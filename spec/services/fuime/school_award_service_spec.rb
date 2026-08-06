# frozen_string_literal: true

require "rails_helper"

# Fuime: the school moving its own money into a student's venture.
#
# The two properties that matter are conservation and funding, and they are the same
# property seen from two sides. An award must never create money (the school's
# subledger falls by exactly what the student's rises), and it must never be granted
# out of money the school does not have — because Fuime::PayoutService caps a
# withdrawal at the venture's ledger balance, so an unfunded award is directly
# withdrawable out of *other students'* sales revenue.
RSpec.describe Fuime::SchoolAwardService do
  let(:school_tree) { build_school_tree }
  let(:school)  { school_tree[0] }
  let(:venture) { school_tree[2] }

  let!(:school_account) { create(:stripe_connected_account, :ready, event: school) }
  let!(:guide)   { create_school_manager(school) }
  let!(:student) { create_student(venture) }

  let(:service) { described_class.new(venture:) }

  # Put real settled money on an event, the way a sale or a bank funding would.
  def credit!(event, cents)
    ct = create(:canonical_transaction, amount_cents: cents, date: Date.current, memo: "Funding")
    create(:canonical_event_mapping, canonical_transaction: ct, event:)
  end

  describe "#available_to_award_cents" do
    it "is the school's own balance, not the whole programme's" do
      credit!(school, 50_000)
      credit!(venture, 900_000)

      # The venture's own sales are not the school's to give away.
      expect(service.available_to_award_cents).to eq(50_000)
    end

    it "is zero when the school has nothing" do
      expect(service.available_to_award_cents).to eq(0)
    end

    it "floors at zero rather than reporting a negative" do
      credit!(school, -5_000)

      expect(service.available_to_award_cents).to eq(0)
    end
  end

  describe "#grant!" do
    before { credit!(school, 100_000) }

    it "moves the money and conserves the total" do
      before_total = school.balance_v2_cents + venture.balance_v2_cents

      service.grant!(amount_cents: 10_000, awarded_to: student, awarded_by: guide)

      expect(school.reload.balance_v2_cents).to eq(90_000)
      expect(venture.reload.balance_v2_cents).to eq(10_000)
      expect(school.balance_v2_cents + venture.balance_v2_cents).to eq(before_total)
    end

    # There is nothing at Stripe to call. The money is already in the account; only
    # its attribution changes.
    it "never talks to Stripe" do
      expect(Stripe::Payout).not_to receive(:create)
      expect(Stripe::Transfer).not_to receive(:create) if defined?(Stripe::Transfer)

      service.grant!(amount_cents: 10_000, awarded_to: student, awarded_by: guide)
    end

    # The load-bearing safety property. Without the funding check, this $100 would be
    # withdrawable by the student straight out of the other ventures' revenue.
    it "refuses an award the school cannot fund" do
      expect { service.grant!(amount_cents: 200_000, awarded_to: student, awarded_by: guide) }
        .to raise_error(described_class::SchoolUnderfunded, /\$1,000\.00 available to award/)
    end

    it "refuses a second award that would overdraw the school" do
      service.grant!(amount_cents: 60_000, awarded_to: student, awarded_by: guide)

      expect { service.grant!(amount_cents: 60_000, awarded_to: student, awarded_by: guide) }
        .to raise_error(described_class::SchoolUnderfunded)
    end

    it "posts nothing when it refuses" do
      expect {
        begin
          service.grant!(amount_cents: 200_000, awarded_to: student, awarded_by: guide)
        rescue described_class::SchoolUnderfunded
          nil
        end
      }.not_to change { CanonicalEventMapping.where(event_id: venture.id).count }
    end

    it "refuses on a venture outside a school programme" do
      ordinary = create(:event)
      create(:stripe_connected_account, :ready, event: ordinary)

      expect { described_class.new(venture: ordinary).grant!(amount_cents: 1_000, awarded_to: student, awarded_by: guide) }
        .to raise_error(described_class::NotASchoolVenture)
    end

    it "records who earned it, who granted it, and the school's own reference" do
      award = service.grant!(amount_cents: 10_000, awarded_to: student, awarded_by: guide,
                             reference: "gradebook-4417")

      expect(award.awarded_to).to eq(student)
      expect(award.awarded_by).to eq(guide)
      expect(award.school_event).to eq(school)
      expect(award.reference).to eq("gradebook-4417")
    end

    # The money is spendable and withdrawable immediately: it is already available at
    # Stripe, so posting it pending would hide it from `balance_v2_cents` — the exact
    # figure the payout cap reads.
    it "makes the award immediately withdrawable" do
      allow(Stripe::Balance).to receive(:retrieve).and_return(
        Stripe::Balance.construct_from(available: [{ currency: "usd", amount: 900_000 }])
      )

      service.grant!(amount_cents: 10_000, awarded_to: student, awarded_by: guide)

      expect(Fuime::PayoutService.new(event: venture.reload).available_balance_cents).to eq(10_000)
    end
  end

  describe "#void!" do
    before { credit!(school, 100_000) }

    let(:award) { service.grant!(amount_cents: 10_000, awarded_to: student, awarded_by: guide) }

    it "returns the money to the school and conserves the total" do
      service.void!(award:, voided_by: guide, reason: "Entered twice")

      expect(school.reload.balance_v2_cents).to eq(100_000)
      expect(venture.reload.balance_v2_cents).to eq(0)
      expect(award.reload).to be_voided
      expect(award.void_reason).to eq("Entered twice")
    end

    # Not a destroy. The money did move, and erasing the original lines would misstate
    # what the student's balance was and when.
    it "leaves the original lines in place and adds reversing ones" do
      service.void!(award:, voided_by: guide)

      amounts = CanonicalEventMapping.where(event_id: venture.id)
                                     .map { |m| m.canonical_transaction.amount_cents }

      expect(amounts).to contain_exactly(10_000, -10_000)
    end

    it "refuses to void twice" do
      service.void!(award:, voided_by: guide)

      expect { service.void!(award: award.reload, voided_by: guide) }
        .to raise_error(described_class::Error)
    end

    # If the student already spent it, the venture goes negative. That is the truth,
    # and the same shape as a chargeback landing after the money was used.
    it "lets the venture go negative rather than silently refusing" do
      create(:canonical_transaction, amount_cents: -10_000, date: Date.current, memo: "Supplies").tap do |ct|
        create(:canonical_event_mapping, canonical_transaction: ct, event: venture)
      end

      service.void!(award:, voided_by: guide)

      expect(venture.reload.balance_v2_cents).to eq(-10_000)
    end
  end

  # The user's rule: only incoming sales move the tax tracker.
  describe "the tax tracker" do
    before { credit!(school, 100_000) }

    it "does not count an award as the venture's business revenue" do
      service.grant!(amount_cents: 10_000, awarded_to: student, awarded_by: guide)

      tracker = Fuime::TaxTrackerService.new(event: venture.reload)

      # A capital contribution never appears on Schedule C. Counting it would inflate
      # the profit a family is told to pay self-employment tax on.
      expect(tracker.income_cents).to eq(0)
      expect(tracker.net_income_cents).to eq(0)
    end

    it "does not count the school's side as a deductible expense either" do
      service.grant!(amount_cents: 10_000, awarded_to: student, awarded_by: guide)

      expect(Fuime::TaxTrackerService.new(event: school.reload).expenses_cents).to eq(0)
    end

    it "does not count a voided award in either direction" do
      award = service.grant!(amount_cents: 10_000, awarded_to: student, awarded_by: guide)
      service.void!(award:, voided_by: guide)

      tracker = Fuime::TaxTrackerService.new(event: venture.reload)

      expect(tracker.income_cents).to eq(0)
      expect(tracker.expenses_cents).to eq(0)
    end

    # The paired assertion: real sales still count, so the exclusion is not a blanket
    # off-switch.
    it "still counts an actual sale" do
      ct = create(:canonical_transaction, amount_cents: 25_000, date: Date.current,
                                          memo: "Payment to Angus's Mowing")
      create(:canonical_event_mapping, canonical_transaction: ct, event: venture)

      service.grant!(amount_cents: 10_000, awarded_to: student, awarded_by: guide)

      expect(Fuime::TaxTrackerService.new(event: venture.reload).income_cents).to eq(25_000)
    end
  end
end
