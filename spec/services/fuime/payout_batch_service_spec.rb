# frozen_string_literal: true

require "rails_helper"

# Fuime: the weekly run — generation, the approval gate, and the one place a batch
# line touches an operator's ledger.
#
# Tagged `:merchant_of_record` throughout because a run is only coherent under that
# model: it presupposes the customer's money landed in Fuime's own account. With
# the flag off, generation raises, and that is asserted here too.
RSpec.describe Fuime::PayoutBatchService, :merchant_of_record do
  let(:period_end) { Date.new(2026, 8, 15) }
  let(:admin) { create(:user, :make_admin) }
  subject(:service) { described_class.new }

  # A sale, and the destination it will be paid to.
  #
  # Under merchant-of-record Fuime owes this operator and needs somewhere to send
  # it, so a venture with no verified payout method is skipped by design — see
  # Fuime::PayableAssessment. Every example here is about the arithmetic rather
  # than that gate, so the destination comes with the sale.
  def sale(event:, gross:, intent: "pi_#{SecureRandom.hex(4)}", date: period_end - 30)
    payout_destination_for(event)
    create(:canonical_transaction, amount_cents: gross, event:, date:,
                                   memo: "Payment from a customer [fuime_#{intent}]")
  end

  def payout_destination_for(event)
    return if event.fuime_payout_methods.live.any?

    create(:fuime_payout_method, :verified, event:)
  end

  describe "#generate!" do
    it "creates a draft run with one line per payable operator" do
      paid_operator = create(:event)
      sale(event: paid_operator, gross: 100_00)
      create(:event) # owed nothing

      batch = service.generate!(period_end:)

      expect(batch).to be_draft
      expect(batch.operator_count).to eq(1)
      expect(batch.payout_requests.first.event).to eq(paid_operator)
      expect(batch.total_cents).to eq(90_00) # less the 10% reserve
    end

    it "freezes the policy onto the row rather than leaving it to read the env" do
      batch = service.generate!(period_end:)

      expect(batch.hold_days).to eq(Fuime::PayoutPolicy::DEFAULT_HOLD_DAYS)
      expect(batch.reserve_basis_points).to eq(Fuime::PayoutPolicy::DEFAULT_RESERVE_BASIS_POINTS)
      expect(batch.minimum_cents).to eq(Fuime::PayoutPolicy::DEFAULT_MINIMUM_CENTS)
    end

    it "defaults the payout date to the next payout weekday" do
      batch = service.generate!(period_end:)

      expect(batch.payout_on.strftime("%A")).to eq("Friday")
    end

    # A weekly job, a retry and an admin clicking Generate all produce a second
    # call for the same period. A second batch would pay an operator twice for one
    # week.
    it "is idempotent on the period" do
      first = service.generate!(period_end:)
      second = service.generate!(period_end:)

      expect(second.id).to eq(first.id)
      expect(Fuime::PayoutBatch.count).to eq(1)
    end

    # The recovery path: a run generated against the wrong policy is cancelled and
    # regenerated for the same week.
    it "allows a fresh run for a period whose earlier run was cancelled" do
      first = service.generate!(period_end:)
      service.cancel!(batch: first, cancelled_by: admin)

      second = service.generate!(period_end:)

      expect(second.id).not_to eq(first.id)
      expect(second).to be_draft
    end

    it "creates lines nobody requested, on the Fuime-pays-its-vendor destination" do
      sale(event: create(:event), gross: 100_00)

      line = service.generate!(period_end:).payout_requests.first

      expect(line.requested_by).to be_nil
      expect(line).to be_scheduled
      expect(line).to be_fuime_vendor_payment
      expect(line).to be_pending
    end

    it "records the reserve and the pre-reserve figure on the line" do
      sale(event: create(:event), gross: 100_00)

      line = service.generate!(period_end:).payout_requests.first

      expect(line.reserve_held_cents).to eq(10_00)
      expect(line.eligible_cents).to eq(90_00)
    end

    # "38 ventures, 6 lines" is either correct or a serious bug, and a reviewer
    # cannot tell which without the reasons.
    it "writes why each excluded venture was excluded onto the run" do
      create(:event, :unvetted)
      create(:event)

      batch = service.generate!(period_end:)

      expect(batch.notes).to include("Not approved to trade")
      # The second venture now skips for the destination gate, which fires
      # ahead of "nothing owed" — see Fuime::PayableAssessment.
      expect(batch.notes).to include("No payout destination")
    end

    it "refuses to generate when Fuime is not the seller of record" do
      # Overriding the tag for this one example: with the flag off there is no
      # money of Fuime's own to pay out, so a run is not a smaller thing — it is a
      # different, unlawful thing (L1).
      allow(Fuime::Features).to receive(:merchant_of_record?).and_return(false)

      expect { service.generate!(period_end:) }.to raise_error(Fuime::Features::Disabled)
    end
  end

  describe "#approve!" do
    let(:batch) do
      sale(event: create(:event), gross: 100_00)
      service.generate!(period_end:)
    end

    it "releases every line and records who released it" do
      service.approve!(batch:, approver: admin)

      expect(batch.reload).to be_approved
      expect(batch.approved_by).to eq(admin)
      expect(batch.payout_requests.map(&:aasm_state)).to all(eq("approved"))
      expect(batch.payout_requests.first.approved_by).to eq(admin)
    end

    # Approval is a decision, not a payment. This is the distinction the batch
    # page's copy rests on, so it is asserted rather than described.
    it "posts no ledger line — approving is not paying" do
      expect { service.approve!(batch:, approver: admin) }
        .not_to change(CanonicalPendingTransaction, :count)
    end

    it "refuses a non-admin" do
      expect { service.approve!(batch:, approver: create(:user)) }
        .to raise_error(described_class::NotPermitted)
    end

    it "refuses a run that has already been decided" do
      service.approve!(batch:, approver: admin)

      expect { service.approve!(batch:, approver: admin) }
        .to raise_error(described_class::WrongState)
    end
  end

  describe "#mark_paid!" do
    let(:event) { create(:event) }
    let(:batch) do
      sale(event:, gross: 100_00)
      b = service.generate!(period_end:)
      service.approve!(batch: b, approver: admin)
      b
    end

    it "debits each operator's ledger for exactly what was paid" do
      expect { service.mark_paid!(batch:, paid_by: admin) }
        .to change { Fuime::PayablesLedger.new(event:).paid_out_cents }.by(90_00)
    end

    it "keeps the payables breakdown reconciling after a run" do
      service.mark_paid!(batch:, paid_by: admin)

      payables = Fuime::PayablesLedger.new(event: event.reload)
      reconciled = payables.gross_sales_cents -
                   payables.fuime_fee_cents -
                   payables.processing_fee_cents -
                   payables.refunds_cents -
                   payables.card_spend_cents -
                   payables.paid_out_cents -
                   payables.committed_cents +
                   payables.other_adjustments_cents

      expect(reconciled).to eq(payables.net_payable_cents)
    end

    it "marks every line paid and records who asserted it" do
      service.mark_paid!(batch:, paid_by: admin)

      expect(batch.reload).to be_paid
      expect(batch.paid_by).to eq(admin)
      expect(batch.payout_requests.map(&:aasm_state)).to all(eq("paid"))
    end

    # The idempotency Fuime::VentureLedger provides, exercised the way a partial
    # failure and retry would exercise it: the state change is rolled back, the
    # ledger keys are not, and re-running must not debit twice.
    it "does not double-debit when the ledger has already been posted" do
      service.mark_paid!(batch:, paid_by: admin)
      before = Fuime::PayablesLedger.new(event: event.reload).paid_out_cents

      batch.payout_requests.each { |r| r.update_columns(aasm_state: "approved") }
      batch.update_columns(aasm_state: "approved")
      service.mark_paid!(batch: batch.reload, paid_by: admin)

      expect(Fuime::PayablesLedger.new(event: event.reload).paid_out_cents).to eq(before)
    end

    it "refuses a run that was never approved" do
      draft = service.generate!(period_end: period_end - 7)

      expect { service.mark_paid!(batch: draft, paid_by: admin) }
        .to raise_error(described_class::WrongState)
    end

    it "refuses a non-admin" do
      expect { service.mark_paid!(batch:, paid_by: create(:user)) }
        .to raise_error(described_class::NotPermitted)
    end
  end

  describe "#cancel!" do
    let(:event) { create(:event) }
    let(:batch) do
      sale(event:, gross: 100_00)
      service.generate!(period_end:)
    end

    # Declined rather than deleted: a line that existed and was pulled is a fact
    # somebody may need to explain, and a deleted row explains nothing.
    it "declines every line and keeps them" do
      service.cancel!(batch:, cancelled_by: admin, reason: "Wrong period")

      expect(batch.reload).to be_cancelled
      expect(batch.payout_requests.map(&:aasm_state)).to all(eq("rejected"))
      expect(batch.payout_requests.first.rejection_reason).to eq("Wrong period")
    end

    it "leaves the money payable, so it appears in a later run" do
      service.cancel!(batch:, cancelled_by: admin)

      expect(Fuime::PayablesLedger.new(event: event.reload).net_payable_cents).to eq(100_00)
    end

    it "can stop a run that was already approved" do
      service.approve!(batch:, approver: admin)

      expect { service.cancel!(batch:, cancelled_by: admin) }.not_to raise_error
      expect(batch.reload).to be_cancelled
    end

    it "refuses to cancel a run that has already paid" do
      service.approve!(batch:, approver: admin)
      service.mark_paid!(batch:, paid_by: admin)

      expect { service.cancel!(batch:, cancelled_by: admin) }
        .to raise_error(described_class::WrongState)
    end
  end
end
