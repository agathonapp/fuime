# frozen_string_literal: true

require "rails_helper"

# Fuime: the four dials, and the arithmetic the class header claims for them.
#
# The worked example in Fuime::PayoutPolicy's header — "$130 reserve at steady
# state on a $100/week operator, about 1.3 weeks of earnings" — is the sentence a
# founder will read when deciding whether the defaults are right. Pinning it here
# means the sentence and the code cannot drift apart silently.
RSpec.describe Fuime::PayoutPolicy do
  describe ".current" do
    it "uses the documented defaults with no configuration" do
      policy = described_class.current

      expect(policy.hold_days).to eq(7)
      expect(policy.reserve_basis_points).to eq(1_000)
      expect(policy.reserve_window_days).to eq(90)
      expect(policy.maximum_cents).to eq(2_500_00)
      expect(policy.minimum_cents).to eq(10_00)
    end

    it "reads each dial from its own env var" do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("FUIME_PAYOUT_HOLD_DAYS").and_return("14")
      allow(ENV).to receive(:[]).with("FUIME_PAYOUT_RESERVE_BASIS_POINTS").and_return("500")

      policy = described_class.current

      expect(policy.hold_days).to eq(14)
      expect(policy.reserve_basis_points).to eq(500)
      # Untouched dials keep their defaults rather than collapsing to zero.
      expect(policy.reserve_window_days).to eq(90)
    end

    # A negative reserve pays out MORE than is owed and a negative hold makes
    # unsettled money eligible, so both invert the control they exist to be. A
    # typo in an env var must not be able to do that, and must not take the app
    # down either — it is clamped, and the clamp is visible on the batch row.
    it "clamps a negative dial to zero rather than inverting the control" do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("FUIME_PAYOUT_RESERVE_BASIS_POINTS").and_return("-1000")

      expect(described_class.current.reserve_basis_points).to eq(0)
    end

    it "ignores a blank env var" do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("FUIME_PAYOUT_HOLD_DAYS").and_return("")

      expect(described_class.current.hold_days).to eq(7)
    end
  end

  describe ".from" do
    # The whole reason this class exists rather than a bag of constants: a batch
    # generated in August must keep answering with August's rules, so every
    # consumer downstream of generation reads the frozen copy.
    it "reads the policy off a batch, not off the environment" do
      batch = build(:fuime_payout_batch, hold_days: 30, reserve_basis_points: 250,
                                         reserve_window_days: 60, maximum_cents: 1_000_00,
                                         minimum_cents: 5_00)

      policy = described_class.from(batch)

      expect(policy.hold_days).to eq(30)
      expect(policy.reserve_basis_points).to eq(250)
      expect(policy.reserve_window_days).to eq(60)
      expect(policy.maximum_cents).to eq(1_000_00)
      expect(policy.minimum_cents).to eq(5_00)
    end
  end

  describe "#eligibility_cutoff" do
    it "is the hold period before the end of the run" do
      policy = described_class.new(hold_days: 7, reserve_basis_points: 0,
                                   reserve_window_days: 90, maximum_cents: 0, minimum_cents: 0)

      expect(policy.eligibility_cutoff(Date.new(2026, 8, 15))).to eq(Date.new(2026, 8, 8))
    end
  end

  describe "#reserve_target_cents" do
    let(:policy) do
      described_class.new(hold_days: 7, reserve_basis_points: 1_000,
                          reserve_window_days: 90, maximum_cents: 0, minimum_cents: 0)
    end

    it "is the configured percentage of trailing gross" do
      expect(policy.reserve_target_cents(1_000_00)).to eq(100_00)
    end

    # Rounding down, always. A cent either way is immaterial to the exposure, and
    # "Fuime rounded its own reserve up" is not a sentence worth defending.
    it "rounds in the operator's favour" do
      expect(policy.reserve_target_cents(1_05)).to eq(10)
    end

    it "holds nothing against no sales, and nothing against negative sales" do
      expect(policy.reserve_target_cents(0)).to eq(0)
      expect(policy.reserve_target_cents(-500_00)).to eq(0)
    end

    # The worked example from the class header. A steady $100/week operator
    # accumulates 13 weeks of sales inside a 90-day window, and 10% of that is the
    # standing reserve — about 1.3 weeks of earnings, held for as long as they
    # trade.
    it "matches the documented steady state for a $100/week operator" do
      thirteen_weeks_of_sales = 13 * 100_00

      expect(policy.reserve_target_cents(thirteen_weeks_of_sales)).to eq(130_00)
    end
  end

  describe "#attributes_for_batch" do
    it "hands back exactly the columns a batch freezes" do
      policy = described_class.current

      expect(policy.attributes_for_batch.keys).to match_array(
        %i[hold_days reserve_basis_points reserve_window_days maximum_cents minimum_cents]
      )
      expect(build(:fuime_payout_batch, **policy.attributes_for_batch)).to be_valid
    end
  end
end
