# frozen_string_literal: true

require "rails_helper"

# Fuime: who may end or re-send a guardianship. These are legal controls —
# particularly that a minor cannot remove their own supervision.
RSpec.describe GuardianshipPolicy do
  let(:guardian)  { create(:user, birthday: 40.years.ago.to_date) }
  let(:minor)     { create(:user, :minor) }
  let(:stranger)  { create(:user, birthday: 30.years.ago.to_date) }
  let(:admin)     { create(:user, :make_admin, birthday: 30.years.ago.to_date) }

  describe "#revoke?" do
    subject(:guardianship) { create(:guardianship, :active, guardian:, minor:) }

    it "allows the guardian who gave consent" do
      expect(described_class.new(guardian, guardianship).revoke?).to be true
    end

    it "allows an admin, for support cases" do
      expect(described_class.new(admin, guardianship).revoke?).to be true
    end

    # The whole point of the control.
    it "does NOT allow the minor to remove their own supervision" do
      expect(described_class.new(minor, guardianship).revoke?).to be false
    end

    it "does not allow an unrelated user" do
      expect(described_class.new(stranger, guardianship).revoke?).to be false
    end

    it "does not allow revoking twice" do
      guardianship.revoke!

      expect(described_class.new(guardian, guardianship).revoke?).to be false
    end
  end

  describe "#resend_invite?" do
    subject(:guardianship) { create(:guardianship, guardian:, minor:) }

    it "allows the minor, who is the one chasing their parent" do
      expect(described_class.new(minor, guardianship).resend_invite?).to be true
    end

    it "allows the guardian and an admin" do
      expect(described_class.new(guardian, guardianship).resend_invite?).to be true
      expect(described_class.new(admin, guardianship).resend_invite?).to be true
    end

    it "does not allow an unrelated user" do
      expect(described_class.new(stranger, guardianship).resend_invite?).to be false
    end

    it "does not apply once the guardianship is active" do
      active = create(:guardianship, :active, guardian:, minor:)

      expect(described_class.new(minor, active).resend_invite?).to be false
    end
  end

  describe "#record?" do
    subject(:guardianship) { create(:guardianship, :active, guardian:, minor:) }

    it "allows everyone the agreement binds, plus admins" do
      expect(described_class.new(guardian, guardianship).record?).to be true
      expect(described_class.new(minor, guardianship).record?).to be true
      expect(described_class.new(admin, guardianship).record?).to be true
    end

    it "does not let an unrelated user read someone else's agreement" do
      expect(described_class.new(stranger, guardianship).record?).to be false
    end

    it "does not allow a signed-out visitor" do
      expect(described_class.new(nil, guardianship).record?).to be false
    end

    # Revoked agreements stay readable: the record of what was signed is the
    # point, and revocation does not erase it.
    it "stays readable after revocation" do
      guardianship.revoke!

      expect(described_class.new(guardian, guardianship).record?).to be true
    end
  end

  describe "#show? / #accept?" do
    subject(:guardianship) { create(:guardianship, guardian:, minor:) }

    it "is limited to the invited guardian" do
      expect(described_class.new(guardian, guardianship).show?).to be true
      expect(described_class.new(minor, guardianship).show?).to be false
      expect(described_class.new(stranger, guardianship).show?).to be false
    end

    it "only allows accepting a pending invite" do
      expect(described_class.new(guardian, guardianship).accept?).to be true

      guardianship.accept!
      expect(described_class.new(guardian, guardianship).accept?).to be false
    end
  end
end
