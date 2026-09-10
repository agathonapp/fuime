# frozen_string_literal: true

require "rails_helper"

# Fuime: G10 recovery path — a succeeded platform PaymentIntent whose webhook
# never arrived still becomes a ledger line, and one that already arrived does
# not become a second line.
RSpec.describe Fuime::MissedMorPaymentSweep do
  let(:event) { create(:event, plan_type: Event::Plan::Standard) }

  def intent(id:, event_id: event.id, status: "succeeded", invoice: nil, livemode: false)
    Stripe::PaymentIntent.construct_from(
      id:,
      object: "payment_intent",
      status:,
      amount: 35_00,
      amount_received: 35_00,
      created: Time.current.to_i,
      livemode:,
      invoice:,
      metadata: event_id.present? ? { "fuime_event_id" => event_id.to_s } : {}
    )
  end

  def stub_list(*intents)
    list = double("Stripe::ListObject")
    allow(list).to receive(:auto_paging_each) { |&block| intents.each(&block) }
    allow(Stripe::PaymentIntent).to receive(:list).and_return(list)
  end

  def ledger_lines
    CanonicalPendingEventMapping
      .where(event_id: event.id)
      .map(&:canonical_pending_transaction)
  end

  it "posts a succeeded storefront intent that has no ledger row" do
    stub_list(intent(id: "pi_missed_1"))

    result = described_class.sweep!(since: 1.hour.ago)

    expect(result[:posted]).to eq(1)
    expect(ledger_lines.size).to eq(2)
    expect(Fuime::VentureLedger.find_row(Fuime::VentureLedger.payment_key("pi_missed_1"))).to be_present
  end

  it "is a no-op for an intent the webhook already recorded" do
    existing = intent(id: "pi_already")
    Fuime::PaymentWebhookHandler.new(
      event: Stripe::Event.construct_from(type: "payment_intent.succeeded", data: { object: existing })
    ).handle
    stub_list(existing)

    expect { described_class.sweep!(since: 1.hour.ago) }
      .not_to(change { ledger_lines.size })
  end

  it "skips Billing invoices, unpaid intents, and intents with no venture" do
    stub_list(
      intent(id: "pi_invoice", invoice: "in_family"),
      intent(id: "pi_open", status: "requires_payment_method"),
      intent(id: "pi_orphan", event_id: nil)
    )

    result = described_class.sweep!(since: 1.hour.ago)

    expect(result[:posted]).to eq(0)
    expect(ledger_lines).to be_empty
  end

  it "walks every page Stripe returns, not just list.data" do
    first = intent(id: "pi_page_1")
    second = intent(id: "pi_page_2")
    list = double("Stripe::ListObject")
    expect(list).to receive(:auto_paging_each) { |&block|
      [first, second].each(&block)
    }
    allow(Stripe::PaymentIntent).to receive(:list).and_return(list)

    result = described_class.sweep!(since: 1.hour.ago)

    expect(result[:posted]).to eq(2)
    expect(Fuime::VentureLedger.find_row(Fuime::VentureLedger.payment_key("pi_page_2"))).to be_present
  end
end
