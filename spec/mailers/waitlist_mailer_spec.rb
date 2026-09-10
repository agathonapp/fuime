# frozen_string_literal: true

require "rails_helper"

# Fuime G1: the "you're in" email. Same deliverability bar as the guardian
# invite — Reply-To, multipart, pasteable URL — because this is the message
# the marketing site has been promising.
RSpec.describe WaitlistMailer, type: :mailer do
  let(:user) { create(:user, email: "maya-waitlist@example.com", full_name: nil) }
  let(:token) { Fuime::WaitlistInviteService.generate_token(user:) }

  describe "#invite" do
    subject(:mail) { described_class.invite(user:, token:) }

    it "addresses the waitlist email with a Reply-To people can answer" do
      expect(mail.to).to eq([user.email])
      expect(mail.reply_to).to eq([ApplicationMailer::OPERATIONS_EMAIL])
      expect(mail.subject).to eq("You're in — log in to Fuime")
    end

    it "is multipart and puts the login URL in both parts" do
      login_url = waitlist_invite_url(token)

      expect(mail.multipart?).to be true
      expect(mail.text_part.body.to_s).to include(login_url)
      expect(mail.html_part.body.to_s).to include(login_url)
      expect(mail.html_part.body.to_s).to include("Log in to Fuime")
    end

    it "names the cohort when one was stamped" do
      cohort = Fuime::Cohort.create!(
        name: "Founders Weekend", code: "FOUNDERS26",
        created_by: create(:user, :make_admin),
        rationale: "I'm running this event and I know everyone attending.",
        expires_at: 3.days.from_now, max_members: 50, risk_level: "slight"
      )

      mail = described_class.invite(user:, token:, cohort:)

      expect(mail.text_part.body.to_s).to include("FOUNDERS26")
      expect(mail.text_part.body.to_s).to include("Founders Weekend")
    end
  end
end
