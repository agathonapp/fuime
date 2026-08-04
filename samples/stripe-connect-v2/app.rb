# frozen_string_literal: true

# ============================================================================
# Stripe Connect (V2 Core Accounts) — sample integration
# ============================================================================
#
# Read top to bottom. The flows, in order:
#
#   1. Create a connected account            V2  core.accounts.create
#   2. Onboard it via an Account Link        V2  core.account_links.create
#   3. Read its live status                  V2  core.accounts.retrieve
#   4. Create products on it                V1  products.create   + Stripe-Account
#   5. A public storefront                   V1  products.list     + Stripe-Account
#   6. Take a direct charge with a fee       V1  checkout.sessions + Stripe-Account
#   7. Charge the account a subscription     V1  checkout.sessions (customer_account)
#   8. A billing portal for that subscription
#   9. Webhooks: THIN (v2) and SNAPSHOT (v1) — two endpoints, two secrets
#
# ── This is a SAMPLE, and it is not Fuime's shipped integration ─────────────
#
# The main Rails app already has a working Connect integration built on the V1
# Accounts API (`Stripe::Account.create` with `controller` properties). This sample
# uses the newer V2 Core Accounts API, which is a genuinely different object model.
# Before copying anything here into the product, read README.md — several defaults
# in this sample would REVERSE deliberate decisions in the real app, and one of them
# would put a minor's data on a public URL.
#
# Run:  bundle install && bundle exec ruby app.rb
# ============================================================================

require "sinatra"
require "stripe"
require "dotenv/load"
require "json"
require "bigdecimal"

set :port, 4242
set :bind, "0.0.0.0"
# Sinatra's default is to only show errors in the browser for localhost; keep the
# console loud instead, because most failures here are Stripe API errors worth
# reading in full.
set :show_exceptions, false

# ============================================================================
# 1. CONFIGURATION
# ============================================================================
#
# Every required value is fetched through `required_env`, which fails at BOOT with
# an actionable message rather than at the first API call with a nil key. A missing
# key that surfaces as "Invalid API Key provided: " three screens into a flow is the
# single most common way to lose an afternoon on a Stripe integration.

def required_env(name, hint)
  value = ENV[name].to_s.strip
  return value unless value.empty?

  abort <<~ERROR

    ┌───────────────────────────────────────────────────────────────────────┐
    │ Missing required configuration: #{name}
    └───────────────────────────────────────────────────────────────────────┘

    #{hint}

    Set it in samples/stripe-connect-v2/.env (copy .env.example to start).

  ERROR
end

def optional_env(name, default)
  value = ENV[name].to_s.strip
  value.empty? ? default : value
end

STRIPE_SECRET_KEY = required_env(
  "STRIPE_SECRET_KEY",
  "Your PLATFORM account's secret key, from Dashboard -> Developers -> API keys.\n" \
  "Use a TEST key (sk_test_...). This sample creates real Stripe objects, and in\n" \
  "live mode those involve real money."
)

# Fail fast on a live key. This sample has no guard rails worth trusting with real
# money, and the cost of the mistake is asymmetric.
if STRIPE_SECRET_KEY.start_with?("sk_live_")
  abort "\nRefusing to start: STRIPE_SECRET_KEY is a LIVE key. This sample is test mode only.\n\n"
end

APP_BASE_URL = optional_env("APP_BASE_URL", "http://localhost:4242")
PLATFORM_FEE_BPS = optional_env("PLATFORM_FEE_BPS", "400").to_i

# ── The Stripe client ───────────────────────────────────────────────────────
#
# One client, used for every request. The API version is NOT set here on purpose:
# the SDK pins the version it was built against, which is what you want. Pinning it
# by hand means a gem upgrade silently keeps talking to an old API.
STRIPE = Stripe::StripeClient.new(STRIPE_SECRET_KEY)

