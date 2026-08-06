# frozen_string_literal: true

require "rails_helper"

# Fuime: who acts on money inside a school programme.
#
# The bug these pin was not a locked door, it was a trap. On a school venture no
# Guardianship row exists or should — the school is in loco parentis — so
# `decide_payout?` resolving through `guardian_reader?` could never pass. But
# `request_payout?` resolves through `member?`, and #permitted_to_operate_business?
# lets a school's students through. So a student could file a payout request that
# nobody on earth except a Fuime admin could then approve, and
# `one_pending_request_per_venture` stopped them from ever filing another.
#
# The paired assertions matter as much as the positive ones: none of this may become
# a route for a family venture to bypass its guardian.
RSpec.describe EventPolicy, "school money decisions", type: :policy do
  let(:school_tree) { build_school_tree }
  let(:school)  { school_tree[0] }
  let(:venture) { school_tree[2] }

  let!(:guide)   { create_school_manager(school) }
  let!(:student) { create_student(venture) }

  def policy_for(user, record = venture)
    described_class.new(user, record)
  end

  describe "#decide_payout?" do
    # Authority resolves through the tree: a guide holds manager on the school, not
    # on several hundred student sub orgs.
    it "allows a manager of the school on a student's venture" do
      expect(policy_for(guide).decide_payout?).to be true
    end

    it "still refuses the student who runs the venture" do
      # The whole content of an approval gate. A manager is >= member, so this has
      # to hold on the school path too, and PayoutRequest re-asserts it.
      expect(policy_for(student).decide_payout?).to be false
    end

    it "refuses a manager of an unrelated school" do
      other_school, _cohort, _other_venture = build_school_tree(school_name: "Beta School")
      outsider = create_school_manager(other_school)

      expect(policy_for(outsider).decide_payout?).to be false
    end

    it "refuses a signed-out visitor" do
      expect(policy_for(nil).decide_payout?).to be false
    end

    # The family model is untouched: a manager on an ordinary venture is not a
    # guardian and still cannot release money.
    it "does not let a manager decide on a venture with no institutional sponsor" do
      ordinary = create(:event)
      manager = create(:user, birthday: 40.years.ago.to_date)
      create(:organizer_position, event: ordinary, user: manager, role: :manager)

      expect(described_class.new(manager, ordinary).decide_payout?).to be false
    end
  end

  describe "#settle_payout?" do
    it "allows a manager of the school" do
      expect(policy_for(guide).settle_payout?).to be true
    end

    it "refuses the student" do
      expect(policy_for(student).settle_payout?).to be false
    end

    # Only the school path has a settlement step at all — on a family venture Stripe
    # says when the money landed and there is nothing for a human to assert.
    it "refuses everyone on a venture with no institutional sponsor" do
      ordinary = create(:event)
      guardian = create(:user, birthday: 40.years.ago.to_date)
      minor = create(:user, :minor)
      create(:organizer_position, event: ordinary, user: minor)
      create(:guardianship, :active, guardian:, minor:)

      expect(described_class.new(guardian, ordinary).settle_payout?).to be false
    end

    it "allows admins, for support" do
      expect(policy_for(create(:user, :admin)).settle_payout?).to be true
    end
  end

  # Without these a school student could not spend the balance either, which means
  # "leave it in and reinvest" was not actually one of the options.
  describe "cards" do
    it "lets a school manager issue and manage cards" do
      expect(policy_for(guide).issue_cards?).to be true
      expect(policy_for(guide).manage_cards?).to be true
    end

    it "still refuses the student, who may only freeze" do
      expect(policy_for(student).issue_cards?).to be false
      expect(policy_for(student).manage_cards?).to be false
    end

    it "does not let a manager of an ordinary venture issue cards" do
      ordinary = create(:event)
      manager = create(:user, birthday: 40.years.ago.to_date)
      create(:organizer_position, event: ordinary, user: manager, role: :manager)

      expect(described_class.new(manager, ordinary).issue_cards?).to be false
    end
  end

  # Pins the trap itself, end to end: the student can still ask, and now somebody
  # other than a Fuime admin can answer.
  describe "the wedge that started this" do
    it "gives every request a reachable decision-maker" do
      expect(policy_for(student).request_payout?).to be true
      expect(policy_for(guide).decide_payout?).to be true
    end
  end
end
