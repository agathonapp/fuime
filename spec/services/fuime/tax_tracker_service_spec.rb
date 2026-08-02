# frozen_string_literal: true

require "rails_helper"

# Fuime: these figures are shown to a teenager and their parent as tax
# guidance, so the arithmetic is verified against hand-computed values.
# See docs/fuime/PRODUCTION_READINESS.md §1.6.
RSpec.describe Fuime::TaxTrackerService do
  let(:event) { create(:event) }

  # Post a canonical transaction on the event's ledger for the current year.
  def post(amount_cents, memo: "Customer payment", date: Date.current)
    ct = create(:canonical_transaction, amount_cents:, memo:, date:)
    create(:canonical_event_mapping, canonical_transaction: ct, event:)
    ct
  end

  subject(:tracker) { described_class.new(event:) }

  describe "income and expenses" do
    it "sums positive lines as income and negative lines as expenses" do
      post(50_000)
      post(20_000)
      post(-15_000, memo: "Supplies")

      expect(tracker.income_cents).to eq(70_000)
      expect(tracker.expenses_cents).to eq(15_000)
      expect(tracker.net_income_cents).to eq(55_000)
    end

    it "excludes transfers and other non-revenue movements from income" do
      post(50_000, memo: "Customer payment")
      post(30_000, memo: "Transfer from savings")
      post(10_000, memo: "Owner deposit")

      expect(tracker.income_cents).to eq(50_000)
    end

    # A refund posts a reversing line; counting the original as income while
    # ignoring the reversal permanently overstates a teen's taxable income.
    it "excludes refund and dispute reversals" do
      post(50_000, memo: "Customer payment")
      post(-50_000, memo: "Refunded payment")

      expect(tracker.income_cents).to eq(50_000)
      expect(tracker.expenses_cents).to eq(0)
    end

    it "ignores transactions from other years" do
      post(50_000, date: Date.current)
      post(99_000, date: Date.current.prev_year)

      expect(tracker.income_cents).to eq(50_000)
    end
  end

  describe "the $400 self-employment threshold" do
    # IRS: SE tax applies once NET EARNINGS (net profit x 92.35%) reach $400,
    # so the profit at which it bites is 400 / 0.9235 ≈ $433.14 — not $400.
    it "computes net earnings as 92.35% of net profit" do
      post(1_000_00)

      expect(tracker.net_income_cents).to eq(100_000)
      expect(tracker.net_earnings_cents).to eq(92_350)
    end

    it "is NOT over the threshold at exactly $400 of net profit" do
      post(400_00)

      expect(tracker.net_income_cents).to eq(40_000)
      expect(tracker.net_earnings_cents).to eq(36_940)
      expect(tracker).not_to be_over_threshold
    end

    it "is over the threshold once net earnings reach $400" do
      post(434_00)

      expect(tracker.net_earnings_cents).to be >= 400_00
      expect(tracker).to be_over_threshold
    end

    it "reports the remaining profit needed to reach the threshold" do
      post(400_00)

      # ~$433.14 - $400.00
      expect(tracker.cents_until_threshold).to eq(
        described_class::NET_PROFIT_FILING_THRESHOLD_CENTS - 40_000
      )
    end

    it "treats a net loss as zero net earnings and not over the threshold" do
      post(10_000)
      post(-30_000, memo: "Supplies")

      expect(tracker.net_income_cents).to be_negative
      expect(tracker.net_earnings_cents).to eq(0)
      expect(tracker).not_to be_over_threshold
      expect(tracker.threshold_progress).to eq(0.0)
    end
  end

  describe "presentation" do
    it "hedges rather than stating a tax obligation as fact" do
      post(1_000_00)

      expect(tracker.status_message).to match(/likely/i)
      expect(tracker.disclaimer).to match(/not tax advice/i)
    end

    it "warns about quarterly estimates only when over the threshold" do
      post(1_000_00)
      expect(tracker.quarterly_estimates_warning).to match(/quarterly/i)

      expect(described_class.new(event: create(:event)).quarterly_estimates_warning).to be_nil
    end

    it "caps the progress bar at 100%" do
      post(10_000_00)

      expect(tracker.threshold_percentage).to eq(100)
    end
  end

  describe "#year_end_packet" do
    it "labels itself an estimate and carries the disclaimer" do
      post(1_000_00)
      packet = tracker.year_end_packet

      expect(packet[:estimate_only]).to be true
      expect(packet[:disclaimer]).to be_present
      expect(packet[:net_income]).to eq(1_000.0)
      expect(packet[:net_earnings]).to eq(923.5)
    end
  end
end