# ============================================================================
# 2. STORAGE
# ============================================================================
#
# An in-memory Hash, because this is a sample. It resets on restart.
#
# TODO(real app): the main Rails app already has the right table for this —
# `stripe_connected_accounts`, one row per venture, with `event_id` UNIQUE as the
# anti-commingling guarantee. Replace `USERS` with that model. See
# app/models/stripe_connected_account.rb.
#
# Note what is stored and what is not: the account ID is stored, the account STATUS
# is not. Status is read live from the API on every render (see #account_status).
# Caching onboarding status is how you end up telling a user they can take payments
# when Stripe disabled them an hour ago.
USERS = {}

def upsert_user(email:, display_name:, account_id:)
  USERS[account_id] = { email: email, display_name: display_name, account_id: account_id }
end

# ============================================================================
# 3. HELPERS
# ============================================================================

# Stripe objects expose nested fields as further Stripe objects, and `to_h` is not
# reliably deep across SDK versions — it can succeed on the first key and raise on
# the second. A JSON round-trip is the only conversion that is deep for every shape,
# including arrays of objects. (Learned the hard way in the main app; see
# app/services/fuime/stripe_hash.rb.)
def deep_hash(object)
  return {} if object.nil?

  JSON.parse(object.to_json, symbolize_names: true)
rescue StandardError
  {}
end

# Read a connected account's live status straight from the API.
#
# `include:` is required for these sub-objects — V2 omits `configuration` and
# `requirements` unless you ask, and their absence looks identical to "not ready".
def account_status(account_id)
  account = STRIPE.v2.core.accounts.retrieve(
    account_id,
    { include: ["configuration.merchant", "requirements"] }
  )
  data = deep_hash(account)

  card_payments = data.dig(:configuration, :merchant, :capabilities, :card_payments, :status)

  # `minimum_deadline.status` is Stripe's summary of whether anything is outstanding.
  # "currently_due" and "past_due" both mean the user must act; anything else means
  # they are done for now.
  requirements_status = data.dig(:requirements, :summary, :minimum_deadline, :status)

  {
    id: data[:id],
    display_name: data[:display_name],
    # The single question a storefront actually has.
    ready_to_process: card_payments == "active",
    card_payments_status: card_payments || "not requested",
    requirements_status: requirements_status || "none",
    onboarding_complete: !["currently_due", "past_due"].include?(requirements_status),
    raw: data
  }
rescue Stripe::StripeError => e
  { id: account_id, error: e.message, ready_to_process: false, onboarding_complete: false }
end

# Fee on a storefront sale, in cents. Basis points so a 4% fee is expressed once.
def application_fee_for(amount_cents)
  (amount_cents * PLATFORM_FEE_BPS / 10_000.0).round
end

# Resolve the connected account ID from a thin event notification.
#
# The notification itself carries only id/type/created/livemode/reason/context — not
# the account. `fetch_event` retrieves the full event, whose `related_object.id` is
# the account for every `v2.core.account[...]` type.
#
# Two fallbacks are tried because the exact envelope has moved between API versions,
# and a webhook handler that raises on an unexpected shape turns a schema change into
# an outage. Returning nil lets the caller log something useful instead.
def account_id_from(notification)
  event = notification.fetch_event
  data = deep_hash(event)

  data.dig(:related_object, :id) ||
    data.dig(:data, :account, :id) ||
    data.dig(:context, :account)
rescue Stripe::StripeError => e
  warn "[thin] could not fetch event #{notification.id}: #{e.message}"
  nil
end

def h(text)
  Rack::Utils.escape_html(text.to_s)
end

# ============================================================================
# 4. DASHBOARD — the platform's own UI
# ============================================================================

get "/" do
  # Status is fetched per account on every load. Fine for a sample with a handful of
  # accounts; in production this wants caching with a short TTL plus webhook-driven
  # invalidation, not a synchronous call per row.
  @accounts = USERS.values.map { |u| u.merge(status: account_status(u[:account_id])) }
  @platform_price_id = ENV["STRIPE_PLATFORM_PRICE_ID"].to_s.strip
  @fee_percent = PLATFORM_FEE_BPS / 100.0
  erb :dashboard
