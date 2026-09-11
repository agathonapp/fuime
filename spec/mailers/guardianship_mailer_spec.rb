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

    # ONBOARDING_PLAN §4.2: the subject says why now. It still must not be the
    # urgent "sign their account" phrasing this spec was written against.
    it "uses a subject that says why now, not an urgent 'sign their account'" do
      expect(mail.subject).to eq("Maya Family started a business — they need a parent to sign off")
      expect(mail.subject).not_to match(/needs you|sign their (fuime )?account/i)
    end

    it "is multipart with a plain-text part and the accept URL in both parts" do
      accept_url = guardianship_url(guardianship.invite_token)

      expect(mail.text_part).to be_present
      expect(mail.html_part).to be_present

      text = mail.text_part.body.to_s
      html = mail.html_part.body.to_s

      expect(text).to include(accept_url)
      expect(text).to include("Maya Family")
      expect(html).to include(accept_url)
      expect(html).to include("Review and sign")
    end

    it "does not ship an HTML-only body" do
      expect(mail.multipart?).to be true
      expect(mail.text_part.content_type).to include("text/plain")
      expect(mail.html_part.content_type).to include("text/html")
    end

    # The pitch, in both parts. "Nothing happens unless you accept" is the one
    # line that survived the rewrite verbatim; it is what makes an unexpected
    # email safe to ignore.
    it "makes the case and says nothing happens unless they accept" do
      [mail.text_part.body.to_s, mail.html_part.body.to_s].each do |body|
        expect(body).to include("What you're agreeing to")
        expect(body).to include("legal signer")
        expect(body).to include("can't turn that off")
        expect(body).to include("nothing happens unless you accept")
      end
    end

    # Neither mailer exists (ONBOARDING_PLAN §2 #8), so the email must not
    # promise them (L8).
    it "promises no notifications or tax summary the product does not send" do
      [mail.text_part.body.to_s, mail.html_part.body.to_s].each do |body|
        expect(body).not_to match(/important notifications/i)
        expect(body).not_to match(/tax/i)
      end
    end

    # The venture is read from what the teen already has — no new column. The
    # invite usually fires on application submit, before any Event exists, so
    # the application's name is the common case.
    it "names the venture from the teen's application when there is one" do
      create(:event_application, user: teen, teen_led: true, name: "Sunset Cookies")

      expect(mail.subject).to include("started a business")
      expect(mail.text_part.body.to_s).to include("Sunset Cookies")
      expect(mail.html_part.body.to_s).to include("Sunset Cookies")
    end

    it "prefers the venture once one exists" do
      create(:event_application, user: teen, teen_led: true, name: "Old Application Name")
      create(:organizer_position, user: teen, event: create(:event, name: "Sunset Cookies LLC"))

      expect(mail.text_part.body.to_s).to include("Sunset Cookies LLC")
      expect(mail.text_part.body.to_s).not_to include("Old Application Name")
    end

    it "says 'a business' when the teen has not named one" do
      expect(mail.text_part.body.to_s).to include("just set up a business on Fuime")
      expect(mail.html_part.body.to_s).to include("a business")
    end

    # Under merchant-of-record the signature gates PAYOUTS: the teen can sell
    # first (Event#payout_setup_blockers). Accepting is a checkbox
    # (GuardianshipsController#accept) and the payout destination is collected
    # later, so the no-SSN / no-ID / no-payment line is true here.
    context "under merchant-of-record", :merchant_of_record do
      # Two things it must NOT claim, both false under MoR: that the parent
      # approves every payout (payouts run as a weekly Fuime::PayoutBatch a Fuime
      # admin approves; the parent gates whether money can go out at all, via
      # Event#payout_setup_blockers), and that the teen can already sell (selling
      # waits on Fuime's vetting, Fuime::OperatorEligibility, and this email
      # usually fires on application submit, before that decision).
      it "says they can't be paid until the parent signs, and asks for no SSN, ID or payment" do
        [mail.text_part.body.to_s, mail.html_part.body.to_s].each do |body|
          expect(body).to include("They can't be paid until you sign.")
          expect(body).to include("can keep going without waiting on you")
          expect(body).to include("Nothing is paid out until you've accepted and set up where the money goes.")
          expect(body).to include("We won't ask for a Social Security number, an ID, or a payment.")
          expect(body).not_to include("until you approve")
          expect(body).not_to include("take orders")
          expect(body).not_to include("can sell")
          expect(body).not_to include("can't run it until you sign")
          expect(body).not_to include("Nothing goes live until you accept")
        end
      end
    end

    # Under Connect the signature gates ACTIVATION
    # (Event::Application#activation_blockers), and Stripe's onboarding does
    # ask the account owner for identity details (L3) — so the no-SSN sentence
    # would be false and must not appear.
    context "under Connect (flag off)" do
      it "says they can't run it until the parent signs, and does not promise no SSN" do
        [mail.text_part.body.to_s, mail.html_part.body.to_s].each do |body|
          expect(body).to include("can't run it until you sign")
          expect(body).to include("Nothing goes live until you accept.")
          expect(body).not_to include("Social Security number")
          expect(body).not_to include("can't be paid until you sign")
        end
      end
    end
  end

  describe "#invite_reminder" do
    subject(:mail) { described_class.invite_reminder(guardianship:, stage: :day3) }

    it "reuses the existing accept token and is multipart" do
      accept_url = guardianship_url(guardianship.invite_token)

      expect(mail.to).to eq([guardian.email])
      expect(mail.reply_to).to eq([ApplicationMailer::OPERATIONS_EMAIL])
      expect(mail.subject).to eq("Reminder: Maya Family is still waiting for you on Fuime")
      expect(mail.text_part.body.to_s).to include(accept_url)
      expect(mail.html_part.body.to_s).to include(accept_url)
      expect(mail.text_part.body.to_s).to include("cannot get paid")
    end

    it "marks the day-6 mail as the last reminder before expiry" do
      mail = described_class.invite_reminder(guardianship:, stage: :day6)

      expect(mail.subject).to match(/Last reminder: Maya Family's Fuime invite expires/i)
      expect(mail.text_part.body.to_s).to include("expires")
    end

    # The reminder carries the same pitch as the first email, framed as a nudge.
    it "carries the pitch and the venture name" do
      create(:event_application, user: teen, teen_led: true, name: "Sunset Cookies")

      [mail.text_part.body.to_s, mail.html_part.body.to_s].each do |body|
        expect(body).to include("Sunset Cookies")
        expect(body).to include("What you're agreeing to")
        expect(body).to include("Review and sign")
        expect(body).not_to match(/important notifications/i)
      end
    end

    # Not "they can sell but they cannot get paid": selling under MoR waits on
    # Fuime's vetting, which may not have happened by day 3 or day 6.
    it "says they cannot get paid until the parent accepts, without claiming they can sell, under merchant-of-record", :merchant_of_record do
      [mail.text_part.body.to_s, mail.html_part.body.to_s].each do |body|
        expect(body).to include("Until you accept, they cannot get paid.")
        expect(body).to include("Nothing is paid out until you've accepted and set up where the money goes.")
        expect(body).not_to include("they can sell")
        expect(body).not_to include("until you approve")
      end
    end

    it "does not claim they can sell under Connect" do
      [mail.text_part.body.to_s, mail.html_part.body.to_s].each do |body|
        expect(body).not_to include("they can sell")
        expect(body).to include("cannot go live and they cannot get paid")
      end
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

    # What acceptance unblocks differs by money model (L8). Under
    # merchant-of-record it clears the guardian half of
    # Event#payout_setup_blockers — activation is Fuime's vetting, not this — so
    # "your venture can now be fully activated" would be false.
    it "tells the teen the parent step for getting paid is done, under merchant-of-record", :merchant_of_record do
      [mail.text_part.body.to_s, mail.html_part.body.to_s].each do |body|
        expect(body).to include("That clears the parent-or-guardian step for getting paid.")
        expect(body).to include("Pat Family sets up where the money goes")
        expect(body).not_to include("fully activated")
      end
    end

    it "keeps the activation framing under Connect" do
      [mail.text_part.body.to_s, mail.html_part.body.to_s].each do |body|
        expect(body).to include("Your venture can now be fully activated.")
        expect(body).not_to include("parent-or-guardian step")
      end
    end
  end
end
