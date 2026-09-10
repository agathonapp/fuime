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
        "fuime_fee_cents"  => fee_cents.to_s
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
end