end

# ── FLOW 1: create a connected account (V2) ─────────────────────────────────
#
# Note there is NO top-level `type:`. V2 has no express/standard/custom; the
# behaviour that `type` used to imply is now expressed explicitly through
# `dashboard` and `defaults.responsibilities`, which is a clearer model: you say who
# collects fees and who eats losses rather than picking a bundle and looking up what
# it means.
post "/accounts" do
  display_name = params[:display_name].to_s.strip
  email = params[:email].to_s.strip

  halt 400, erb(:error, locals: { message: "A business name and an email are both required." }) if
    display_name.empty? || email.empty?

  begin
    account = STRIPE.v2.core.accounts.create(
      {
        display_name: display_name,
        contact_email: email,
        identity: {
          # ISO 3166-1 alpha-2, lowercase. The account's country is immutable, so
          # getting it from the user rather than hardcoding matters in a real app.
          country: "us"
        },
        # 'full' gives the account holder a complete Stripe Dashboard.
        #
        # ⚠️ THE MAIN APP DELIBERATELY DOES THE OPPOSITE. Fuime sets
        # `stripe_dashboard.type = none` so families stay inside Fuime and never see
        # a Stripe UI. Read README.md before copying this value.
        dashboard: "full",
        defaults: {
          responsibilities: {
            # Stripe collects its fees directly from the account, and Stripe carries
            # negative-balance losses. The second one is the important one: it is why
            # a platform does not need reserves to cover a chargeback its user cannot
            # pay. The main app makes the same choice (`losses.payments = stripe`).
            fees_collector: "stripe",
            losses_collector: "stripe"
          }
        },
        configuration: {
          # An empty `customer: {}` still matters: it makes this account a CUSTOMER of
          # your platform, which is what lets you bill it a subscription later using
          # `customer_account:` (flow 7). Omit it and the subscription flow has
          # nothing to charge.
          customer: {},
          merchant: {
            capabilities: {
              # Requested up front so Stripe collects everything in one onboarding
              # pass instead of interrupting the user twice.
              card_payments: { requested: true }
            }
          }
        }
      }
    )

    upsert_user(email: email, display_name: display_name, account_id: account.id)

    # TODO(real app): persist the user -> account_id mapping here, inside the same
    # transaction as whatever created the user. The main app writes the local row
    # BEFORE the Stripe call for exactly this reason: a crash between the two must
    # leave a retryable record rather than a Stripe account you have no reference to.
    redirect "/"
  rescue Stripe::StripeError => e
    status 500
    erb :error, locals: { message: "Stripe rejected the account: #{e.message}" }
  end
end

# ── FLOW 2: onboarding via an Account Link (V2) ─────────────────────────────
#
# Account Links are single-use and short-lived. Mint one per click; never store or
# email one.
post "/accounts/:account_id/onboarding_link" do
  account_id = params[:account_id]

  begin
    link = STRIPE.v2.core.account_links.create(
      {
        account: account_id,
        use_case: {
          type: "account_onboarding",
          account_onboarding: {
            # Both configurations, matching what was requested at creation. Asking
            # for a configuration here that the account does not have is an error.
            configurations: %w[merchant customer],
            # Where Stripe sends the user if the link expires before they finish.
            # It must mint a NEW link, which is why it points back at the dashboard.
            refresh_url: "#{APP_BASE_URL}/",
            # Where Stripe returns them on completion.
            #
            # Returning here does NOT mean onboarding succeeded — Stripe is explicit
            # that it only means the flow was entered and exited. That is why the
            # dashboard re-reads status from the API rather than trusting this
            # redirect. Treating the return trip as success is the classic Connect bug.
            return_url: "#{APP_BASE_URL}/?returned_from=#{account_id}"
          }
        }
      }
    )

    redirect link.url
  rescue Stripe::StripeError => e
    status 500
    erb :error, locals: { message: "Could not start onboarding: #{e.message}" }
  end
end

