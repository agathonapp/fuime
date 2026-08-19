# frozen_string_literal: true

require "rails_helper"

# Fuime: the HTTP boundary of the money-in path.
#
# ── Why this exists, when the handler already has a spec ────────────────────
#
# `spec/services/fuime/payment_webhook_handler_spec.rb` calls the handler
# directly. Every doc in docs/fuime has said, since Phase 0, that **no Stripe
# webhook has ever run** — and what was meant by that is precisely the part a
# handler spec cannot reach: signature verification, and the controller's routing
# of an event to the right handler.
#
# That gap is not academic. In production `FUIME_STRIPE_WEBHOOK_SECRET` is set, so
# every delivery takes the `Stripe::Webhook.construct_event` branch. If that
# branch is wrong, **every** webhook 400s, no sale ever reaches a ledger, and the
# failure is invisible from the app side — the storefront works, the checkout
# works, Stripe shows the payment, and the teenager's ledger stays empty.
#
# In development the secret is typically blank and the controller deliberately
# accepts unsigned events so `stripe listen` works. That is why this runs in the
# test environment, where `allow_unsigned_webhooks?` is false: it forces the
# production branch, which is the one that has never been exercised.
#
# ── The payload is Stripe's, not ours ──────────────────────────────────────
#
# spec/fixtures/fuime/payment_intent_succeeded.json was **captured from Stripe's
# own Events API** (test mode, 2026-08-16) after confirming a real PaymentIntent
# on Fuime's platform account with `pm_card_visa`. Only `client_secret` is
# redacted. Every previous payload in this repository was written from the
# documentation, and PR #28 found two bugs that were invisible until code
# actually ran — so a fixture whose shape came from Stripe is worth more than a
# tidier one we authored.
RSpec.describe "the Stripe webhook endpoint", :merchant_of_record, type: :request do
  let(:secret) { "whsec_#{SecureRandom.hex(16)}" }

  let(:payload) do
    Rails.root.join("spec/fixtures/fuime/payment_intent_succeeded.json").read
  end

  # The venture the captured payload's metadata points at. Created with that
  # exact id so the fixture maps to something without being rewritten.
  let!(:venture) do
    event_id = JSON.parse(payload).dig("data", "object", "metadata", "fuime_event_id").to_i
    create(:event, id: event_id, name: "DevHacks (Demo Event)")
  end

  def intent_id = JSON.parse(payload).dig("data", "object", "id")

  # Stripe's scheme: HMAC-SHA256 over "<timestamp>.<raw body>", hex, as `v1`.
  def signature_header(body, at: Time.now.to_i, key: secret)
    "t=#{at},v1=#{OpenSSL::HMAC.hexdigest('SHA256', key, "#{at}.#{body}")}"
  end

  def deliver(body = payload, header: nil, at: Time.now.to_i)
    post "/fuime/webhooks/stripe",
         params: body,
         headers: {
           "Content-Type"     => "application/json",
           "Stripe-Signature" => header || signature_header(body, at:)
         }
  end

  around do |example|
    old = ENV["FUIME_STRIPE_WEBHOOK_SECRET"]
    ENV["FUIME_STRIPE_WEBHOOK_SECRET"] = secret
    example.run
    old.nil? ? ENV.delete("FUIME_STRIPE_WEBHOOK_SECRET") : ENV["FUIME_STRIPE_WEBHOOK_SECRET"] = old
  end

  def ledger_row = Fuime::VentureLedger.find_row(Fuime::VentureLedger.payment_key(intent_id))
  def fee_row    = Fuime::VentureLedger.find_row(Fuime::VentureLedger.fee_key(intent_id))

  describe "a correctly signed event from Stripe" do
    it "is accepted and reaches the venture's ledger" do
      deliver

      expect(response).to have_http_status(:ok)
      expect(ledger_row).to be_present
      expect(ledger_row.amount_cents).to eq(4500)
    end

    it "posts Fuime's cut as its own visible line" do
      deliver

      expect(fee_row).to be_present
      expect(fee_row.amount_cents).to eq(-225)
    end

    # Stripe retries on any non-2xx, so this is not a nicety.
    it "does not double-post when Stripe retries" do
      deliver
      deliver

      expect(RawPendingDonationTransaction.where(
        donation_transaction_id: Fuime::VentureLedger.payment_key(intent_id)
      ).count).to eq(1)
    end
  end

  describe "an event that did not come from Stripe" do
    it "refuses a forged signature and writes nothing" do
      deliver(header: "t=#{Time.now.to_i},v1=#{'0' * 64}")

      expect(response).to have_http_status(:bad_request)
      expect(ledger_row).to be_nil
    end

    it "refuses a missing signature header" do
      deliver(header: "")

      expect(response).to have_http_status(:bad_request)
      expect(ledger_row).to be_nil
    end

    # Signed with a real algorithm but the wrong key — what an attacker who has
    # read the docs but not the environment would send.
    it "refuses a signature made with a different secret" do
      deliver(header: signature_header(payload, key: "whsec_not_the_one"))

      expect(response).to have_http_status(:bad_request)
      expect(ledger_row).to be_nil
    end

    # The signature covers the body, so a payload edited in flight must fail even
    # though the header is otherwise well-formed. This is the one that matters:
    # the amount is in the body.
    it "refuses a body altered after signing" do
      signed_for = payload
      tampered = payload.sub('"amount_received": 4500', '"amount_received": 450000')
      expect(tampered).not_to eq(payload) # the fixture really did change

      deliver(tampered, header: signature_header(signed_for))

      expect(response).to have_http_status(:bad_request)
      expect(ledger_row).to be_nil
    end

    # Stripe's default tolerance is 5 minutes; an old timestamp is a replayed
    # capture rather than a live delivery.
    it "refuses a timestamp outside the tolerance window" do
      deliver(at: 20.minutes.ago.to_i)

      expect(response).to have_http_status(:bad_request)
      expect(ledger_row).to be_nil
    end

    # A malformed body is refused BEFORE the controller sees it.
    #
    # Worth an example because of what it says about the controller: Rack parses
    # the body when the request declares `Content-Type: application/json`, so
    # `Fuime::WebhooksController`'s own `rescue JSON::ParserError` is
    # **unreachable** on that content type. It is not wrong, just dead — and
    # knowing that is what stops somebody debugging a malformed-payload report by
    # adding logging to a branch that never runs.
    #
    # Rails turns this into a 400 in production; in the test environment
    # `show_exceptions` is off, so it surfaces as the exception itself.
    it "refuses a body that is not JSON, before reaching the controller" do
      # Matched on the message rather than the class: the underlying
      # ActionDispatch::Http::Parameters::ParseError arrives wrapped by the
      # error-page renderer, and which wrapper is used is a Rails detail rather
      # than the behaviour being asserted.
      expect { deliver("not json at all") }
        .to raise_error(/parsing request parameters/)

      expect(ledger_row).to be_nil
    end
  end

  # A missing secret must never degrade to "accept anything" — outside
  # development this endpoint writes to children's ledgers, so an unverified
  # event is an attacker-controlled ledger line.
  describe "when no secret is configured" do
    it "refuses to serve rather than accepting unsigned events" do
      ENV.delete("FUIME_STRIPE_WEBHOOK_SECRET")

      deliver

      expect(response).to have_http_status(:service_unavailable)
      expect(ledger_row).to be_nil
    end
  end

end
