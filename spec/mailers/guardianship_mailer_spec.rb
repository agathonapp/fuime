# frozen_string_literal: true

require "rails_helper"

# Fuime: the parent-invite email is the only way a guardian learns they have
# something to sign. Deliverability is mostly DNS/ESP (Resend + SPF/DKIM/DMARC
# on fuime.com — see docs/fuime/LAUNCH_SPEC.md §3.4), but the message itself
# used to look like a blast: no-reply From with no Reply-To, HTML-only, a
# subject that said the child "needs you to sign their account", and a button
# whose URL was not also in the body as text.
RSpec.describe GuardianshipMailer, type: :mailer do
  let(:teen) { create(:user, :minor, full_name: "Maya Family") }
  let(:guardian) { create(:user, :unknown_age, email: "pat-family@example.com") }
  let(:guardianship) { create(:guardianship, minor: teen, guardian:) }

  describe "#invite" do
    subject(:mail) { described_class.invite(guardianship:) }

    it "addresses the guardian with a Reply-To people can actually answer" do
      expect(mail.to).to eq([guardian.email])
      expect(mail.reply_to).to eq([ApplicationMailer::OPERATIONS_EMAIL])
      expect(mail.from).to be_present
    end

    it "uses a subject that names the invite, not an urgent 'sign their account'" do
      expect(mail.subject).to eq("Maya Family invited you to be their guardian on Fuime")
      expect(mail.subject).not_to match(/needs you|sign their (fuime )?account/i)
    end

    it "is multipart with a plain-text part and the accept URL in both parts" do
      accept_url = guardianship_url(guardianship.invite_token)

      expect(mail.mime_type).to eq("multipart/alternative")
      expect(mail.text_part).to be_present
      expect(mail.html_part).to be_present

      text = mail.text_part.body.to_s
      html = mail.html_part.body.to_s

      expect(text).to include(accept_url)
      expect(text).to include("Maya Family")
      expect(html).to include(accept_url)
      expect(html).to include("Review guardian invitation")
    end

    it "does not ship an HTML-only body" do
      expect(mail.body.parts.map(&:mime_type)).to include("text/plain", "text/html")
    end
  end

  describe "#accepted" do
    subject(:mail) { described_class.accepted(guardianship:) }

    before { guardian.update!(full_name: "Pat Family") }

    it "tells the teen, with a text part and a reply address" do
      expect(mail.to).to eq([teen.email])
      expect(mail.reply_to).to eq([ApplicationMailer::OPERATIONS_EMAIL])
      expect(mail.subject).to eq("Pat Family accepted your Fuime guardian invitation")
      expect(mail.text_part.body.to_s).to include("accepted your guardian invitation")
    end
  end
end