# ── FLOW 4: create a product ON the connected account ───────────────────────
#
# The `stripe_account:` option sends the Stripe-Account header, which makes the
# product belong to the connected account rather than to your platform. Forget it
# and you silently build a catalogue on the wrong account.
post "/accounts/:account_id/products" do
  account_id = params[:account_id]
  name = params[:name].to_s.strip
  description = params[:description].to_s.strip
  # Accepts what a person types: "12", "12.50", "$1,250.00".
  dollars = params[:price].to_s.gsub(/[^\d.]/, "")

  if name.empty? || dollars.empty?
    halt 400, erb(:error, locals: { message: "A product name and a price are both required." })
  end

  price_in_cents = (BigDecimal(dollars) * 100).round
  if price_in_cents <= 0
    halt 400, erb(:error, locals: { message: "Price must be greater than zero." })
  end

  begin
    STRIPE.v1.products.create(
      {
        name: name,
        description: description.empty? ? nil : description,
        # Creates the Product and its default Price in one call.
        default_price_data: {
          unit_amount: price_in_cents,
          currency: "usd"
        }
      }.compact,
      { stripe_account: account_id }
    )

    redirect "/"
  rescue Stripe::StripeError => e
    status 500
    erb :error, locals: { message: "Could not create the product: #{e.message}" }
  end
end

# ============================================================================
# 5. STOREFRONT — what the connected account's customers see
# ============================================================================
#
# ⚠️ THE ACCOUNT ID IS IN THE URL, AND YOU SHOULD NOT SHIP THAT.
#
# It is used here because it keeps the sample to one moving part. In production use
# your own opaque, user-chosen identifier (a slug) and look the account up from it.
# Reasons, in increasing order of seriousness:
#
#   1. `acct_...` is a Stripe-internal identifier and leaks your data model.
#   2. It is unguessable but not secret, and it appears in logs, referrers and
#      analytics.
#   3. FOR THE MAIN APP SPECIFICALLY: these storefronts belong to businesses run by
#      MINORS. Fuime's real storefront is keyed on `event.slug` and deliberately
#      publishes less than HCB's transparency page did — no balance, owner name only
#      when the owner is a confirmed adult. Putting a minor's Stripe account ID on a
#      public URL is a step backwards from that. See PRODUCTION_READINESS.md §2.2.
get "/storefront/:account_id" do
  @account_id = params[:account_id]
  @status = account_status(@account_id)

  begin
    products = STRIPE.v1.products.list(
      {
        limit: 20,
        active: true,
        # Without expanding it, `default_price` is just an ID and you cannot show a
        # price without an N+1 of extra calls.
        expand: ["data.default_price"]
      },
      { stripe_account: @account_id }
    )
    @products = deep_hash(products)[:data] || []
  rescue Stripe::StripeError => e
    @products = []
    @load_error = e.message
  end

  erb :storefront
end

# ── FLOW 6: direct charge with an application fee ───────────────────────────
#
# `stripe_account:` makes this a DIRECT charge: the connected account is the merchant
# of record, the funds settle to it, and refunds and disputes debit its balance. The
# platform is never in the flow of funds, which is the property that keeps a platform
# out of money-transmission territory.
#
# `application_fee_amount` is how the platform is paid. Stripe deducts it and moves
# it to the platform balance automatically, so there is nothing to reconcile.
post "/storefront/:account_id/checkout" do
  account_id = params[:account_id]
  price_id = params[:price_id]
  product_name = params[:product_name].to_s
  amount_cents = params[:amount_cents].to_i

  if price_id.to_s.empty? || amount_cents <= 0
    halt 400, erb(:error, locals: { message: "That product is not purchasable." })
  end

  fee = application_fee_for(amount_cents)

  begin
    session = STRIPE.v1.checkout.sessions.create(
      {
        mode: "payment",
        # The Price already exists on the connected account, so reference it rather
        # than restating the amount. Restating it is how a storefront ends up
        # charging a different number than it displayed.
        line_items: [{ price: price_id, quantity: 1 }],
        payment_intent_data: {
          application_fee_amount: fee,
          # Shows on the buyer's statement. They bought from the venture, not from
          # your platform, so this should say the venture.
          statement_descriptor_suffix: product_name[0, 22].strip
        }.compact,
        success_url: "#{APP_BASE_URL}/success?session_id={CHECKOUT_SESSION_ID}&account_id=#{account_id}",
        cancel_url: "#{APP_BASE_URL}/storefront/#{account_id}"
      },
      { stripe_account: account_id }
    )

    redirect session.url
  rescue Stripe::StripeError => e
    status 500
    erb :error, locals: { message: "Could not start checkout: #{e.message}" }
  end
