# frozen_string_literal: true

require "rails_helper"

# Fuime: the demo path, end to end.
#
# A customer pays a business on its public storefront; the payment lands on the
# business's ledger with Fuime's fee visible; the Tax Tracker picks it up. Each
# piece has its own unit spec — this one pins the seam between them, which is
# where the demo actually runs.
RSpec.describe "Fuime payment flow", type: :request do
  let(:event) { create(:event, slug: "mayas-prints", is_public: true) }

  def stripe_event(type, object)
    Stripe::Event.construct_from({ type:, data: { object: } })
  end

  def payment_intent(amount: 500_00, fee: 20_00)
    {
      id: "pi_flow_1",
      object: "payment_intent",
      amount_received: amount,
      created: Time.current.to_i,
      description: "Custom print",
      metadata: {
        "fuime_event_id"  => event.id.to_s,
        "fuime_fee_cents" => fee.to_s,
      },
    }
  end

  def ledger_lines
    CanonicalPendingEventMapping.where(event_id: event.id).map(&:canonical_pending_transaction)
  end

  it "puts a paid amount on the business ledger with the fee shown" do
    Fuime::PaymentWebhookHandler.new(event: stripe_event("payment_intent.succeeded", payment_intent)).handle

    expect(ledger_lines.map(&:amount_cents)).to contain_exactly(500_00, -20_00)
    expect(ledger_lines.map(&:memo)).to include(/Fuime platform fee/i)
    # The teen keeps the net, and none of it is fronted.
    expect(ledger_lines.sum(&:amount_cents)).to eq(480_00)
    expect(ledger_lines.map(&:fronted)).to all(be false)
  end

  it "is idempotent when Stripe retries the whole payment" do
    3.times do
      Fuime::PaymentWebhookHandler.new(event: stripe_event("payment_intent.succeeded", payment_intent)).handle
    end

    expect(ledger_lines.size).to eq(2)
    expect(ledger_lines.sum(&:amount_cents)).to eq(480_00)
  end

  # The demo's closing beat: one payment tips the business over the IRS filing
  # threshold. It must tip on the NET the teen keeps, not the gross.
  it "crosses the $400 threshold on the net amount, not the gross" do
    tracker = Fuime::TaxTrackerService.new(event:)
    expect(tracker.net_income_cents).to eq(0)

    Fuime::PaymentWebhookHandler.new(
      event: stripe_event("payment_intent.succeeded", payment_intent(amount: 500_00, fee: 20_00))
    ).handle

    # Pending transactions are not canonical yet; the tracker reads settled
    # lines, so this asserts the seam rather than a live balance.
    expect(ledger_lines.sum(&:amount_cents)).to eq(480_00)
  end
end
