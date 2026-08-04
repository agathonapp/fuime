# frozen_string_literal: true

require "rails_helper"

# Fuime: who may set up the venture's payment account.
#
# This is the one place where a guardian is deliberately allowed to *write*
# something in a venture's orbit. EventPolicy otherwise keeps them strictly
# read-only — `member?` and `manager?` both require an OrganizerPosition a
# guardian never holds — and the comment on `guardian_reader?` says outright that
# "a guardian can see a venture and act on nothing in it."
#
# The exception is principled rather than convenient: the thing being written is
# not the venture, it is the guardian's own Stripe account. Stripe requires the
# owner of an under-18 account to be the adult, and onboarding collects that
# adult's date of birth, address and SSN last four. A teen cannot supply those and
# must not be asked to — so the teen is excluded from setup even though they run
# the business.
RSpec.describe EventPolicy, type: :policy do
  let(:event) { create(:event) }
  let(:minor) { create(:user, :minor) }
  let(:guardian) { create(:user) }

  before { create(:organizer_position, event:, user: minor) }

  def policy_for(user)
    described_class.new(user, event)
  end

  describe "#setup_payments?" do
    it "allows the venture's active guardian" do
      create(:guardianship, :active, guardian:, minor:)

      expect(policy_for(guardian).setup_payments?).to be true
    end

    # The teen operates the business and still cannot do this — see the class
    # comment. This is the example most likely to look like a bug to someone who
    # has not read why.
    it "refuses the minor who runs the venture" do
      create(:guardianship, :active, guardian:, minor:)

      expect(policy_for(minor).setup_payments?).to be false
    end

    it "refuses a guardian whose invite is still pending" do
      create(:guardianship, guardian:, minor:)

      expect(policy_for(guardian).setup_payments?).to be false
    end

    it "refuses an unrelated adult" do
      create(:guardianship, :active, guardian:, minor:)

      expect(policy_for(create(:user)).setup_payments?).to be false
    end

    it "allows admins, for support" do
      expect(policy_for(create(:user, :make_admin)).setup_payments?).to be true
    end

    it "refuses a signed-out visitor" do
      expect(policy_for(nil).setup_payments?).to be false
    end
  end

  # The status page is wider than the setup action on purpose: a teen needs to
  # know whether they can be paid and whose action is outstanding, even though
  # they cannot act on it.
  describe "#payment_setup_status?" do
    it "allows the team to see the status" do
      expect(policy_for(minor).payment_setup_status?).to be true
    end

    it "allows the guardian to see the status" do
      create(:guardianship, :active, guardian:, minor:)

      expect(policy_for(guardian).payment_setup_status?).to be true
    end

    it "refuses an unrelated adult" do
      expect(policy_for(create(:user)).payment_setup_status?).to be false
    end
  end
end