end

get "/success" do
  @account_id = params[:account_id]
  session_id = params[:session_id]

  begin
    # Retrieved with the connected-account header because the session lives on that
    # account, not on the platform.
    @session = deep_hash(
      STRIPE.v1.checkout.sessions.retrieve(session_id, { stripe_account: @account_id })
    )
  rescue Stripe::StripeError => e
    @error = e.message
  end

  erb :success
end

# ============================================================================
# 6. SUBSCRIPTIONS — the platform charging the connected account
# ============================================================================
#
# This is the platform billing its USER, which is the opposite direction from the
# storefront above. It works because the account was created with
# `configuration.customer: {}`.
#
# The key V2 idea: one ID serves as both the connected account and the customer.
# There is no separate `cus_...` to create or reconcile — pass `customer_account:`
# with the `acct_...` ID. Note this call has NO `stripe_account:` option, because
# the subscription belongs to the PLATFORM.
post "/accounts/:account_id/subscribe" do
  account_id = params[:account_id]
  price_id = required_env(
    "STRIPE_PLATFORM_PRICE_ID",
    "A recurring Price on your PLATFORM account, created in Dashboard -> Product\n" \
    "catalogue. This is what you charge your users for using the platform."
  )

  begin
    session = STRIPE.v1.checkout.sessions.create(
      {
        # NOT `customer:`. For a V2 account this is `customer_account:`.
        customer_account: account_id,
        mode: "subscription",
        line_items: [{ price: price_id, quantity: 1 }],
        success_url: "#{APP_BASE_URL}/?subscribed=#{account_id}&session_id={CHECKOUT_SESSION_ID}",
        cancel_url: "#{APP_BASE_URL}/"
      }
    )

    redirect session.url
  rescue Stripe::StripeError => e
    status 500
    erb :error, locals: { message: "Could not start the subscription: #{e.message}" }
  end
end

# ── FLOW 8: billing portal ─────────────────────────────────────────────────
#
# Stripe-hosted management of the subscription: change plan, update card, cancel.
# Building this yourself is weeks of work for a worse result.
post "/accounts/:account_id/billing_portal" do
  account_id = params[:account_id]

  begin
    session = STRIPE.v1.billing_portal.sessions.create(
      {
        customer_account: account_id,
        return_url: "#{APP_BASE_URL}/"
      }
    )
    redirect session.url
  rescue Stripe::StripeError => e
    status 500
    erb :error, locals: {
      message: "Could not open the billing portal: #{e.message}\n\n" \
               "If this says no configuration exists, save your portal settings once at " \
               "Dashboard -> Settings -> Billing -> Customer portal."
    }
  end
end

# ============================================================================
# 7. WEBHOOKS
# ============================================================================
#
# TWO endpoints, TWO signing secrets, two different payload styles. This is the part
# people get wrong most often, so it is worth being explicit:
#
#   THIN (v2)     — account requirements and capability changes. The payload is
#                   deliberately minimal; you fetch the full event to see anything.
#   SNAPSHOT (v1) — subscriptions, invoices, payment methods. The payload contains
#                   the full object.
#
# Verifying a thin event against the snapshot secret fails, and vice versa. If every
# event is suddenly a signature error, check you have not crossed the two.

