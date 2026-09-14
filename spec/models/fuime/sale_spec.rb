# frozen_string_literal: true

require "rails_helper"

# The behaviour worth pinning here is the enrichment, not the columns.
#
# A sale reaches Fuime as TWO Stripe events with different payloads —
# `checkout.session.completed` carries `customer_details.address` and
# `payment_intent.succeeded` does not — so the naive create-and-ignore loses the
# buyer's jurisdiction every time the PaymentIntent wins the race. That loss is
# silent, and it lands on exactly the data this table exists to hold.
RSpec.describe Fuime::Sale do
  let(:event) { create(:event) }

  # A stand-in for Stripe's address object — it only has to answer #country,
  # #state and #postal_code. Held in a `let` rather than assigned to a constant,
  # because a constant defined inside a describe block leaks to the top level
  # and `Address` is a name something else will eventually want.
  let(:address_class) { Struct.new(:country, :state, :postal_code, keyword_init: true) }

  def address(**attrs) = address_class.new(**attrs)

  def record(intent: "pi_test_1", address: nil, amount_cents: 5_00)
    described_class.record!(
      payment_intent_id: intent,
      event:,
      amount_cents:,
      address:,
      occurred_at: Time.current
    )
  end

  describe ".record!" do
    it "stores the jurisdiction a Checkout Session supplied" do
      row = record(address: address(country: "US", state: "CA", postal_code: "94110"))

      expect(row.country).to eq("US")
      expect(row.state).to eq("CA")
      expect(row.postal_code).to eq("94110")
    end

    it "records a sale whose jurisdiction Stripe never supplied, rather than dropping it" do
      row = record(address: nil)

      expect(row).to be_persisted
      expect(row.country).to be_nil
      expect(described_class.unknown_jurisdiction).to include(row)
    end

    it "is idempotent — the same sale arriving twice writes one row" do
      buyer = address(country: "US", state: "TX", postal_code: "78701")

      expect { 2.times { record(address: buyer) } }
        .to change(described_class, :count).by(1)
    end

    # The bug this whole design exists to prevent.
    it "fills in a jurisdiction the first event could not supply" do
      record(address: nil) # payment_intent.succeeded arrives first
      row = record(address: address(country: "GB", state: nil, postal_code: "SW1A 1AA"))

      expect(row.country).to eq("GB")
      expect(row.postal_code).to eq("SW1A 1AA")
    end

    # The first address Stripe gave is the one the buyer actually entered.
    it "never overwrites a jurisdiction it already has" do
      record(address: address(country: "US", state: "NY", postal_code: "10001"))
      row = record(address: address(country: "CA", state: "ON", postal_code: "M5V"))

      expect(row.country).to eq("US")
      expect(row.state).to eq("NY")
    end

    it "declines without a venture to attribute the sale to" do
      expect(
        described_class.record!(
          payment_intent_id: "pi_orphan", event: nil,
          amount_cents: 100, address: nil, occurred_at: Time.current
        )
      ).to be_nil
    end

    # Prime Directive: the ledger is what the founder sees. A compliance record
    # that cannot be written must never take a sale down with it.
    it "swallows and reports an unexpected failure instead of raising" do
      allow(described_class).to receive(:find_by).and_raise(ActiveRecord::StatementInvalid, "boom")
      expect(Rails.error).to receive(:report)

      expect { record(address: nil) }.not_to raise_error
    end
  end

  describe ".in_year" do
    it "buckets by when the sale happened, not when the row was written" do
      travel_to(Time.zone.local(2027, 3, 1)) do
        described_class.record!(
          payment_intent_id: "pi_backfilled", event:, amount_cents: 100,
          address: nil, occurred_at: Time.zone.local(2026, 12, 31, 23, 0)
        )
      end

      expect(described_class.in_year(2026).count).to eq(1)
      expect(described_class.in_year(2027).count).to eq(0)
    end
  end

end
