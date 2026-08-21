# frozen_string_literal: true

require "rails_helper"

RSpec.describe Guardianship do
  let(:adult) { create(:user, birthday: 40.years.ago.to_date) }
  let(:teen)  { create(:user, :minor) }

  describe "validations" do
    it "is valid for an adult guardian and a minor" do
      expect(build(:guardianship, guardian: adult, minor: teen)).to be_valid
    end

    it "rejects a guardian who is known to be a minor" do
      guardianship = build(:guardianship, guardian: create(:user, :minor), minor: teen)

      expect(guardianship).not_to be_valid
      expect(guardianship.errors[:guardian]).to include("must be 18 or older")
    end

    # A guardian invited by email starts as a stub with no birthday. Creation
    # must succeed so they can be invited at all; activation is what's gated.
    it "allows creation when the guardian's age is not yet known" do
      stub = create(:user, :unknown_age)

      expect(build(:guardianship, guardian: stub, minor: teen)).to be_valid
    end

    it "rejects a guardian who is also the minor" do
      guardianship = build(:guardianship, guardian: adult, minor: adult)

      expect(guardianship).not_to be_valid
    end

    it "rejects a duplicate guardian/minor pair" do
      create(:guardianship, guardian: adult, minor: teen)
      duplicate = build(:guardianship, guardian: adult, minor: teen)

      expect(duplicate).not_to be_valid
    end
  end

  describe "#activation_blockers" do
    it "is empty for a confirmed adult guardian" do
      guardianship = create(:guardianship, guardian: adult, minor: teen)

      expect(guardianship.activation_blockers).to be_empty
      expect(guardianship).to be_activatable
    end

    # The core §1.2 defect: a stub guardian who has told us nothing used to pass
    # `is_minor?` (nil, falsy) and could sign as the responsible adult. Still
    # fail-closed; the sentence now asks them to tick the 18+ box rather than to
    # enter a date of birth, which since 2026-08-20 there is nowhere to enter.
    it "blocks activation when the guardian's age is unknown" do
      stub = create(:user, :unknown_age)
      guardianship = create(:guardianship, guardian: stub, minor: teen)

      expect(guardianship).not_to be_activatable
      expect(guardianship.activation_blockers.join).to match(/18 or older/i)
    end

    # The replacement route to the same assertion. See
    # GuardianshipsController#accept: the acceptance box carries the 18+ claim.
    it "is activatable once the guardian has confirmed they're 18 or older" do
      stub = create(:user, :unknown_age)
      guardianship = create(:guardianship, guardian: stub, minor: teen)

      stub.attest_adult_18_plus!
      expect(guardianship.reload).to be_activatable
    end
  end

  describe "#accept!" do
    it "activates and records the consent evidence" do
      guardianship = create(:guardianship, guardian: adult, minor: teen)

      expect(
        guardianship.accept!(consent_ip: "203.0.113.7", consent_user_agent: "Firefox")
      ).to be true

      guardianship.reload
      expect(guardianship).to be_active
      expect(guardianship.agreement_signed_at).to be_present
      expect(guardianship.agreement_version).to eq(described_class::CURRENT_AGREEMENT_VERSION)
      expect(guardianship.agreement_ip).to eq("203.0.113.7")
      expect(guardianship.agreement_user_agent).to eq("Firefox")
    end

    it "clears the invite token so the link cannot be replayed" do
      guardianship = create(:guardianship, guardian: adult, minor: teen)
      token = guardianship.invite_token

      guardianship.accept!

      expect(guardianship.reload.invite_token).to be_nil
      expect(described_class.find_by_token(token)).to be_nil
    end

    it "refuses to activate when a precondition fails" do
      guardianship = create(:guardianship, guardian: create(:user, :unknown_age), minor: teen)

      expect(guardianship.accept!).to be false
      expect(guardianship.reload).to be_pending
    end
  end

  describe "#revoke!" do
    it "records who revoked it and when" do
      guardianship = create(:guardianship, :active, guardian: adult, minor: teen)

      guardianship.revoke!(revoked_by: adult)

      guardianship.reload
      expect(guardianship).to be_revoked
      expect(guardianship.revoked_at).to be_present
      expect(guardianship.revoked_by_id).to eq(adult.id)
    end

    it "immediately removes the minor's ability to operate a business" do
      guardianship = create(:guardianship, :active, guardian: adult, minor: teen)
      expect(teen.reload.permitted_to_operate_business?).to be true

      guardianship.revoke!(revoked_by: adult)

      expect(teen.reload.permitted_to_operate_business?).to be false
    end
  end

  describe ".find_by_token" do
    it "finds a pending invite" do
      guardianship = create(:guardianship, guardian: adult, minor: teen)

      expect(described_class.find_by_token(guardianship.invite_token)).to eq(guardianship)
    end

    it "does not find an expired invite" do
      guardianship = create(:guardianship, :expired_invite, guardian: adult, minor: teen)

      expect(described_class.find_by_token(guardianship.invite_token)).to be_nil
    end

    it "does not find a revoked invite" do
      guardianship = create(:guardianship, guardian: adult, minor: teen)
      token = guardianship.invite_token
      guardianship.revoke!

      expect(described_class.find_by_token(token)).to be_nil
    end

    it "returns nil for a blank or unknown token" do
      expect(described_class.find_by_token(nil)).to be_nil
      expect(described_class.find_by_token("")).to be_nil
      expect(described_class.find_by_token("nope")).to be_nil
    end
  end

  describe "#resend_invite!" do
    it "issues a fresh token and refreshes the clock" do
      guardianship = create(:guardianship, :expired_invite, guardian: adult, minor: teen)
      old_token = guardianship.invite_token

      expect(guardianship.resend_invite!).to be true

      guardianship.reload
      expect(guardianship.invite_token).not_to eq(old_token)
      expect(guardianship).not_to be_invite_expired
      expect(described_class.find_by_token(guardianship.invite_token)).to eq(guardianship)
    end

    it "does nothing for an already-active guardianship" do
      guardianship = create(:guardianship, :active, guardian: adult, minor: teen)

      expect(guardianship.resend_invite!).to be false
    end
  end
end
