# frozen_string_literal: true

require "rails_helper"

# Fuime: who may do what with a business card.
#
# The point of these four predicates is that they do NOT all resolve to the same person.
# The teen operates the business; the guardian is the Accountholder who carries the card
# liability. Every predicate that increases what can be spent belongs to the guardian, and
# the one that only ever reduces it belongs to both.
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

  describe "#cards?" do
    it "is readable by the team and the guardian" do
      expect(policy_for(minor).cards?).to be true
      expect(policy_for(guardian).cards?).to be true
    end

    it "is not readable by an unrelated user" do
      expect(policy_for(create(:user)).cards?).to be false
    end
  end

  describe "#issue_cards? and #manage_cards?" do
    # Issuing creates a liability, and raising a limit increases what can be spent. Both
    # are the Accountholder's decisions.
    it "belong to the guardian" do
      expect(policy_for(guardian).issue_cards?).to be true
      expect(policy_for(guardian).manage_cards?).to be true
    end

    it "are refused to the teen who runs the venture" do
      expect(policy_for(minor).issue_cards?).to be false
      expect(policy_for(minor).manage_cards?).to be false
    end

    it "are refused to an unrelated adult" do
      stranger = create(:user, birthday: 35.years.ago.to_date)

      expect(policy_for(stranger).issue_cards?).to be false
      expect(policy_for(stranger).manage_cards?).to be false
    end

    it "are refused to a signed-out visitor" do
      expect(policy_for(nil).issue_cards?).to be false
      expect(policy_for(nil).manage_cards?).to be false
    end

    it "are allowed to admins, for support" do
      admin = create(:user, :admin)

      expect(policy_for(admin).issue_cards?).to be true
      expect(policy_for(admin).manage_cards?).to be true
    end

    it "are refused to a guardian whose guardianship is only pending" do
      other_minor = create(:user, :minor)
      pending_guardian = create(:user, birthday: 40.years.ago.to_date)
      create(:organizer_position, event:, user: other_minor)
      create(:guardianship, guardian: pending_guardian, minor: other_minor)

      expect(policy_for(pending_guardian).manage_cards?).to be false
    end
  end

  describe "#freeze_cards?" do
    # THE deliberate exception. A teenager who has lost their card needs to stop it in the
    # moment rather than wait for a parent to wake up, and freezing can only ever reduce
    # what is spendable.
    it "is allowed to the teen" do
      expect(policy_for(minor).freeze_cards?).to be true
    end

    it "is allowed to the guardian" do
      expect(policy_for(guardian).freeze_cards?).to be true
    end

    it "is refused to an unrelated user" do
      expect(policy_for(create(:user)).freeze_cards?).to be false
    end
  end

  # The asymmetry stated as one assertion, because it is the design and not an accident:
  # a teen can take spending away but cannot give it back.
  describe "the freeze/unfreeze asymmetry" do
    it "lets the teen reduce spending but never restore it" do
      policy = policy_for(minor)

      expect(policy.freeze_cards?).to be true
      expect(policy.manage_cards?).to be false
    end
  end

  # Pundit resolves a query with `public_send`, so a predicate below the `private` keyword
  # raises NoMethodError on every request — which is exactly what happened to
  # #setup_payments? and 500'd the whole Connect onboarding flow.
  describe "Pundit reachability" do
    it "exposes every card predicate publicly" do
      policy = policy_for(minor)

      %i[cards? issue_cards? manage_cards? freeze_cards?].each do |query|
        expect { policy.public_send(query) }.not_to raise_error, "#{query} must be public for Pundit"
      end
    end
  end
end
