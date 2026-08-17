# frozen_string_literal: true

require "rails_helper"

# Fuime: what one operator gets paid in one run.
#
# The property worth protecting above every individual example: **no ordering of
# these rules pays an operator more than Fuime owes them.** Each of the four terms
# can only reduce the figure, and the last example in this file asserts that
# directly rather than trusting the four to compose.
RSpec.describe Fuime::PayableAssessment do
  let(:period_end) { Date.new(2026, 8, 15) }
  let(:event) { create(:event) }

  let(:policy) do
    Fuime::PayoutPolicy.new(
      hold_days: 7,
      reserve_basis_points: 0,
      reserve_window_days: 90,
      maximum_cents: 250_00,
      minimum_cents: 10_00
    )
  end

  subject(:assessment) { described_class.new(event:, policy:, period_end:).call }

  # A settled ledger line carrying its Fuime::VentureLedger key in the memo, the
  # way ConnectSettlementSweep writes them. Built directly rather than driven
  # through the sweep so these examples stay about the arithmetic.
  def post_line(key, amount_cents, date: period_end - 30, memo: "Line")
    create(:canonical_transaction, amount_cents:, memo: "#{memo} [#{key}]", event:, date:)
  end

  def sale(intent:, gross:, date: period_end - 30)
    post_line("fuime_#{intent}", gross, date:, memo: "Payment from a customer")
  end

  describe "the ordinary case" do
    before { sale(intent: "pi_1", gross: 100_00) }

    it "pays what is owed once it has cleared the hold" do
      expect(assessment).to be_payable
      expect(assessment.amount_cents).to eq(100_00)
    end

    it "reports every figure that produced the number" do
      expect(assessment.payable_cents).to eq(100_00)
      expect(assessment.aged_cents).to eq(100_00)
      expect(assessment.committed_cents).to eq(0)
      expect(assessment.eligible_cents).to eq(100_00)
    end
  end

  describe "the hold period" do
    it "does not pay out a sale that has not aged yet" do
      sale(intent: "pi_1", gross: 100_00, date: period_end - 2)

      expect(assessment).not_to be_payable
      expect(assessment.skip_reason).to include("7-day hold")
    end

    it "pays a sale on the day it clears" do
      sale(intent: "pi_1", gross: 100_00, date: period_end - 7)

      expect(assessment.amount_cents).to eq(100_00)
    end

    # The bug the `min` exists to prevent, and the single most important example
    # here. Summing aged lines ALONE would report $500 eligible and pay out money
    # the operator no longer has, because the refund is newer than the cutoff.
    it "lets a recent refund bite even though it has not aged" do
      sale(intent: "pi_1", gross: 500_00, date: period_end - 30)
      post_line("fuime_rev_pi_1_refund_re_1_40000", -400_00, date: period_end - 1, memo: "Refunded")

      expect(assessment.aged_cents).to eq(500_00)
      expect(assessment.payable_cents).to eq(100_00)
      expect(assessment.amount_cents).to eq(100_00)
    end
  end

  describe "the rolling reserve" do
    let(:policy) do
      Fuime::PayoutPolicy.new(hold_days: 7, reserve_basis_points: 1_000,
                              reserve_window_days: 90, maximum_cents: 250_00, minimum_cents: 10_00)
    end

    it "withholds the configured percentage of trailing gross" do
      sale(intent: "pi_1", gross: 100_00)

      expect(assessment.reserve_target_cents).to eq(10_00)
      expect(assessment.amount_cents).to eq(90_00)
    end

    # The behaviour a per-line withholding scheme has to be carefully built to
    # imitate and this one gets for free: sales outside the window stop counting
    # toward the target, so the reserve unwinds on its own.
    it "releases as sales age out of the window, with nothing to run" do
      sale(intent: "pi_old", gross: 100_00, date: period_end - 120)

      expect(assessment.trailing_gross_cents).to eq(0)
      expect(assessment.reserve_target_cents).to eq(0)
      expect(assessment.amount_cents).to eq(100_00)
    end

    # The reason has to name the term that actually caused the skip. $15 payable
    # against a $10 reserve leaves $5, under the $10 floor — and but for the
    # reserve the $15 would have been paid, so the reserve is the answer.
    it "explains itself when the reserve is the reason nothing is paid" do
      sale(intent: "pi_1", gross: 100_00)
      post_line("fuime_rev_pi_1_refund_re_1_8500", -85_00, date: period_end - 20, memo: "Refunded")

      expect(assessment).not_to be_payable
      expect(assessment.skip_reason).to include("Held as reserve")
    end

    # …and must NOT name it when the operator would have been skipped anyway.
    # Blaming the reserve for a $2 payable would send somebody looking for money
    # that was never there.
    it "does not blame the reserve for an operator who was under the floor regardless" do
      sale(intent: "pi_1", gross: 100_00)
      post_line("fuime_rev_pi_1_refund_re_1_9800", -98_00, date: period_end - 20, memo: "Refunded")

      expect(assessment.skip_reason).to include("minimum")
    end
  end

  describe "the per-operator cap" do
    it "pays the cap and rolls the rest forward rather than refusing" do
      sale(intent: "pi_1", gross: 400_00)

      expect(assessment).to be_payable
      expect(assessment.amount_cents).to eq(250_00)
      expect(assessment.eligible_cents).to eq(400_00)
      expect(assessment).to be_capped
      expect(assessment.withheld_cents).to eq(150_00)
    end
  end

  describe "the minimum" do
    it "rolls a small payable into the next run" do
      sale(intent: "pi_1", gross: 5_00)

      expect(assessment).not_to be_payable
      expect(assessment.skip_reason).to include("minimum")
    end

    it "says plainly when nothing is owed at all" do
      expect(assessment).not_to be_payable
      expect(assessment.skip_reason).to eq("Nothing owed.")
    end
  end

  # Tagged because a `fuime_vendor_payment` line only validates under the model
  # that gives Fuime money of its own to pay out.
  describe "money already promised", :merchant_of_record do
    # Without this deduction two open runs would each pay the same money. The
    # unique index stops a venture appearing twice in ONE run; this is what stops
    # it being paid twice across two.
    it "deducts a line already sitting in an earlier run" do
      # A destination, because under MoR an operator without one is skipped
      # before any arithmetic runs — see #structural_skip_reason.
      create(:fuime_payout_method, :verified, event:)
      sale(intent: "pi_1", gross: 100_00)
      batch = create(:fuime_payout_batch)
      create(:payout_request, event:, payout_batch: batch, requested_by: nil,
                              amount_cents: 60_00, destination: PayoutRequest::FUIME_VENDOR_PAYMENT)

      expect(assessment.committed_cents).to eq(60_00)
      expect(assessment.amount_cents).to eq(40_00)
    end

    # A paid line has already had its ledger debit posted, so it is inside
    # `payable_cents` and counting it again would deduct it twice.
    it "does not double-count a run that has already paid" do
      create(:fuime_payout_method, :verified, event:)
      sale(intent: "pi_1", gross: 100_00)
      batch = create(:fuime_payout_batch, :paid)
      create(:payout_request, :paid, event:, payout_batch: batch, requested_by: nil,
                                     amount_cents: 60_00, destination: PayoutRequest::FUIME_VENDOR_PAYMENT)

      expect(assessment.committed_cents).to eq(0)
    end
  end

  describe "operators Fuime does not pay" do
    it "skips a venture inside a school programme, naming the real payer" do
      allow(event).to receive(:shares_payment_account?).and_return(true)

      expect(assessment).not_to be_payable
      expect(assessment.skip_reason).to include("school")
    end

    it "skips a venture nobody has approved to trade" do
      event.update!(operator_vetting_status: :unvetted)

      expect(assessment).not_to be_payable
      expect(assessment.skip_reason).to include("Not approved to trade")
    end

    it "skips a frozen venture" do
      event.update!(financially_frozen: true)

      expect(assessment).not_to be_payable
      expect(assessment.skip_reason).to include("frozen")
    end
  end

  # The composition property. Individually correct rules can still compose into a
  # payout larger than the debt, so this asserts the invariant directly across a
  # spread of ledgers rather than trusting the four examples above.
  describe "the invariant" do
    let(:policy) do
      Fuime::PayoutPolicy.new(hold_days: 7, reserve_basis_points: 1_000,
                              reserve_window_days: 90, maximum_cents: 250_00, minimum_cents: 10_00)
    end

    [
      [100_00, 0],
      [100_00, -30_00],
      [500_00, -450_00],
      [20_00, -25_00],
      [1_000_00, -10_00]
    ].each do |gross, adjustment|
      it "never pays more than is owed (gross #{gross}, adjustment #{adjustment})" do
        sale(intent: "pi_1", gross:)
        post_line("fuime_rev_pi_1_refund_re_1_#{adjustment.abs}", adjustment, date: period_end - 20) unless adjustment.zero?

        result = described_class.new(event:, policy:, period_end:).call

        expect(result.amount_cents).to be <= [result.payable_cents, 0].max
        expect(result.amount_cents).to be >= 0
      end
    end
  end
end
