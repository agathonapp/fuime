# frozen_string_literal: true

require "rails_helper"

# Fuime: the record-level rules for money out of a school venture.
#
# Defence in depth behind EventPolicy. Everything asserted here is also enforced in
# the policy layer, and it is enforced twice because a single missed check is a minor
# moving money out of an account they do not own, or one student moving another
# student's revenue.
RSpec.describe PayoutRequest, "inside a school programme", type: :model do
  let(:school_tree) { build_school_tree }
  let(:school)  { school_tree[0] }
  let(:venture) { school_tree[2] }

  let!(:school_account) { create(:stripe_connected_account, :ready, event: school) }
  let!(:guide)   { create_school_manager(school) }
  let!(:student) { create_student(venture) }

  def build_request(**attrs)
    described_class.new(
      {
        event: venture,
        requested_by: student,
        amount_cents: 4_000,
        destination: described_class::PERSONAL_TRANSFER
      }.merge(attrs)
    )
  end

  describe "who may be recorded as the approver" do
    it "accepts a manager of the sponsoring school" do
      expect(build_request(approved_by: guide)).to be_valid
    end

    # The original rule required an overseeing guardian, of which a school venture
    # has none by design — so no adult at the school could be recorded, and the
    # request could never be approved by anyone but a Fuime admin.
    it "refuses an adult with no role in the programme" do
      request = build_request(approved_by: create(:user, birthday: 40.years.ago.to_date))

      expect(request).not_to be_valid
      expect(request.errors[:approved_by]).to include("must be a manager of the sponsoring school")
    end

    it "refuses a manager of a different school" do
      other_school, _cohort, _v = build_school_tree(school_name: "Beta School")
      request = build_request(approved_by: create_school_manager(other_school))

      expect(request).not_to be_valid
    end

    it "still allows an admin, for support on a stuck request" do
      expect(build_request(approved_by: create(:user, :admin))).to be_valid
    end

    # The family rule is unchanged.
    it "still requires an overseeing guardian on a venture with no sponsor" do
      ordinary = create(:event)
      create(:stripe_connected_account, :ready, event: ordinary)
      minor = create(:user, :minor)
      create(:organizer_position, event: ordinary, user: minor)

      request = described_class.new(
        event: ordinary, requested_by: minor, amount_cents: 4_000,
        destination: described_class::ACCOUNT_OWNER_BANK,
        approved_by: create(:user, birthday: 40.years.ago.to_date)
      )

      expect(request).not_to be_valid
      expect(request.errors[:approved_by]).to include("must be a guardian overseeing this venture")
    end
  end

  describe "self-approval" do
    # On a family venture this is true structurally — requesting needs member,
    # deciding needs guardian, and a guardian is read-only. On a school venture it is
    # not: a manager is >= member, so the same guide could file and approve in two
    # clicks. Segregation of duties is the entire content of an approval gate.
    it "refuses an approver who is also the requester" do
      request = build_request(requested_by: guide, approved_by: guide)

      expect(request).not_to be_valid
      expect(request.errors[:approved_by]).to include("can't approve their own payout request")
    end

    # No exemption. An admin approving a request an admin filed is precisely this.
    it "refuses it for admins too" do
      admin = create(:user, :admin)
      request = build_request(requested_by: admin, approved_by: admin)

      expect(request).not_to be_valid
    end
  end

  describe "which destination a venture may ask for" do
    it "allows a personal transfer on a venture sharing the school's account" do
      expect(build_request).to be_valid
    end

    # Would send the pooled balance of every student in the programme to the
    # school's bank on one student's request.
    it "refuses a Stripe payout from the shared account" do
      request = build_request(destination: described_class::ACCOUNT_OWNER_BANK)

      expect(request).not_to be_valid
      expect(request.errors[:destination].join).to match(/school's account/)
    end

    it "allows a Stripe payout on the school org itself, which owns its account" do
      request = described_class.new(
        event: school, requested_by: create_student(school), amount_cents: 4_000,
        destination: described_class::ACCOUNT_OWNER_BANK
      )

      expect(request).to be_valid
    end

    it "refuses a personal transfer on a family venture" do
      ordinary = create(:event)
      create(:stripe_connected_account, :ready, event: ordinary)
      minor = create(:user, :minor)
      create(:organizer_position, event: ordinary, user: minor)

      request = described_class.new(
        event: ordinary, requested_by: minor, amount_cents: 4_000,
        destination: described_class::PERSONAL_TRANSFER
      )

      expect(request).not_to be_valid
    end

    it "refuses an unknown destination" do
      expect(build_request(destination: "cash_in_an_envelope")).not_to be_valid
    end

    # When nothing has onboarded, neither destination message would be true — the
    # real problem is setup, which Fuime::PayoutService reports as NotSetUp.
    it "says nothing about destinations when no account exists anywhere" do
      school_account.destroy!
      request = build_request
      request.valid?

      expect(request.errors[:destination]).to be_empty
    end
  end

  describe "the settlement state" do
    it "reports awaiting_settlement only for an approved personal transfer" do
      request = build_request(approved_by: guide, aasm_state: "approved")

      expect(request.awaiting_settlement?).to be true
      expect(request.personal_transfer?).to be true
    end

    it "does not report it for a Stripe payout" do
      ordinary = create(:event)
      create(:stripe_connected_account, :ready, event: ordinary)

      request = described_class.new(
        event: ordinary, requested_by: create(:user, :minor), amount_cents: 4_000,
        destination: described_class::ACCOUNT_OWNER_BANK, aasm_state: "approved"
      )

      expect(request.awaiting_settlement?).to be false
    end

    it "does not report it while still pending" do
      expect(build_request.awaiting_settlement?).to be false
    end
  end

  describe "defaults" do
    # Every row that existed before the destination column keeps meaning what it
    # meant, which is why the column defaults rather than being backfilled.
    it "defaults to the Stripe payout destination" do
      ordinary = create(:event)
      create(:stripe_connected_account, :ready, event: ordinary)
      request = create(:payout_request, event: ordinary)

      expect(request.destination).to eq(described_class::ACCOUNT_OWNER_BANK)
      expect(request.account_owner_bank?).to be true
    end
  end
end
