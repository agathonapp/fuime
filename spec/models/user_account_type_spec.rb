# frozen_string_literal: true

require "rails_helper"

# Fuime: #account_type is what the admin user page reads to answer "is this a
# parent or a kid?", so the classification is pinned here rather than left to
# whatever the view happens to infer.
RSpec.describe User, type: :model do
  describe "#account_type" do
    it "is :teen for a minor with no guardian" do
      user = create(:user, birthday: 15.years.ago.to_date)

      expect(user.account_type).to eq(:teen)
      expect(user.account_type_label).to eq("Teen")
    end

    it "is :teen for a minor who does have an active guardian" do
      guardianship = create(:guardianship, :active)

      expect(guardianship.minor.account_type).to eq(:teen)
    end

    it "is :adult for a confirmed adult with no wards" do
      user = create(:user, birthday: 40.years.ago.to_date)

      expect(user.account_type).to eq(:adult)
      expect(user.account_type_label).to eq("Adult")
    end

    it "is :guardian for an adult who actively signs for a teen" do
      guardianship = create(:guardianship, :active)

      expect(guardianship.guardian.account_type).to eq(:guardian)
      expect(guardianship.guardian.account_type_label).to eq("Parent / guardian")
    end

    it "is not :guardian while the guardianship is only pending" do
      guardianship = create(:guardianship)

      expect(guardianship.guardian.account_type).to eq(:adult)
    end

    it "is not :guardian once the guardianship is revoked" do
      guardianship = create(:guardianship, :revoked)

      expect(guardianship.guardian.account_type).to eq(:adult)
    end

    # Fail closed: guessing "adult" on missing data is the guess that skips the
    # guardian requirement entirely.
    it "is :teen when no date of birth is on file" do
      user = create(:user, :unknown_age)

      expect(user.account_type).to eq(:teen)
    end

    # Ordering matters: :guardian is checked before :teen, so an adult with an
    # unrecorded birthday who signs for a teen still reads as a guardian rather
    # than being misfiled as a kid on the admin page.
    it "prefers :guardian over :teen when the guardian's own age is unknown" do
      minor = create(:user, :minor)
      guardian = create(:user, :unknown_age)
      create(:guardianship, minor:, guardian:).update!(status: :active)

      expect(guardian.reload.account_type).to eq(:guardian)
    end
  end

  describe "#primary_guardianship" do
    it "is nil when the user has never invited anyone" do
      expect(create(:user, birthday: 15.years.ago.to_date).primary_guardianship).to be_nil
    end

    it "returns the pending invite when there is no active one" do
      guardianship = create(:guardianship)

      expect(guardianship.minor.primary_guardianship).to eq(guardianship)
    end

    it "prefers the active guardianship over a pending one" do
      minor = create(:user, birthday: 15.years.ago.to_date)
      create(:guardianship, minor:, guardian: create(:user, birthday: 40.years.ago.to_date))
      active = create(:guardianship, :active, minor:, guardian: create(:user, birthday: 41.years.ago.to_date))

      expect(minor.primary_guardianship).to eq(active)
    end
  end
end
