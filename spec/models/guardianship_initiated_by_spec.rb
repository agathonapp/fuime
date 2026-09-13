# frozen_string_literal: true

require "rails_helper"

# Fuime: who started a guardianship, and the two behaviours that turn on it.
#
# A parent-first row is created and accepted in the same request, which would
# otherwise (a) mail the teen "your parent accepted your invitation" when they
# never sent one, and (b) put every ordinary parent-first family on the payout
# reviewer's self-signed list.
RSpec.describe Guardianship, "#initiated_by" do
  let(:guardian) { create(:user, birthday: 40.years.ago.to_date, full_name: "Pat Init") }
  let(:minor) { create(:user, :attested_teen, full_name: "Maya Init") }

  it "defaults to the minor, which is what every existing row is" do
    expect(create(:guardianship, guardian:, minor:)).to be_initiated_by_minor
  end

  describe "#accept!" do
    it "still mails the teen by default" do
      guardianship = create(:guardianship, guardian:, minor:)

      expect {
        guardianship.accept!(consent_ip: "127.0.0.1", consent_user_agent: "rspec")
      }.to have_enqueued_mail(GuardianshipMailer, :accepted).once
    end

    it "does not when the guardian started it" do
      guardianship = create(:guardianship, guardian:, minor:, initiated_by: :guardian)

      expect {
        guardianship.accept!(consent_ip: "127.0.0.1", consent_user_agent: "rspec", notify_minor: false)
      }.not_to have_enqueued_mail(GuardianshipMailer, :accepted)

      expect(guardianship.reload).to be_active
      expect(guardianship.agreement_version).to eq(described_class::CURRENT_AGREEMENT_VERSION)
      expect(guardianship.agreement_ip).to eq("127.0.0.1")
    end
  end

  describe "#self_signed_signals" do
    # The signal exists to catch a teen accepting their own invite seconds
    # after sending it. A parent who set the family up did both in one request
    # on purpose, so reporting it would fire on every ordinary family and bury
    # the real ones.
    it "omits fast acceptance for a guardian-initiated row" do
      guardianship = create(:guardianship, guardian:, minor:, initiated_by: :guardian)
      guardianship.update!(invite_sent_at: Time.current)
      guardianship.accept!(consent_ip: "127.0.0.1", consent_user_agent: "rspec", notify_minor: false)

      expect(guardianship.self_signed_signals.join(" ")).not_to match(/after the invite was sent/)
    end

    it "still reports it for a minor-initiated row" do
      guardianship = create(:guardianship, guardian:, minor:)
      guardianship.update!(invite_sent_at: Time.current)
      guardianship.accept!(consent_ip: "127.0.0.1", consent_user_agent: "rspec")

      expect(guardianship.self_signed_signals.join(" ")).to match(/after the invite was sent/)
    end
  end
end
