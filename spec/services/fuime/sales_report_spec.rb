# frozen_string_literal: true

require "rails_helper"

# Fuime: the questions the ledger cannot answer.
#
# HCB's ledger aggregates by memo prefix, so before Fuime::Sale nothing in the
# app could say which product a founder sells most of, or what revenue did last
# month. These pin the answers AND the honesty of the empty states — a founder
# sees this dashboard before their first sale, and a crash or a misleading zero
# on that screen is worse than no dashboard.
RSpec.describe Fuime::SalesReport do
  let(:event) { create(:event) }
  let(:other_event) { create(:event) }

  def sell(cents, at: Time.current, offer: nil, event: self.event, country: "US", state: "CA")
    Fuime::Sale.create!(
      stripe_payment_intent_id: "pi_#{SecureRandom.hex(6)}",
      event:, amount_cents: cents, occurred_at: at,
      fuime_offer_id: offer&.id, country:, state:
    )
  end

  describe "before the first sale" do
    it "answers with zeroes rather than raising" do
      report = described_class.new(event:)

      expect(report.sale_count).to eq(0)
      expect(report.total_revenue_cents).to eq(0)
      expect(report.average_sale_cents).to eq(0)
      expect(report.revenue_series).to eq({})
      expect(report.top_offers).to eq([])
    end
  end

  describe "the headline numbers" do
    before do
      sell(2_500)
      sell(7_500)
      sell(1_000_00, event: other_event) # another founder's money
    end

    it "counts and sums only this venture's sales" do
      report = described_class.new(event:)

      expect(report.sale_count).to eq(2)
      expect(report.total_revenue_cents).to eq(10_000)
    end

    it "averages what an order is worth" do
      expect(described_class.new(event:).average_sale_cents).to eq(5_000)
    end
  end

  describe "revenue over time" do
    before do
      sell(10_00, at: Time.zone.local(2026, 1, 15))
      sell(20_00, at: Time.zone.local(2026, 1, 20))
      sell(50_00, at: Time.zone.local(2026, 3, 2))
    end

    it "buckets by month, oldest first" do
      series = described_class.new(event:).revenue_series(interval: "month")

      expect(series.values).to eq([30_00, 50_00])
      expect(series.keys.map(&:month)).to eq([1, 3])
    end

    # A quiet month is a fact about the business. Omitting it closes the gap and
    # implies sales that did not happen.
    it "shows a month with no sales as a zero, not as a missing bucket" do
      series = described_class.new(event:).revenue_series_filled(interval: "month")

      expect(series.values).to eq([30_00, 0, 50_00])
    end

    it "refuses an interval it cannot bucket" do
      expect { described_class.new(event:).revenue_series(interval: "fortnight") }
        .to raise_error(ArgumentError, /interval must be one of/)
    end

    it "honours a date window" do
      report = described_class.new(event:, since: Time.zone.local(2026, 2, 1))

      expect(report.total_revenue_cents).to eq(50_00)
    end
  end

  describe "what sells" do
    let(:mow) { create(:fuime_offer, event:, name: "Lawn mow", price_cents: 35_00) }
    let(:hedge) { create(:fuime_offer, event:, name: "Hedge trim", price_cents: 60_00) }

    before do
      3.times { sell(35_00, offer: mow) }
      sell(60_00, offer: hedge)
      sell(9_00) # free-amount path, no offer
    end

    it "ranks products by revenue, richest first" do
      top = described_class.new(event:).top_offers

      expect(top.map { |row| row[:offer_name] }).to eq(["Lawn mow", "Hedge trim"])
      expect(top.first).to include(revenue_cents: 105_00, sale_count: 3, offer: mow)
    end

    it "reports off-storefront sales separately rather than as an 'other' product" do
      expect(described_class.new(event:).unattributed_revenue_cents).to eq(9_00)
    end

    # A subscription outlives its listing, and a founder asking what they sold
    # last quarter should still be told.
    it "still names a sale whose offer was deleted since" do
      mow_id = mow.id
      Fuime::Sale.where(fuime_offer_id: mow_id).update_all(fuime_offer_id: -1)

      top = described_class.new(event:).top_offers
      expect(top.map { |row| row[:offer_name] }).to include("a product that has since been removed")
    end
  end

  describe "where the customers were" do
    before do
      sell(10_00, country: "US", state: "CA")
      sell(30_00, country: "US", state: "NY")
      sell(5_00, country: "GB", state: nil)
      sell(1_00, country: nil, state: nil)
    end

    it "groups by jurisdiction, largest first, ignoring sales it cannot place" do
      by_place = described_class.new(event:).revenue_by_jurisdiction

      expect(by_place).to eq("US-NY" => 30_00, "US-CA" => 10_00, "GB" => 5_00)
    end
  end

  # The number a founder cannot reconcile against their payout is worse than no
  # number, so the service carries its own disclaimers to whatever renders it.
  describe "honesty" do
    it "says out loud that refunds are not subtracted" do
      expect(described_class.new(event:).caveats.join(" ")).to match(/refund/i)
    end

    it "says this is not what you are owed" do
      expect(described_class.new(event:).caveats.join(" ")).to match(/owed|payout/i)
    end
  end
end
