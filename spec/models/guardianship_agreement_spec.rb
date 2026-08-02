# frozen_string_literal: true

require "rails_helper"

# Fuime: a guardian must always be able to re-read the exact text they signed,
# so agreement versions resolve to their own on-disk partial. The version string
# comes out of the database and is interpolated into a path, so the allowlist
# that guards it is tested as a security control, not a nicety.
RSpec.describe Guardianship, type: :model do
  describe ".agreement_partial_for" do
    it "resolves the current version to its partial" do
      expect(described_class.agreement_partial_for(described_class::CURRENT_AGREEMENT_VERSION))
        .to eq("guardianships/agreements/2026_08_01_v1")
    end

    it "translates dashes in the version to underscores in the filename" do
      expect(described_class.agreement_partial_for("2026-08-01-v1"))
        .to eq("guardianships/agreements/2026_08_01_v1")
    end

    it "is nil for a version with no partial on disk" do
      expect(described_class.agreement_partial_for("1999-01-01-v9")).to be_nil
    end

    it "is nil for a blank version" do
      expect(described_class.agreement_partial_for(nil)).to be_nil
      expect(described_class.agreement_partial_for("")).to be_nil
    end

    # The allowlist must reject anything that could escape the agreements
    # directory, even though these strings should never reach the database.
    it "rejects path traversal and other unsafe version strings" do
      [
        "../../../../etc/passwd",
        "..%2f..%2fsecrets",
        "2026-08-01-v1/../../../config/database",
        "foo bar",
        "Foo-V1",          # uppercase is outside the allowlist
        "2026;rm -rf /",
      ].each do |unsafe|
        expect(described_class.agreement_partial_for(unsafe)).to be_nil,
                                                                 "expected #{unsafe.inspect} to be rejected"
      end
    end
  end

  # The revoked_by_id column and its foreign key shipped without a matching
  # association, so every `guardianship.revoked_by` in a view raised NoMethodError.
  describe "#revoked_by" do
    it "reads back the user who withdrew consent" do
      guardianship = create(:guardianship, :active)
      admin = create(:user, :make_admin, birthday: 35.years.ago.to_date)

      guardianship.revoke!(revoked_by: admin)

      expect(guardianship.reload.revoked_by).to eq(admin)
    end

    it "is nil when the revocation is not attributable to a user" do
      guardianship = create(:guardianship, :active)

      guardianship.revoke!

      expect(guardianship.reload.revoked_by).to be_nil
    end
  end

  describe "#agreement_partial" do
    it "renders the version that was actually signed, not today's terms" do
      guardianship = create(:guardianship, :active, agreement_version: "2026-08-01-v1")

      expect(guardianship.agreement_partial).to eq("guardianships/agreements/2026_08_01_v1")
    end

    it "falls back to the current version when unsigned" do
      guardianship = create(:guardianship)

      expect(guardianship.agreement_partial)
        .to eq(described_class.agreement_partial_for(described_class::CURRENT_AGREEMENT_VERSION))
    end

    it "is nil when the signed version's text is no longer on disk" do
      guardianship = create(:guardianship, :active)
      guardianship.update_column(:agreement_version, "2020-01-01-v0")

      expect(guardianship.reload.agreement_partial).to be_nil
    end
  end
end
