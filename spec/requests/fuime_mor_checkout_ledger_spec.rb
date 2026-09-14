# frozen_string_literal: true

require "rails_helper"

# Fuime: G10 — a successful MoR Checkout hits the ledger through the HTTP
# webhook, and a replay / the twin Stripe event does not double-post.
#
# Sibling of spec/requests/fuime_stripe_webhook_endpoint_spec.rb, which proves
# signature verification against a captured payment_intent.succeeded. This file
# is the Checkout shape: session.completed (the event a Dashboard "Checkout"
# endpoint actually sends) and payment_intent.succeeded (the event the handler
# has always posted from), both signed, both mapping to one venture.
RSpec.describe "MoR Checkout → webhook → ledger", :merchant_of_record, type: :request do
  let(:secret) { "whsec_#{SecureRandom.hex(16)}" }
  let(:event) { create(:event, plan_type: Event::Plan::Standard, name: "Sunset Lawn") }
  let(:amount_cents) { 35_00 }
  let(:intent_id) { "pi_mor_g10_#{SecureRandom.hex(4)}" }
  let(:offer) { create(:fuime_offer, event:, name: "Front lawn mow", price_cents: amount_cents) }
  let(:session_id) { "cs_test_mor_g10_#{SecureRandom.hex(4)}" }

  def fee_cents = event.fuime_fee_cents_on(amount_cents)

  def signature_header(body, at: Time.now.to_i, key: secret)
    "t=#{at},v1=#{OpenSSL::HMAC.hexdigest("SHA256", key, "#{at}.#{body}")}"
  end

  def deliver(payload)
    body = payload.to_json
    post "/fuime/webhooks/stripe",
         params: body,
         headers: {
           "Content-Type"     => "application/json",
           "Stripe-Signature" => signature_header(body)
         }
  end

  def stripe_envelope(type, object)
    {
      id: "evt_#{SecureRandom.hex(8)}",
      object: "event",
      type:,
      livemode: false,
      data: { object: }
    }
  end

  def session_object
    {
      id: session_id,
      object: "checkout.session",
      amount_total: amount_cents,
      payment_intent: intent_id,
      payment_status: "paid",
      status: "complete",
      mode: "payment",
      created: Time.current.to_i,
      metadata: {
        "fuime_event_id"   => event.id.to_s,
        "fuime_event_name" => event.name,
        "fuime_fee_cents"  => fee_cents.to_s,
        "fuime_offer_id"   => offer.id.to_s
      },
      # The shape `billing_address_collection: "required"` produces. Only this
      # event carries it — see the jurisdiction examples at the bottom.
      customer_details: {
        email: "buyer@example.com",
        address: {
          country: "US", state: "CA", postal_code: "94110",
          city: "San Francisco", line1: "1 Market St"
        }
      }
    }
  end

  def intent_object
    {
      id: intent_id,
      object: "payment_intent",
      amount_received: amount_cents,
      created: Time.current.to_i,
      description: "Front and back lawn mow",
      metadata: {
        "fuime_event_id"   => event.id.to_s,
        "fuime_event_name" => event.name,
        "fuime_fee_cents"  => fee_cents.to_s
      }
    }
  end

  def ledger_lines
    CanonicalPendingEventMapping
      .where(event_id: event.id)
      .map(&:canonical_pending_transaction)
  end

  around do |example|
    old = ENV["FUIME_STRIPE_WEBHOOK_SECRET"]
    ENV["FUIME_STRIPE_WEBHOOK_SECRET"] = secret
    example.run
    old.nil? ? ENV.delete("FUIME_STRIPE_WEBHOOK_SECRET") : ENV["FUIME_STRIPE_WEBHOOK_SECRET"] = old
  end

  it "posts gross + fee from checkout.session.completed" do
    deliver(stripe_envelope("checkout.session.completed", session_object))

    expect(response).to have_http_status(:ok)
    expect(ledger_lines.map(&:amount_cents)).to contain_exactly(amount_cents, -fee_cents)
    expect(Fuime::VentureLedger.find_row(Fuime::VentureLedger.payment_key(intent_id))).to be_present
    expect(Fuime::VentureLedger.find_row(Fuime::VentureLedger.payment_key(session_id))).to be_nil
  end

  it "does not double-post when payment_intent.succeeded arrives after the session" do
    deliver(stripe_envelope("checkout.session.completed", session_object))
    deliver(stripe_envelope("payment_intent.succeeded", intent_object))

    expect(response).to have_http_status(:ok)
    expect(ledger_lines.size).to eq(2)
    expect(ledger_lines.sum(&:amount_cents)).to eq(amount_cents - fee_cents)
  end

  it "does not double-post when Stripe retries checkout.session.completed" do
    payload = stripe_envelope("checkout.session.completed", session_object)
    deliver(payload)
    deliver(payload)

    expect(RawPendingDonationTransaction.where(
      donation_transaction_id: Fuime::VentureLedger.payment_key(intent_id)
    ).count).to eq(1)
  end

  it "still posts from payment_intent.succeeded alone (direct PaymentIntent / no Checkout)" do
    deliver(stripe_envelope("payment_intent.succeeded", intent_object))

    expect(response).to have_http_status(:ok)
    expect(ledger_lines.map(&:amount_cents)).to contain_exactly(amount_cents, -fee_cents)
  end

  # Under MoR every operator's sales aggregate under ONE legal entity, so state
  # economic nexus accrues against Fuime rather than against each teenager
  # (MOR_RISK_ACCEPTANCE.md §7). Nexus is measured on history and history cannot
  # be backfilled, so the capture has to happen here, on the live webhook path.
  describe "the buyer's jurisdiction" do
    def jurisdiction = Fuime::Sale.find_by(stripe_payment_intent_id: intent_id)

    it "is recorded from the Checkout Session, keyed to the same id as the ledger" do
      deliver(stripe_envelope("checkout.session.completed", session_object))

      expect(jurisdiction).to have_attributes(
        country: "US", state: "CA", postal_code: "94110",
        amount_cents:, event_id: event.id
      )
    end

    # The bug the create-or-enrich design exists to prevent. Stripe fires both
    # events for one sale and only the session carries an address, so if the
    # PaymentIntent wins the race a create-and-ignore would drop the address
    # permanently — silently, on exactly the sales this record is for.
    it "is filled in by the session even when payment_intent.succeeded landed first" do
      deliver(stripe_envelope("payment_intent.succeeded", intent_object))
      expect(jurisdiction.country).to be_nil

      deliver(stripe_envelope("checkout.session.completed", session_object))

      expect(jurisdiction.country).to eq("US")
      expect(jurisdiction.state).to eq("CA")
    end

    it "keeps one row per sale however many times Stripe delivers" do
      payload = stripe_envelope("checkout.session.completed", session_object)
      deliver(payload)
      deliver(payload)
      deliver(stripe_envelope("payment_intent.succeeded", intent_object))

      expect(Fuime::Sale.where(stripe_payment_intent_id: intent_id).count).to eq(1)
    end

    # Deliberate minimisation: counting nexus needs the jurisdiction, not the
    # buyer's doorstep. Stripe sends city and line1; Fuime does not keep them.
    it "keeps the jurisdiction and not the buyer's street address" do
      deliver(stripe_envelope("checkout.session.completed", session_object))

      expect(jurisdiction.attributes.values_at("country", "state", "postal_code")).to all(be_present)
      expect(jurisdiction.attributes.keys).not_to include("city", "line1")
    end

    # The other half of why this table exists: the ledger aggregates by memo
    # prefix, so nothing could answer "what does this founder sell most of".
    it "records which offer was bought, so per-product revenue is computable" do
      deliver(stripe_envelope("checkout.session.completed", session_object))

      expect(jurisdiction.offer).to eq(offer)
      expect(Fuime::Sale.revenue_by_offer).to eq(offer.id => amount_cents)
    end

    # A sale Fuime cannot place is a thing the nexus report must be able to SEE.
    # Dropping the row would make it invisible instead.
    it "records a sale Stripe gave no address for, rather than dropping it" do
      deliver(stripe_envelope("payment_intent.succeeded", intent_object))

      expect(jurisdiction).to be_present
      expect(Fuime::Sale.unknown_jurisdiction).to include(jurisdiction)
    end
  end

  # An operator's subscription earns money every month, and every month of it
  # has to reach their ledger. Signup and renewal both arrive as `invoice.paid`
  # — see PaymentWebhookHandler#record_subscription_invoice for why neither the
  # Checkout Session nor the PaymentIntent can serve here.
  describe "a subscription renewal" do
    let(:renewal_intent_id) { "pi_renewal_#{SecureRandom.hex(4)}" }
    let(:sub_amount_cents) { 9_99 }

    def sub_fee_cents = event.fuime_fee_cents_on(sub_amount_cents)

    def invoice_object(intent: renewal_intent_id, kind: Fuime::PaymentLinkService::OPERATOR_SALE_KIND,
                       amount: sub_amount_cents)
      {
        id: "in_#{SecureRandom.hex(6)}",
        object: "invoice",
        amount_paid: amount,
        created: Time.current.to_i,
        period_end: 30.days.from_now.to_i,
        payment_intent: intent,
        subscription_details: {
          metadata: {
            "fuime_event_id"          => event.id.to_s,
            "fuime_event_name"        => event.name,
            "fuime_offer_name"        => "Drill plan tool",
            # Stamped at signup, and deliberately stale by the time a renewal
            # arrives — the handler must recompute rather than trust it.
            "fuime_fee_cents"         => "1",
            "fuime_subscription_kind" => kind
          }.compact
        }
      }
    end

    it "posts gross and fee to the venture's ledger" do
      deliver(stripe_envelope("invoice.paid", invoice_object))

      expect(response).to have_http_status(:ok)
      expect(ledger_lines.map(&:amount_cents)).to contain_exactly(sub_amount_cents, -sub_fee_cents)
    end

    # The signup metadata carries the fee as it was the day the buyer subscribed.
    # A renewal is a new sale, possibly a year later, and the venture's plan may
    # have changed — so the fee is recomputed from the plan the money came from.
    it "recomputes the fee instead of reusing the one stamped at signup" do
      deliver(stripe_envelope("invoice.paid", invoice_object))

      fee_line = ledger_lines.find { |line| line.amount_cents.negative? }
      expect(fee_line.amount_cents).to eq(-sub_fee_cents)
      expect(fee_line.amount_cents).not_to eq(-1)
    end

    it "names what was bought and which period it was for" do
      deliver(stripe_envelope("invoice.paid", invoice_object))

      memo = ledger_lines.find { |line| line.amount_cents.positive? }.memo
      expect(memo).to include("Drill plan tool")
      expect(memo).to include("billing period ending")
    end

    it "posts each month separately, and never the same month twice" do
      deliver(stripe_envelope("invoice.paid", invoice_object(intent: "pi_month_one")))
      deliver(stripe_envelope("invoice.paid", invoice_object(intent: "pi_month_two")))
      # Stripe retrying month two.
      deliver(stripe_envelope("invoice.paid", invoice_object(intent: "pi_month_two")))

      expect(ledger_lines.sum(&:amount_cents)).to eq((sub_amount_cents - sub_fee_cents) * 2)
    end

    # Fuime's own family-plan invoices arrive on this same endpoint. Posting one
    # would credit a founder with money Fuime charged their parent.
    it "ignores an invoice that is not an operator's sale" do
      deliver(stripe_envelope("invoice.paid", invoice_object(kind: nil)))

      expect(response).to have_http_status(:ok)
      expect(ledger_lines).to be_empty
    end

    # A fully discounted period or a converting trial. Real, and not revenue.
    it "posts nothing for a zero-amount invoice" do
      deliver(stripe_envelope("invoice.paid", invoice_object(amount: 0)))

      expect(response).to have_http_status(:ok)
      expect(ledger_lines).to be_empty
    end
  end
end
