# frozen_string_literal: true

require "rails_helper"

# Fuime: a user who is already someone's signing guardian must not be asked to
# invite a guardian for themselves.
#
# Why this is safe rather than a hole in the age gate: minor_or_unknown_age? is
# fail-closed, so a user with no date of birth is treated as a minor — which is
# what made adults with incomplete profiles get sent to the guardian invite page.
# The exemption keys on an ACTIVE guardianship, and Guardianship's
# guardian_must_be_adult refuses to let one go active unless guardian.known_adult?
# is true. A pending guardianship proves nothing (two minors could name each
# other), so pending must NOT exempt.
RSpec.describe User, type: :model do
  describe "#needs_guardian?" do
    let(:adult_dob) { 30.years.ago.to_date }
    let(:teen_dob) { 15.years.ago.to_date }

    it "asks an adult with no date of birth for a guardian, as before" do
      user = create(:user, birthday: nil)

      expect(user.needs_guardian?).to be true
    end

    it "exempts a user who is the active guardian of someone else" do
      guardian = create(:user, birthday: adult_dob)
      minor = create(:user, birthday: teen_dob)
      Guardianship.create!(guardian:, minor:, status: :active)

      expect(guardian.guardian_of_active_ward?).to be true
      expect(guardian.needs_guardian?).to be false
    end

    it "does NOT exempt on a merely pending guardianship" do
      # The hole this closes: a guardianship can be created for a guardian whose
      # age is unknown, so pending is not evidence of adulthood.
      guardian = create(:user, birthday: nil)
      minor = create(:user, birthday: teen_dob)
      Guardianship.create!(guardian:, minor:, status: :pending)

      expect(guardian.guardian_of_active_ward?).to be false
      expect(guardian.needs_guardian?).to be true
    end

    it "still exempts an adult with a known date of birth" do
      expect(create(:user, birthday: adult_dob).needs_guardian?).to be false
    end

    it "still requires a guardian for a teen who has none" do
      expect(create(:user, birthday: teen_dob).needs_guardian?).to be true
    end
  end
end
