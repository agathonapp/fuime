# frozen_string_literal: true

require "rails_helper"

# Fuime: money out of a student venture inside a school programme.
#
# Two things are being proven, and the first is a safety property rather than a
# feature. One Stripe account holds every student's money, so Stripe's available
# balance is the WHOLE programme's — and every existing balance check compared a
# student's request against it. Left alone, one student could have withdrawn
# another student's revenue and the ledger would only have shown it afterwards.
#
# The second is the cash-out path itself: the student asks, the school approves, the
# school pays them, and the ledger follows the money rather than the authorisation.
RSpec.describe Fuime::PayoutService, "inside a school programme" do
  let(:school_tree) { build_school_tree }
  let(:school)  { school_tree[0] }
  let(:venture) { school_tree[2] }

  let!(:school_account) { create(:stripe_connected_account, :ready, event: school) }
  let!(:guide)   { create_school_manager(school) }
  let!(:student) { create_student(venture) }

  let(:service) { described_class.new(event: venture) }

  def stub_balance(available_cents)
    allow(Stripe::Balance).to receive(:retrieve).and_return(
      Stripe::Balance.construct_from(
        available: [{ currency: "usd", amount: available_cents }]
      )
    )
  end

  # Give the venture a real settled ledger balance, the way a sale would. Settled
  # rather than pending on purpose: `balance_v2_cents` is what the cap reads, and
  # pending incoming money is deliberately not part of it.
  def credit_venture!(cents, event: venture)
    ct = create(:canonical_transaction, amount_cents: cents, date: Date.current, memo: "Sale")
    create(:canonical_event_mapping, canonical_transaction: ct, event:)
    ct
  end

  describe "#available_balance_cents on a shared account" do
    it "caps at the venture's own ledger balance, not the programme's" do
      # The school's account holds $9,000 across every student. This venture earned
      # $40. Before the cap, the student was told $9,000 was available to them and
      # the amount check in #request! agreed.
      stub_balance(900_000)
      credit_venture!(4_000)

      expect(service.available_balance_cents).to eq(4_000)
    end

    it "still caps at Stripe's number when Stripe has less than the ledger says" do
      # Money from a recent sale is on the ledger but not yet released by Stripe.
      stub_balance(1_000)
      credit_venture!(4_000)

      expect(service.available_balance_cents).to eq(1_000)
    end

    it "reports zero rather than a negative for a venture in the red" do
      stub_balance(900_000)
      credit_venture!(-2_000)

      expect(service.available_balance_cents).to eq(0)
    end

    # One student's earnings are invisible to another's.
    it "does not let a sibling venture's balance count toward this one" do
      sibling = create(:event, parent: venture.parent)
      stub_balance(900_000)
      credit_venture!(50_000, event: sibling)
      credit_venture!(1_500)

      expect(service.available_balance_cents).to eq(1_500)
    end

    # The family model must not acquire a cap it does not need: there the account
    # holds exactly one venture's money and Stripe's number IS the answer.
    it "leaves an owned account reading Stripe's balance directly" do
      ordinary = create(:event)
      create(:stripe_connected_account, :ready, event: ordinary)
      stub_balance(7_777)

      expect(described_class.new(event: ordinary).available_balance_cents).to eq(7_777)
    end
  end

  describe "#request!" do
    before { stub_balance(900_000) }

    it "creates a personal transfer, because that is the only destination available" do
      credit_venture!(10_000)

      request = service.request!(amount_cents: 4_000, requested_by: student,
                                 destination_note: "my own bank account")

      expect(request).to be_personal_transfer
      expect(request.destination_note).to eq("my own bank account")
    end

    # The cap doing its job at the point a student would have exploited it.
    it "refuses more than the venture itself has earned" do
      credit_venture!(4_000)

      expect { service.request!(amount_cents: 50_000, requested_by: student) }
        .to raise_error(described_class::InsufficientFunds, /\$40\.00 available/)
    end

    it "refuses when the school has not finished setting payments up" do
      school_account.destroy!

      expect { described_class.new(event: venture.reload).request!(amount_cents: 1_000, requested_by: student) }
        .to raise_error(described_class::NotSetUp)
    end
  end

  describe "#approve! on a personal transfer" do
    before { stub_balance(900_000) }

    let(:request) do
      credit_venture!(10_000)
      service.request!(amount_cents: 4_000, requested_by: student, destination_note: "my bank")
    end

    it "never calls Stripe, because Stripe cannot make this payment" do
      # Stripe pays out only to external accounts belonging to the account holder,
      # and a student's personal account is not the school's. Attempting it would be
      # both a Stripe violation and Fuime directing a third party's funds.
      expect(Stripe::Payout).not_to receive(:create)

      service.approve!(request:, approver: guide)
    end

    it "records the approval and waits for the school to pay" do
      service.approve!(request:, approver: guide)

      expect(request.reload).to be_approved
      expect(request.approved_by).to eq(guide)
      expect(request.awaiting_settlement?).to be true
      expect(request.stripe_payout_id).to be_nil
    end

    # The load-bearing decision on this path. Debiting at approval would show the
    # student a reduced balance for money still in the school's account — and would
    # let the venture spend against a balance already queued to be paid out in cash.
    it "posts no ledger line yet, because the money has not moved" do
      expect { service.approve!(request:, approver: guide) }
        .not_to change { CanonicalPendingEventMapping.where(event_id: venture.id).count }
    end

    it "refuses an approver who is not a manager of the school" do
      expect { service.approve!(request:, approver: create(:user, birthday: 40.years.ago.to_date)) }
        .to raise_error(ActiveRecord::RecordInvalid)
    end
  end

  describe "#settle!" do
    before { stub_balance(900_000) }

    let(:request) do
      credit_venture!(10_000)
      req = service.request!(amount_cents: 4_000, requested_by: student, destination_note: "my bank")
      service.approve!(request: req, approver: guide)
      req
    end

    it "debits the venture's ledger for exactly the amount paid" do
      service.settle!(request:, settled_by: guide)

      line = CanonicalPendingEventMapping
             .where(event_id: venture.id)
             .map(&:canonical_pending_transaction)
             .find { |cpt| cpt.amount_cents == -4_000 }

      expect(line).to be_present
      expect(line.memo).to match(/Paid out to .* by the school/)
    end

    it "records who confirmed it, separately from who approved it" do
      business_office = create_school_manager(school)

      service.settle!(request:, settled_by: business_office)

      expect(request.reload).to be_paid
      expect(request.approved_by).to eq(guide)
      expect(request.settled_by).to eq(business_office)
      expect(request.settled_at).to be_present
    end

    # A double-click must not debit twice. The ledger key is the PayoutRequest id
    # precisely because there is no Stripe object to key on here.
    it "is idempotent" do
      service.settle!(request:, settled_by: guide)

      expect { service.settle!(request: request.reload, settled_by: guide) }
        .to raise_error(described_class::Error)

      lines = CanonicalPendingEventMapping.where(event_id: venture.id)
                                          .map(&:canonical_pending_transaction)
      expect(lines.count { |cpt| cpt.amount_cents == -4_000 }).to eq(1)
    end

    it "refuses a request nobody has approved yet" do
      credit_venture!(10_000)
      unapproved = service.request!(amount_cents: 1_000, requested_by: student)

      expect { service.settle!(request: unapproved, settled_by: guide) }
        .to raise_error(described_class::Error, /isn't waiting to be marked as paid/)
    end

    # Reinvesting is the default, and it has to actually work: money left alone
    # stays on the venture's balance.
    it "leaves the rest of the balance on the venture" do
      service.settle!(request:, settled_by: guide)

      expect(venture.reload.balance_v2_cents).to eq(6_000)
    end
  end
end
