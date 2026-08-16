# frozen_string_literal: true

require "rails_helper"

# Fuime: the hosted payment page — the link a teenager pastes into a Replit site.
#
# Public, unauthenticated, and reached cold by strangers, so it gets the same
# scrutiny as the checkout endpoint: what it shows, what it refuses, and what it
# refuses to say about *why* it refused.
RSpec.describe "the hosted payment page", type: :request do
  let(:event) { create(:event, is_public: true, name: "Sunset Lawn Care") }
  let(:offer) do
    create(:fuime_offer, event:, name: "Front and back lawn mow",
                         description: "Includes edging.", unit_label: "per visit",
                         price_cents: 35_00)
  end

  def visit!(identifier = offer.to_param, venture: event.slug)
    get "/pay/#{venture}/#{identifier}"
  end

  describe "a published offer on a public venture" do
    before do
      allow_any_instance_of(Event).to receive(:accepts_payments?).and_return(true)
      offer.publish!
    end

    it "answers the four questions a stranger has" do
      visit!

      body = CGI.unescapeHTML(response.body)
      expect(response).to have_http_status(:ok)
      expect(body).to include("Sunset Lawn Care")            # from whom
      expect(body).to include("Front and back lawn mow")     # what
      expect(body).to include("$35.00 per visit")            # how much
      expect(body).to include("Stripe")                      # who takes the card
    end

    # L5. This page is seen by more strangers than any authenticated page, so the
    # standing disclosure matters here most.
    it "carries the standing disclosure" do
      visit!

      body = CGI.unescapeHTML(response.body)
      expect(body).to match(/not a bank/i)
      # The copy line-wraps in the template, so the whitespace is flexible.
      expect(body).to match(/does not take\s+deposits/i)
    end

    # The storefront reasons at length about a minor's name beside a price being
    # a targeting profile. This page shows strictly less.
    it "says nothing about who runs the business" do
      teen = create(:user, birthday: 16.years.ago.to_date)
      create(:organizer_position, event:, user: teen)

      visit!

      body = CGI.unescapeHTML(response.body)
      expect(body).not_to include(teen.email)
      expect(body).not_to include(teen.name.to_s) if teen.name.present?
      event.selling_blockers.each { |blocker| expect(body).not_to include(blocker) }
    end

    # The primary key never appears in public HTML — a sequential id is the one
    # identifier somebody can walk to enumerate the catalogue.
    it "posts the operator's own identifier, never the id" do
      visit!

      expect(response.body).to include(%(value="#{offer.to_param}"))
      expect(offer.to_param).to eq("front-and-back-lawn-mow"),
                                "the link should read as the thing, not as a random string"
      expect(response.body).not_to match(/offer_token"[^>]*value="#{offer.id}"/)
    end

    # The permanent identifier still resolves, so a link already printed on a
    # flyer survives the operator tidying up the slug afterwards.
    it "still answers on the permanent token after a rename" do
      original = offer.public_token
      offer.update!(slug: "renamed-later")

      visit!(original)

      expect(response).to have_http_status(:ok)
      expect(CGI.unescapeHTML(response.body)).to include("Front and back lawn mow")
    end

    it "refuses a slug that belongs to another business" do
      other_event = create(:event, is_public: true)
      other = create(:fuime_offer, event: other_event, name: "Front and back lawn mow")
      allow_any_instance_of(Event).to receive(:accepts_payments?).and_return(true)
      other.publish!

      # Same slug text, different venture — the venture segment is the namespace.
      visit!(other.to_param, venture: other_event.slug)
      expect(response).to have_http_status(:ok)

      expect(other.to_param).to eq(offer.to_param),
                                "two businesses may both sell the same thing under the same slug"
    end

    it "posts the token, so the price cannot be rewritten in a browser" do
      visit!

      body = response.body
      expect(body).to include(%(name="offer_token"))
      expect(body).not_to include(%(name="amount"))
    end
  end

  describe "links that should not work" do
    # A stale link must not still be able to buy something the operator took down.
    it "404s a draft" do
      visit!

      expect(response).to have_http_status(:not_found)
    end

    it "404s an archived offer" do
      allow_any_instance_of(Event).to receive(:accepts_payments?).and_return(true)
      offer.publish!
      offer.archive!

      visit!

      expect(response).to have_http_status(:not_found)
    end

    # A payment page is a public page, so a venture that has withdrawn its
    # storefront has withdrawn its links too.
    it "404s when the venture is no longer public" do
      allow_any_instance_of(Event).to receive(:accepts_payments?).and_return(true)
      offer.publish!
      # `update_columns` to skip the Event callback that reaches for the system
      # user — this example is about the lookup, not about that machinery.
      event.update_columns(is_public: false)

      visit!

      expect(response).to have_http_status(:not_found)
    end

    it "404s a token that never existed" do
      visit!("nosuchtoken1")

      expect(response).to have_http_status(:not_found)
    end

    # Every wrong guess has to look the same. A redirect with "that isn't for
    # sale" tells whoever is probing that the token space is worth probing, and
    # an operator who took an offer down gets a page that does not announce it
    # used to be for sale.
    it "says the same thing whether the token never existed or was withdrawn" do
      visit!("nosuchtoken1")
      never_existed = CGI.unescapeHTML(response.body)

      visit!
      withdrawn = CGI.unescapeHTML(response.body)

      expect(withdrawn).to eq(never_existed)
    end
  end

  describe "a venture that has stopped being able to sell" do
    before do
      allow_any_instance_of(Event).to receive(:accepts_payments?).and_return(true)
      offer.publish!
      allow_any_instance_of(Event).to receive(:accepts_payments?).and_return(false)
    end

    # A dead Pay button on a link already sent to a real customer is worse than
    # an honest message.
    it "says so rather than showing a button that cannot work" do
      visit!

      body = CGI.unescapeHTML(response.body)
      expect(response).to have_http_status(:ok)
      expect(body).to include("isn't able to take payments right now")
      expect(body).not_to include(%(name="offer_token"))
    end

    # …but not WHY. Event#selling_blockers names operators and states their ages.
    it "does not say why" do
      teen = create(:user, birthday: 16.years.ago.to_date)
      create(:organizer_position, event:, user: teen)

      visit!

      body = CGI.unescapeHTML(response.body)
      event.selling_blockers.each { |blocker| expect(body).not_to include(blocker) }
    end
  end
end
