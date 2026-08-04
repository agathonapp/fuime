# frozen_string_literal: true

require "rails_helper"

# Fuime: who may ask for money and who may release it.
#
# The separation asserted here is the control that makes "the parent owns the
# account and the funds" true rather than decorative (CLAUDE.md L2). It is enforced
# in three places on purpose — this policy, Fuime::PayoutService, and PayoutRequest
# — because a single missed check is a minor moving money out of an account they
# do not own.
RSpec.describe EventPolicy, type: :policy do
  let(:event) { create(:event) }
  let(:minor) { create(:user, :minor) }
  let(:guardian) { create(:user, birthday: 40.years.ago.to_date) }

  before do
    create(:organizer_position, event:, user: minor)
    create(:guardianship, :active, guardian:, minor:)
  end

  def policy_for(user)
    described_class.new(user, event)
  end

  describe "#request_payout?" do
    it "allows the teen who runs the venture" do
      expect(policy_for(minor).request_payout?).to be true
    end

    # A guardian is read-only on the venture by construction. Asking for a payout
    # is an operating decision, and operating is the teen's job.
    it "does not let the guardian request on the teen's behalf" do
      expect(policy_for(guardian).request_payout?).to be false
    end

    it "refuses an unrelated user" do
      expect(policy_for(create(:user)).request_payout?).to be false
    end

    it "refuses a signed-out visitor" do
      expect(policy_for(nil).request_payout?).to be false
    end

    it "allows admins, for support" do
      expect(policy_for(create(:user, :admin)).request_payout?).to be true
    end
  end

  describe "#decide_payout?" do
    it "allows the venture's active guardian" do
      expect(policy_for(guardian).decide_payout?).to be true
    end

    # THE rule. A teen approving their own payout request would make the guardian's
    # ownership of the funds meaningless.
    it "refuses the teen who runs the venture" do
      expect(policy_for(minor).decide_payout?).to be false
    end

    it "refuses a guardian whose guardianship is only pending" do
      other_minor = create(:user, :minor)
      pending_guardian = create(:user, birthday: 40.years.ago.to_date)
      create(:organizer_position, event:, user: other_minor)
      create(:guardianship, guardian: pending_guardian, minor: other_minor)

      expect(policy_for(pending_guardian).decide_payout?).to be false
    end

    it "refuses a guardian of a minor who is not on this venture" do
      unrelated_guardian = create(:user, birthday: 40.years.ago.to_date)
      create(:guardianship, :active, guardian: unrelated_guardian, minor: create(:user, :minor))

      expect(policy_for(unrelated_guardian).decide_payout?).to be false
    end

    it "refuses a signed-out visitor" do
      expect(policy_for(nil).decide_payout?).to be false
    end

    it "allows admins, for stuck payouts" do
      expect(policy_for(create(:user, :admin)).decide_payout?).to be true
    end
  end

  describe "#payouts?" do
    # Both parties need the screen: the teen to see the balance and their request's
    # state, the guardian to see what they are being asked to approve.
    it "is readable by the team and by the guardian" do
      expect(policy_for(minor).payouts?).to be true
      expect(policy_for(guardian).payouts?).to be true
    end

    it "is not readable by an unrelated user" do
      expect(policy_for(create(:user)).payouts?).to be false
    end
  end

  # Pundit resolves a query with `public_send`, so a predicate below the `private`
  # keyword raises NoMethodError on every request. That is exactly what happened to
  # #setup_payments? and #payment_setup_status?, and it 500'd the entire Connect
  # onboarding flow. This pins the visibility so it cannot regress silently.
  describe "Pundit reachability" do
    it "exposes every payout predicate publicly" do
      policy = policy_for(minor)

      %i[payouts? request_payout? decide_payout?].each do |query|
        expect { policy.public_send(query) }.not_to raise_error, "#{query} must be public for Pundit"
      end
    end

    it "exposes the payment setup predicates publicly" do
      policy = policy_for(minor)

      %i[setup_payments? payment_setup_status?].each do |query|
        expect { policy.public_send(query) }.not_to raise_error, "#{query} must be public for Pundit"
      end
    end
  end
end
