# frozen_string_literal: true

require "rails_helper"

# Fuime: the one path to `adult_18_plus`.
#
# The order matters and is the reason this is a class rather than two copies of
# four lines: the 18+ attestation must be written before #activation_blockers
# is read (it is the blocker being cleared), and through the association rather
# than a second instance of the same user (attest_adult_18_plus! uses
# update_columns, so a sibling object would hold a stale value).
RSpec.describe Fuime::GuardianConsentService do
  let(:guardian) { create(:user, :attested_teen, full_name: "Pat Consent") }
  let(:minor) { create(:user, :attested_teen, full_name: "Maya Consent") }
  let(:guardianship) { create(:guardianship, guardian:, minor:) }

  it "makes the guardian an adult and activates the guardianship" do
    result = described_class.new(guardianship:, ip: "10.0.0.1", user_agent: "rspec").call

    expect(result).to be_ok
    expect(guardian.reload).to be_attested_adult_18_plus
    expect(guardian).to be_known_adult
    expect(guardianship.reload).to be_active
    expect(guardianship.agreement_ip).to eq("10.0.0.1")
    expect(guardianship.agreement_user_agent).to eq("rspec")
  end

  # The ordering bug this class exists to make impossible: if the blockers were
  # read before the attestation, or from a different instance of the guardian,
  # the 18+ blocker would fire on the very request that cleared it.
  it "reads the blockers after attesting, so the 18+ blocker cannot fire on itself" do
    expect(guardianship.activation_blockers).to be_any

    expect(described_class.new(guardianship:).call).to be_ok
  end

  it "reports a remaining blocker without activating" do
    allow(guardianship).to receive(:activation_blockers).and_return(["something is wrong"])

    result = described_class.new(guardianship:).call

    expect(result).not_to be_ok
    expect(result.error).to eq("something is wrong")
    expect(guardianship.reload).not_to be_active
  end

  it "is a no-op on an already-active guardianship" do
    described_class.new(guardianship:).call
    signed_at = guardianship.reload.agreement_signed_at

    expect(described_class.new(guardianship:).call).to be_ok
    expect(guardianship.reload.agreement_signed_at).to eq(signed_at)
  end

  it "passes notify_minor through to accept!" do
    expect {
      described_class.new(guardianship:, notify_minor: false).call
    }.not_to have_enqueued_mail(GuardianshipMailer, :accepted)
  end
end
