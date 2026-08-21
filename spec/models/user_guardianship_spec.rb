# frozen_string_literal: true

require "rails_helper"

# Fuime: the age and guardianship rules that gate operating a business.
# See docs/fuime/PRODUCTION_READINESS.md §1.1.
RSpec.describe User, "Fuime age and guardianship rules" do
  describe "#minor_or_unknown_age?" do
    it "is true for a minor" do
      expect(build(:user, :minor).minor_or_unknown_age?).to be true
    end

    it "is false for an adult" do
      expect(build(:user, birthday: 30.years.ago.to_date).minor_or_unknown_age?).to be false
    end

    # The original defect: `is_minor?` is nil with no birthday, which is falsy,
    # so every guard silently passed for a user who skipped the field.
    it "is true when the age is unknown" do
      expect(build(:user, :unknown_age).minor_or_unknown_age?).to be true
    end
  end

  describe "#known_adult?" do
    it "is true only when we positively know the user is 18+" do
      expect(build(:user, birthday: 30.years.ago.to_date).known_adult?).to be true
      expect(build(:user, :minor).known_adult?).to be false
      expect(build(:user, :unknown_age).known_adult?).to be false
    end
  end

  # The gates above are fail-closed on a missing birthday, and no staff account
  # has one — so without this exemption every Fuime admin reads as a parentless
  # minor and is refused on their own account (the family plan being the case
  # that surfaced it).
  describe "#staff?" do
    it "is true for admins and auditors" do
      expect(build(:user, :make_admin, :unknown_age).staff?).to be true
      expect(build(:user, :make_auditor, :unknown_age).staff?).to be true
    end

    it "is false for an ordinary user" do
      expect(build(:user).staff?).to be false
    end

    # An admin who has asked to be treated as a normal user means it — including
    # the gates, which is the only way to preview what a teen actually hits.
    it "is false for an admin pretending not to be one" do
      expect(build(:user, :make_admin, pretend_is_not_admin: true).staff?).to be false
    end
  end

  describe "#permitted_to_operate_business?" do
    it "allows an adult" do
      expect(create(:user, birthday: 30.years.ago.to_date).permitted_to_operate_business?).to be true
    end

    it "denies a minor with no guardian" do
      expect(create(:user, :minor).permitted_to_operate_business?).to be false
    end

    it "denies a user whose age is unknown" do
      expect(create(:user, :unknown_age).permitted_to_operate_business?).to be false
    end

    it "denies a minor whose guardianship is still pending" do
      teen = create(:user, :minor)
      create(:guardianship, minor: teen, guardian: create(:user, birthday: 40.years.ago.to_date))

      expect(teen.reload.permitted_to_operate_business?).to be false
    end

    it "allows a minor with an ACTIVE guardianship" do
      expect(create(:user, :minor_with_guardian).permitted_to_operate_business?).to be true
    end

    it "denies a minor once the guardianship is revoked" do
      teen = create(:user, :minor)
      guardianship = create(
        :guardianship, :active,
        minor: teen,
        guardian: create(:user, birthday: 40.years.ago.to_date)
      )
      expect(teen.reload.permitted_to_operate_business?).to be true

      guardianship.revoke!

      expect(teen.reload.permitted_to_operate_business?).to be false
    end
  end

  describe "COPPA minimum age" do
    it "refuses a signup under 13" do
      user = build(:user, birthday: 11.years.ago.to_date)

      expect(user).not_to be_valid
      expect(user.errors[:birthday].join).to match(/under 13/i)
    end

    it "accepts a 13-year-old" do
      expect(build(:user, birthday: 13.years.ago.to_date - 1.day)).to be_valid
    end
  end

  describe "an age answer required to finish onboarding" do
    # The bypass: with nothing on file the under-13 check never ran and the
    # guardian requirement never fired.
    #
    # Signup asks for a checkbox rather than a date now
    # (AddAgeAttestationToUsers), so the requirement moved with it. The property is
    # unchanged: onboarding cannot complete without an answer.
    it "is invalid on the :onboarding context without an age answer" do
      user = create(:user, :unknown_age)

      expect(user.valid?(:onboarding)).to be false
      expect(user.errors[:age_attestation].join).to match(/required/i)
    end

    it "is valid on the :onboarding context once the box is ticked" do
      expect(create(:user, :attested_teen).valid?(:onboarding)).to be true
    end

    # Users who onboarded before the switch answered in a more precise way and must
    # not be sent back to re-answer.
    it "is valid on the :onboarding context with a birthday already on file" do
      expect(create(:user, birthday: 16.years.ago.to_date).valid?(:onboarding)).to be true
    end

    # Organizer invites, guardian stubs, and seeds create users without a
    # birthday; that must keep working outside the onboarding submission.
    it "does not block ordinary creation without a birthday" do
      expect(build(:user, :unknown_age)).to be_valid
    end
  end
end