# ── THIN events (V2 accounts) ──────────────────────────────────────────────
#
# Local listener:
#
#   stripe listen \
#     --thin-events 'v2.core.account[requirements].updated,v2.core.account[configuration.merchant].capability_status_updated,v2.core.account[configuration.customer].capability_status_updated' \
#     --forward-thin-to localhost:4242/webhooks/thin
#
# Why these matter beyond setup: account requirements change over time because
# regulators and card networks change what they need. An account that works today can
# be disabled next month with no action by the user. Without this endpoint, the first
# you hear of it is a user asking why their storefront went dark.
post "/webhooks/thin" do
  payload = request.body.read
  signature = request.env["HTTP_STRIPE_SIGNATURE"]
  secret = required_env(
    "STRIPE_THIN_WEBHOOK_SECRET",
    "Signing secret printed by `stripe listen --thin-events ... --forward-thin-to ...`,\n" \
    "or from Dashboard -> Developers -> Webhooks for a destination with payload style THIN."
  )

  begin
    # ── Ruby's method is NOT `parse_thin_event` ────────────────────────────
    #
    # The JS SDK calls this `parseThinEvent`. stripe-ruby has no such method and no
    # `Thin*` class at all — it names the concept "event notification":
    #
    #   client.parse_event_notification(payload, sig_header, secret)
    #     => Stripe::V2::Core::EventNotification
    #        responds to: id, type, created, livemode, reason, context, fetch_event
    #
    # Verified by introspecting stripe-ruby 19.4.0 rather than translating the JS
    # example, which would have failed with NoMethodError on the first webhook.
    notification = STRIPE.parse_event_notification(payload, signature, secret)
  rescue Stripe::SignatureVerificationError
    # 400 tells Stripe not to retry. A bad signature will never become good.
    halt 400, "Invalid signature"
  end

  begin
    # `type` is on the notification itself, so the dispatch happens BEFORE any network
    # call. Only the branches that need the account then fetch it. Fetching first would
    # mean an API round trip for every event type you ignore, which at volume is a lot
    # of latency spent learning you did not care.
    case notification.type
    when "v2.core.account[requirements].updated"
      # `fetch_event` pulls the full event, whose `related_object.id` is the account.
      # This is the point of the thin model: you read current state rather than acting
      # on a payload that may be minutes stale by the time it arrives.
      account_id = account_id_from(notification)
      status = account_status(account_id)
      puts "[thin] requirements updated for #{account_id}: " \
           "status=#{status[:requirements_status]} complete=#{status[:onboarding_complete]}"

      # TODO(real app): if requirements are now outstanding, email the account holder
      # with what is needed. In Fuime that email goes to the GUARDIAN, not the minor —
      # the guardian is the account owner and the only person who can supply identity
      # details (CLAUDE.md L2).

    when "v2.core.account[configuration.merchant].capability_status_updated"
      account_id = account_id_from(notification)
      status = account_status(account_id)
      puts "[thin] merchant capability changed for #{account_id}: " \
           "card_payments=#{status[:card_payments_status]}"

      # TODO(real app): this is the transition that turns a storefront on and off.
      # Persist it and invalidate any cached "can this account take payments" answer.

    when "v2.core.account[configuration.customer].capability_status_updated"
      puts "[thin] customer capability changed for #{account_id_from(notification)}"
      # Affects whether you can bill this account a subscription.

    when "v2.core.account[configuration.recipient].capability_status_updated"
      puts "[thin] recipient capability changed for #{account_id_from(notification)}"
      # Affects whether you can send money TO this account.

    else
      # Logged rather than ignored. Stripe adds event types, and a destination
      # subscribed to something nobody handles is invisible until it matters.
      puts "[thin] unhandled event type: #{notification.type}"
    end
  rescue Stripe::StripeError => e
    # 500 so Stripe retries. Handlers must be idempotent, because it will.
    status 500
    return "Handler error: #{e.message}"
  end

  status 200
  "ok"
end

