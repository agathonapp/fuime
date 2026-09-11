# frozen_string_literal: true

require "rails_helper"

# Fuime: the email _selling_blockers.html.erb has promised since vetting shipped
# ("We'll email you when yours is approved") and nothing sent. Same
# deliverability bar as the guardian invite — Reply-To, multipart, the URL
# pasteable from the text part — because a teenager reading this on a phone is
# the whole audience.
RSpec.describe Fuime::VettingMailer, type: :mailer do
  # Pinned rather than Faker'd: the subject and the URL are matched verbatim.
  # `business_category` so the merchant-of-record example below is about
  # vetting and not about the launch scope.
  let(:event) { create(:event, name: "Maya Design Studio", slug: "maya-design", business_category: "services") }

  # 17 rather than 16 so the age-floor example is not sitting on its own boundary.
  let(:founder) { create(:user, :minor, birthday: 17.years.ago.to_date, email: "maya-founder@example.com", full_name: "Maya Founder") }
  let(:co_founder) { create(:user, email: "sam-cofounder@example.com") }
  let(:helper) { create(:user, email: "helper-member@example.com") }
  let(:former_manager) { create(:user, email: "former-manager@example.com") }

  before do
    create(:organizer_position, event:, user: founder, role: :manager)
    create(:organizer_position, event:, user: co_founder, role: :manager)
    create(:organizer_position, event:, user: helper, role: :member)
    # acts_as_paranoid: a removed manager keeps their row with `deleted_at` set.
    create(:organizer_position, event:, user: former_manager, role: :manager).destroy
  end

  describe "#approved" do
    subject(:mail) { described_class.approved(event:) }

    it "goes to every current manager and to nobody else" do
      expect(mail.to).to contain_exactly("maya-founder@example.com", "sam-cofounder@example.com")
      expect(mail.to).not_to include("helper-member@example.com", "former-manager@example.com")
    end

    it "has a Reply-To people can actually answer" do
      expect(mail.reply_to).to eq([ApplicationMailer::OPERATIONS_EMAIL])
      expect(mail.from).to be_present
    end

    it "names the venture in the subject and points at publishing" do
      expect(mail.subject).to eq("Maya Design Studio is approved — publish your first offer")
    end

    it "is multipart with the offers URL in both parts" do
      offers_url = fuime_offers_url(event_slug: "maya-design")

      expect(mail.multipart?).to be true
      expect(mail.text_part.content_type).to include("text/plain")
      expect(mail.html_part.content_type).to include("text/html")

      text = mail.text_part.body.to_s
      html = mail.html_part.body.to_s

      expect(text).to include(offers_url)
      expect(text).to include("Maya Design Studio")
      expect(html).to include(offers_url)
      expect(html).to include("Publish your first offer")
    end

    it "says the pay link appears after publishing, in both parts" do
      expect(mail.text_part.body.to_s).to include("pay link appears on that page as soon as an offer is published")
      expect(mail.html_part.body.to_s).to include("pay link appears on that page as soon as an offer is published")
    end

    # Vetting is one gate of several. Fuime::Offer refuses to publish for a
    # venture that cannot take payments, so the sentence "you can publish now" is
    # only allowed when that is true (L8). Under Connect — the untagged default —
    # this venture has no connected account, so it cannot.
    it "does not claim they can publish when something else still blocks selling" do
      expect(event.accepts_payments?).to be(false)

      expect(mail.text_part.body.to_s).not_to include("You can publish your first offer now")
      expect(mail.text_part.body.to_s).to include("still needs sorting before you can publish")
    end

    it "says they can publish now when nothing else stands in the way", :merchant_of_record do
      expect(event.reload.accepts_payments?).to be(true)

      expect(mail.text_part.body.to_s).to include("You can publish your first offer now")
      expect(mail.html_part.body.to_s).to include("You can publish your first offer now")
      expect(mail.text_part.body.to_s).not_to include("still needs sorting")
    end

    # L5: none of the words a company without a partner bank may not use.
    it "stays inside the permitted vocabulary" do
      body = mail.text_part.body.to_s + mail.html_part.body.to_s

      expect(body).not_to match(/\b(bank|banking|checking|savings|deposits?|insured|FDIC)\b/i)
    end

    it "sends nothing when the venture has no managers" do
      event.organizer_positions.each(&:destroy)

      expect(mail.to).to be_blank
    end
  end

  # The other half of the split in Event#record_vetting_decision!: a venture
  # coming back from a suspension was already trading, and its offers stayed
  # published while the Buy button was withheld, so it must not be told to
  # "publish your first offer".
  describe "#reinstated" do
    subject(:mail) { described_class.reinstated(event:) }

    it "goes to the same managers with the same Reply-To" do
      expect(mail.to).to contain_exactly("maya-founder@example.com", "sam-cofounder@example.com")
      expect(mail.reply_to).to eq([ApplicationMailer::OPERATIONS_EMAIL])
    end

    it "says the venture may sell again, not that it should publish a first offer" do
      expect(mail.subject).to eq("Maya Design Studio is approved to sell again")
      expect(mail.subject).not_to include("first offer")

      [mail.text_part.body.to_s, mail.html_part.body.to_s].each do |body|
        expect(body).to include("lifted the suspension on Maya Design Studio")
        expect(body).not_to include("first offer")
      end
    end

    it "is multipart with the offers URL in both parts" do
      offers_url = fuime_offers_url(event_slug: "maya-design")

      expect(mail.multipart?).to be true
      expect(mail.text_part.body.to_s).to include(offers_url)
      expect(mail.html_part.body.to_s).to include(offers_url)
      expect(mail.html_part.body.to_s).to include("Go to what you sell")
    end

    context "when the venture can sell and has published offers", :merchant_of_record do
      # Published while approved (the factory default), the way a real venture's
      # offers were before an admin suspended it. Nothing unpublishes them.
      before do
        create(:fuime_offer, :published, event:)
        event.update!(operator_vetting_status: :suspended)
        event.update!(operator_vetting_status: :approved)
      end

      it "says the published offers are back on sale, in both parts" do
        expect(event.reload.accepts_payments?).to be(true)
        expect(event.fuime_offers.published).to exist

        [mail.text_part.body.to_s, mail.html_part.body.to_s].each do |body|
          expect(body).to include("Your published offers are back on sale")
          expect(body).not_to include("You can publish an offer now")
          expect(body).not_to include("still needs sorting")
        end
      end
    end

    context "when the venture can sell but never published anything", :merchant_of_record do
      it "says they can publish an offer now" do
        expect(event.reload.accepts_payments?).to be(true)

        [mail.text_part.body.to_s, mail.html_part.body.to_s].each do |body|
          expect(body).to include("You can publish an offer now")
          expect(body).not_to include("back on sale")
        end
      end
    end

    # Under Connect — the untagged default — this venture has no ready connected
    # account, so approval alone does not make it able to sell (L8).
    it "does not claim anything is on sale when something else still blocks selling" do
      create(:fuime_offer, event:)
      expect(event.accepts_payments?).to be(false)

      [mail.text_part.body.to_s, mail.html_part.body.to_s].each do |body|
        expect(body).to include("still needs sorting before you can sell")
        expect(body).not_to include("back on sale")
        expect(body).not_to include("You can publish an offer now")
      end
    end

    it "stays inside the permitted vocabulary" do
      body = mail.text_part.body.to_s + mail.html_part.body.to_s

      expect(body).not_to match(/\b(bank|banking|checking|savings|deposits?|insured|FDIC)\b/i)
    end

    it "sends nothing when the venture has no managers" do
      event.organizer_positions.each(&:destroy)

      expect(mail.to).to be_blank
    end
  end
end
