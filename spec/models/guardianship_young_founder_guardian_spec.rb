# frozen_string_literal: true

require "rails_helper"

# Fuime: a young founder cannot stand as another young founder's guardian.
#
# ── The hole this file exists for ──────────────────────────────────────────
#
# Every guardian age check asked `guardian.is_minor?`, which reads a birthday.
# Signup stopped asking for a birthday on 2026-08-20 — it asks for a "13 or
# older" tick — so `is_minor?` is nil for every account created since, and the
# check was true only of a population that no longer exists.
#
# What that left: teen A invites classmate B as their guardian. B ticks the 18+
# box, which calls `attest_adult_18_plus!` and overwrites B's own
# minor_13_plus attestation. B is now a known adult, so `User#needs_guardian?`
# is false for B's OWN venture as well, and A has cleared the L2 gate that
# decides who Fuime may pay. Two founders at the same cohort event can do this to
# each other in about a minute, and Fuime would then be paying a minor who is
# standing as the legal payee and the clawback obligor.
#
# `self_signed_signals` cannot see it: that looks for one person with two
# inboxes, and this is two real people with two real inboxes.
#
# The check cannot be about age, because Fuime does not know anyone's age. It is
# about what the account has already told Fuime it is by using the product.
RSpec.describe Guardianship, "a young founder as guardian" do
  let(:teen) { create(:user, :minor) }

  # An account that has told Fuime it is a young founder: 13+ at signup, and it
  # runs a venture.
  let(:other_founder) do
    create(:user, :minor).tap do |u|
      u.update_column(:age_attestation, User.age_attestations[:minor_13_plus])
      create(:organizer_position, event: create(:event), user: u)
    end
  end

  it "refuses the invitation rather than creating it" do
    guardianship = described_class.new(minor: teen, guardian: other_founder)

    expect(guardianship).not_to be_valid
    expect(guardianship.errors.full_messages.join)
      .to match(/signed up as a young founder/i)
  end

  it "refuses an account that is itself somebody's ward, even with no venture" do
    ward = create(:user, :minor).tap do |u|
      u.update_column(:age_attestation, User.age_attestations[:minor_13_plus])
      create(:guardianship, :active, minor: u, guardian: create(:user, birthday: 40.years.ago.to_date))
    end

    expect(described_class.new(minor: teen, guardian: ward)).not_to be_valid
  end

  it "will not present the accept form for one that already exists" do
    guardianship = build(:guardianship, minor: teen, guardian: other_founder)
    guardianship.save!(validate: false)

    expect(guardianship.structural_activation_blockers)
      .to include(described_class::YOUNG_FOUNDER_AS_GUARDIAN)
    expect(guardianship.can_present_accept_form?).to be(false)
  end

  it "refuses the auto-invite from an application's cosigner email too" do
    expect {
      Fuime::GuardianInviteService.new(minor: teen, guardian_email: other_founder.email).run!
    }.to raise_error(Fuime::GuardianInviteService::InvalidInvite, /young founder/i)
  end

  # ── The half that must keep working ───────────────────────────────────────
  #
  # A parent who created an account before being invited ticked the same 13+ box
  # at signup (it is the only attestation signup offers). They are not a young
  # founder: no venture, no application of their own, nobody has named them a
  # minor. Refusing them would break the ordinary parent path, which is the
  # whole product.
  it "still allows a parent whose account only ever ticked 13+ at signup" do
    parent = create(:user).tap do |u|
      u.update_column(:age_attestation, User.age_attestations[:minor_13_plus])
      u.update_column(:birthday, nil)
    end

    guardianship = described_class.new(minor: teen, guardian: parent)

    expect(guardianship).to be_valid
    expect(guardianship.structural_activation_blockers).to be_empty
  end

  it "still allows a guardian who has confirmed they are 18 or older" do
    adult = create(:user, birthday: 40.years.ago.to_date).tap do |u|
      u.update_column(:age_attestation, User.age_attestations[:adult_18_plus])
    end

    expect(described_class.new(minor: teen, guardian: adult)).to be_valid
  end
end