# ── SNAPSHOT events (V1) — subscriptions and billing ───────────────────────
#
# Local listener:
#
#   stripe listen --forward-to localhost:4242/webhooks/snapshot
#
# The reason this endpoint exists rather than trusting the checkout redirect: a
# subscription's state changes long after checkout, without the user visiting your
# app. Cancellations, failed payments and downgrades all arrive here or nowhere.
post "/webhooks/snapshot" do
  payload = request.body.read
  signature = request.env["HTTP_STRIPE_SIGNATURE"]
  secret = required_env(
    "STRIPE_SNAPSHOT_WEBHOOK_SECRET",
    "Signing secret printed by `stripe listen --forward-to localhost:4242/webhooks/snapshot`.\n" \
    "This is a DIFFERENT secret from the thin-events listener."
  )

  begin
    event = Stripe::Webhook.construct_event(payload, signature, secret)
  rescue JSON::ParserError
    halt 400, "Invalid payload"
  rescue Stripe::SignatureVerificationError
    halt 400, "Invalid signature"
  end

  object = event.data.object
  data = deep_hash(object)

  # For a V2 account there is no `customer` ID to key on. The account ID arrives as
  # `customer_account` and has the shape `acct_...`.
  account_id = data[:customer_account]

  case event.type
  when "customer.subscription.created", "customer.subscription.updated"
    item = (data[:items] || {})[:data]&.first || {}
    price_id = item.dig(:price, :id)

    if data[:pause_collection]
      # Paused. `resumes_at` is nil for an indefinite pause.
      puts "[snapshot] subscription PAUSED for #{account_id}, resumes #{data.dig(:pause_collection, :resumes_at).inspect}"
    elsif data[:cancel_at_period_end]
      # Not cancelled yet. Access continues to the end of the period, and the user can
      # still reactivate — which arrives as another `updated` with this back to false.
      puts "[snapshot] subscription set to cancel at period end for #{account_id}"
    else
      puts "[snapshot] subscription active for #{account_id} on price #{price_id} (status #{data[:status]})"
    end

    # TODO(real app): write subscription status + price ID + current_period_end for
    # this account. This is the record your entitlement checks read, so it must be
    # written from here rather than from the checkout success page — the success page
    # is not visited on a renewal, a cancellation or a failed payment.

  when "customer.subscription.deleted"
    puts "[snapshot] subscription ENDED for #{account_id}"
    # TODO(real app): revoke access.

  when "invoice.paid"
    puts "[snapshot] invoice paid for #{account_id}: #{data[:id]}"
    # TODO(real app): extend the paid-through date. This, not subscription.updated, is
    # the event that proves money actually arrived.

  when "invoice.payment_failed"
    puts "[snapshot] invoice payment FAILED for #{account_id}: #{data[:id]}"
    # TODO(real app): start a dunning flow. Do not revoke immediately — Stripe retries.

  when "payment_method.attached", "payment_method.detached"
    puts "[snapshot] payment method #{event.type.split('.').last} for #{data[:customer_account] || data[:customer]}"

  when "customer.updated"
    puts "[snapshot] customer updated; default PM = " \
         "#{data.dig(:invoice_settings, :default_payment_method).inspect}"
    # TODO(real app): treat everything here as billing information only. Never use a
    # customer's billing email as a login credential.

  when "customer.tax_id.created", "customer.tax_id.updated", "customer.tax_id.deleted"
    puts "[snapshot] tax ID #{event.type.split('.').last}: #{data[:value].inspect} " \
         "verification=#{data.dig(:verification, :status).inspect}"

  when "billing_portal.configuration.created", "billing_portal.configuration.updated",
       "billing_portal.session.created"
    puts "[snapshot] #{event.type}"

  else
    puts "[snapshot] unhandled event type: #{event.type}"
  end

  status 200
  "ok"
end

# ============================================================================
# 8. ERROR PAGE
# ============================================================================

error do
  status 500
  erb :error, locals: { message: env["sinatra.error"]&.message || "Something went wrong." }
end
