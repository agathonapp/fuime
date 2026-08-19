# frozen_string_literal: true

require "rails_helper"

# Fuime: the API a venture's own software — including an AI agent — sells through.
#
# Held to the same standard as Fuime::CheckoutsController, because it is the same
# thing: a request from outside that ends with a stranger being asked for money in
# a child's name. The caller here is if anything less trustworthy than a browser
# — it is frequently a language model choosing a number, and the key it presents
# has usually been pasted somewhere the teenager does not control.
#
# So the questions are: does the key bound the blast radius to one venture, does
# the eligibility gate get re-asked at request time, and does a wrong number get
# refused rather than rounded into something plausible.
RSpec.describe "the payment links API", :merchant_of_record, type: :request do
  let(:teen) { create(:user, :minor, birthday: 16.years.ago.to_date) }

  let(:event) do
    create(:event, business_category: "services", is_public: true, name: "Sunset Lawn Care").tap do |e|
      e.update!(operator_vetting_status: :approved, operator_vetted_at: Time.current)
      create(:organizer_position, event: e, user: teen, role: :manager)
    end
  end

  let(:plaintext) { Fuime::ApiKey.mint!(event:, created_by: teen, name: "Website")[1] }

  def auth(key = plaintext)
    { "Authorization" => "Bearer #{key}" }
  end

  def post_link(body, key: plaintext)
    post "/api/fuime/v1/payment_links", params: body.to_json,
                                        headers: auth(key).merge("Content-Type" => "application/json")
  end

  def json = JSON.parse(response.body)

  describe "authentication" do
    it "refuses a request with no key" do
      post "/api/fuime/v1/payment_links", params: {}

      expect(response).to have_http_status(:unauthorized)
    end

    it "refuses an unknown key" do
      post_link({ amount: "35.00", name: "Mow" }, key: "fuime_sk_nope")

      expect(response).to have_http_status(:unauthorized)
    end

    it "refuses a revoked key" do
      key, plain = Fuime::ApiKey.mint!(event:, created_by: teen, name: "Old")
      key.revoke!

      post_link({ amount: "35.00", name: "Mow" }, key: plain)

      expect(response).to have_http_status(:unauthorized)
    end

    # Every failure returns the same body. Distinguishing "unknown" from
    # "revoked" tells somebody working through the key space when they have
    # found a real one — see Fuime::ApiKey.authenticate.
    it "says the same thing however it failed" do
      post_link({ amount: "35.00", name: "Mow" }, key: "fuime_sk_nope")
      unknown = json

      key, plain = Fuime::ApiKey.mint!(event:, created_by: teen, name: "Old")
      key.revoke!
      post_link({ amount: "35.00", name: "Mow" }, key: plain)

      expect(json).to eq(unknown)
    end

    it "accepts the key without the Bearer prefix" do
      post "/api/fuime/v1/payment_links",
           params: { amount: "35.00", name: "Mow" }.to_json,
           headers: { "Authorization" => plaintext, "Content-Type" => "application/json" }

      expect(response).to have_http_status(:created)
    end
  end

  describe "creating a link" do
    it "returns a payable URL for the amount asked for" do
      post_link({ amount: "35.00", name: "Lawn mow" })

      expect(response).to have_http_status(:created)
      expect(json["amount_cents"]).to eq(3500)
      expect(json["status"]).to eq("published")
      expect(json["url"]).to include("/pay/#{event.slug}/")
    end

    it "accepts cents, and prefers them when both are sent" do
      post_link({ amount: "1.00", amount_cents: 4500, name: "Mow" })

      expect(json["amount_cents"]).to eq(4500)
    end

    it "accepts a currency symbol, because a model writing JSON includes one" do
      post_link({ amount: "$45.00", name: "Mow" })

      expect(json["amount_cents"]).to eq(4500)
    end

    # The link is real: it renders, and it renders the price off the record.
    it "produces a link a stranger can actually pay" do
      post_link({ amount: "35.00", name: "Lawn mow" })
      get URI.parse(json["url"]).path

      expect(response).to have_http_status(:ok)
      expect(CGI.unescapeHTML(response.body)).to include("$35.00")
    end

    # The whole reason `listed` exists. A price agreed with one customer is not
    # a shop listing — see AddListingToFuimeOffers.
    it "keeps the link off the public storefront" do
      post_link({ amount: "35.00", name: "Private quote for Dana" })
      get "/b/#{event.slug}"

      expect(response.body).not_to include("Private quote for Dana")
    end
  end

  describe "refusing a number nobody meant" do
    # The failure mode this exists for: a model misplacing a decimal point and a
    # teenager's customer being asked for $450,000. Refused, not clamped —
    # silently charging $10,000 when the caller said $450,000 is its own bug.
    it "refuses an amount over the maximum rather than clamping it" do
      post_link({ amount: "450000", name: "Mow" })

      expect(response).to have_http_status(:unprocessable_entity)
      expect(json["error"]).to eq("invalid_amount")
      expect(Fuime::Offer.count).to eq(0)
    end

    it "refuses an amount below a dollar" do
      post_link({ amount: "0.50", name: "Mow" })

      expect(response).to have_http_status(:unprocessable_entity)
    end

    # `to_i` would read this as 0, and a coerced zero is a link that charges
    # nothing while reporting success.
    it "refuses words rather than reading them as zero" do
      post_link({ amount: "forty five", name: "Mow" })

      expect(response).to have_http_status(:unprocessable_entity)
      expect(Fuime::Offer.count).to eq(0)
    end

    it "refuses a negative amount" do
      post_link({ amount_cents: -4500, name: "Mow" })

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "refuses a request with no amount at all" do
      post_link({ name: "Mow" })

      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe "the eligibility gate" do
    # Re-asked at request time, not trusted from whenever the key was minted. A
    # venture suspended an hour ago must not still be issuing payable links
    # through a key nobody thought to revoke.
    it "refuses once the venture stops being allowed to sell" do
      plaintext # mint while still eligible
      event.update!(operator_vetting_status: :suspended)

      post_link({ amount: "35.00", name: "Mow" })

      expect(response).to have_http_status(:conflict)
      expect(json["error"]).to eq("not_accepting_payments")
    end

    # Event#selling_blockers names operators and states their ages. The caller
    # may be a program on a stranger's server; it gets the fact, not the reasons.
    it "does not tell the caller who or why" do
      plaintext
      event.update!(operator_vetting_status: :suspended)

      post_link({ amount: "35.00", name: "Mow" })

      expect(response.body).not_to include(teen.name)
    end
  end

  describe "the blast radius of a leaked key" do
    let(:other_event) do
      create(:event, business_category: "services", name: "Someone Else's Business").tap do |e|
        e.update!(operator_vetting_status: :approved, operator_vetted_at: Time.current)
      end
    end

    # There is no event parameter anywhere in this API, so this asserts the
    # property rather than a rejection: a caller cannot even express the request.
    it "acts only on the key's own venture, whatever the caller sends" do
      post_link({ amount: "35.00", name: "Mow", event_id: other_event.id,
                  event_slug: other_event.slug })

      expect(json["url"]).to include("/pay/#{event.slug}/")
      expect(other_event.fuime_offers).to be_empty
    end

    it "lists only the key's own venture's links" do
      create(:fuime_offer, event: other_event, name: "Not yours", listed: false,
                           created_via: "operator")
      post_link({ amount: "35.00", name: "Mine" })

      get "/api/fuime/v1/payment_links", headers: auth

      names = json["payment_links"].map { |l| l["name"] }
      expect(names).to include("Mine")
      expect(names).not_to include("Not yours")
    end

    it "cannot take down a link another key made" do
      other_key = Fuime::ApiKey.mint!(event:, created_by: teen, name: "Other")[0]
      theirs = Fuime::Offer.for_amount!(event:, price_cents: 1000, name: "Theirs",
                                        created_via: "api", api_key: other_key)

      delete "/api/fuime/v1/payment_links/#{theirs.public_token}", headers: auth

      expect(response).to have_http_status(:not_found)
      expect(theirs.reload).to be_published
    end
  end

  describe "taking a link down" do
    it "archives it so the URL stops taking money" do
      post_link({ amount: "35.00", name: "Mow" })
      token = json["id"]

      delete "/api/fuime/v1/payment_links/#{token}", headers: auth

      expect(response).to have_http_status(:ok)
      expect(Fuime::Offer.find_by(public_token: token)).to be_archived
    end

    it "leaves the buyer's page unable to charge afterwards" do
      post_link({ amount: "35.00", name: "Mow" })
      url = URI.parse(json["url"]).path
      delete "/api/fuime/v1/payment_links/#{json['id']}", headers: auth

      get url

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "GET /me" do
    it "says which venture the key speaks for" do
      get "/api/fuime/v1/me", headers: auth

      expect(response).to have_http_status(:ok)
      expect(json.dig("venture", "slug")).to eq(event.slug)
      expect(json.dig("venture", "can_sell")).to be(true)
      expect(json.dig("key", "display")).to match(/\Afuime_sk_••••/)
    end

    # So an agent can say "I can't take payments yet" in conversation rather than
    # generating a link that will fail.
    it "reports when the venture cannot sell" do
      plaintext
      event.update!(operator_vetting_status: :suspended)

      get "/api/fuime/v1/me", headers: auth

      expect(json.dig("venture", "can_sell")).to be(false)
    end

    it "never returns the key itself" do
      get "/api/fuime/v1/me", headers: auth

      expect(response.body).not_to include(plaintext)
    end
  end

end
