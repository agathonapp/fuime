# frozen_string_literal: true

require "rails_helper"

# Fuime: /discover is the public shop window of listed offers.
#
# Two things are under test. The ordinary half is that the right offers appear
# and the wrong ones do not. The other half is that this page stays a LISTING
# and never becomes a dispatch or a marketplace that needs a crowd — no ranking,
# no search, no social proof, and every card is `/b/:slug` with no query string
# so checkout can only read `offer.price_cents`.
#
# Unlisted published offers are private pay links. They must 404 here and keep
# working on `/pay/`. See Fuime::DiscoverController and AddListingToFuimeOffers.
RSpec.describe "Fuime Discover", type: :request do
  # Pinned names: assertions match rendered HTML, and a Faker apostrophe is
  # escaped. Attributes are set at CREATE — flipping `is_public` afterwards
  # mails a transparency notice that needs User.system_user.
  def payable_venture(name:, slug:, category: "services", tagline: nil, **attrs)
    event = create(:event, {
      name:, slug:, business_category: category,
      storefront_tagline: tagline,
      is_public: true, is_indexable: true
    }.merge(attrs))
    create(:stripe_connected_account, :ready, event:)
    event
  end

  def listed_offer(venture, name:, price_cents: 35_00, **attrs)
    create(:fuime_offer, :published, { event: venture, name:, price_cents: }.merge(attrs))
  end

  # For ventures `#publish!` will refuse (demo, hidden, no payment account).
  # The row still has to exist as published so Discover cannot leak it by
  # state alone.
  def force_published_offer(venture, name:, **attrs)
    offer = create(:fuime_offer, { event: venture, name: }.merge(attrs))
    offer.update_column(:aasm_state, "published")
    offer
  end

  def rendered
    CGI.unescapeHTML(response.body)
  end

  describe "GET /discover" do
    it "answers 200" do
      get fuime_discover_path

      expect(response).to have_http_status(:ok)
    end

    it "lists a listed, payable offer with the operator's price" do
      venture = payable_venture(name: "Maya Design", slug: "maya-design",
                                tagline: "Posters and prints")
      listed_offer(venture, name: "A3 poster", price_cents: 35_00)

      get fuime_discover_path

      expect(response).to have_http_status(:ok)
      expect(rendered).to include("Maya Design")
      expect(rendered).to include("Services")
      expect(rendered).to include("Posters and prints")
      expect(rendered).to include("A3 poster")
      expect(rendered).to include("$35.00")
    end

    it "links each card to /b/:slug with no amount, price, or offer_token" do
      venture = payable_venture(name: "Maya Design", slug: "maya-design")
      listed_offer(venture, name: "A3 poster", price_cents: 35_00)

      get fuime_discover_path

      href = fuime_storefront_path(slug: "maya-design")
      expect(href).to eq("/b/maya-design")
      expect(response.body).to include(%(href="#{href}"))
      expect(response.body).not_to include("#{href}?")
      expect(response.body).not_to include("offer_token")
      expect(response.body).not_to match(/[?&](amount|price|price_cents)=/)
    end

    it "does not post checkout from Discover" do
      venture = payable_venture(name: "Maya Design", slug: "maya-design")
      listed_offer(venture, name: "A3 poster")

      get fuime_discover_path

      expect(response.body).not_to include(fuime_storefront_pay_path(slug: "maya-design"))
      expect(response.body).not_to match(/<form[^>]*method="post"/i)
    end

    it "hides an unlisted offer" do
      venture = payable_venture(name: "Maya Design", slug: "maya-design")
      listed_offer(venture, name: "Private tutoring", listed: false)

      get fuime_discover_path

      expect(rendered).not_to include("Private tutoring")
    end

    it "hides a draft and an archived offer" do
      venture = payable_venture(name: "Maya Design", slug: "maya-design")
      create(:fuime_offer, event: venture, name: "Draft poster")
      create(:fuime_offer, :archived, event: venture, name: "Archived poster")

      get fuime_discover_path

      expect(rendered).not_to include("Draft poster")
      expect(rendered).not_to include("Archived poster")
    end

    it "hides an offer on a venture with no connected account" do
      event = create(:event, name: "No Account Co", slug: "no-account-co",
                             business_category: "services", is_public: true, is_indexable: true)
      offer = create(:fuime_offer, event:, name: "Ghost mow")
      offer.update_column(:aasm_state, "published")

      get fuime_discover_path

      expect(rendered).not_to include("Ghost mow")
      expect(rendered).not_to include("No Account Co")
    end

    it "hides a venture nobody has approved" do
      venture = payable_venture(name: "Unreviewed Co", slug: "unreviewed-co")
      listed_offer(venture, name: "Unreviewed mow")
      venture.update!(operator_vetting_status: :unvetted)

      get fuime_discover_path

      expect(rendered).not_to include("Unreviewed Co")
      expect(rendered).not_to include("Unreviewed mow")
    end

    it "hides a suspended venture" do
      venture = payable_venture(name: "Suspended Co", slug: "suspended-co")
      listed_offer(venture, name: "Suspended mow")
      venture.update!(operator_vetting_status: :suspended)

      get fuime_discover_path

      expect(rendered).not_to include("Suspended Co")
      expect(rendered).not_to include("Suspended mow")
    end

    it "hides private, non-indexable, demo and hidden ventures" do
      private_v = payable_venture(name: "Private Co", slug: "private-co", is_public: false)
      listed_offer(private_v, name: "Private Co offer")

      noindex = payable_venture(name: "Noindex Co", slug: "noindex-co", is_indexable: false)
      listed_offer(noindex, name: "Noindex Co offer")

      demo = payable_venture(name: "Demo Co", slug: "demo-co", demo_mode: true)
      force_published_offer(demo, name: "Demo Co offer")

      hidden = payable_venture(name: "Hidden Co", slug: "hidden-co", hidden_at: Time.current)
      force_published_offer(hidden, name: "Hidden Co offer")

      get fuime_discover_path

      ["Private Co", "Noindex Co", "Demo Co", "Hidden Co"].each do |name|
        expect(rendered).not_to include(name)
        expect(rendered).not_to include("#{name} offer")
      end
    end
  end

  describe "GET /directory still works" do
    it "still lists a vetted payable venture and does not become the offer shop" do
      venture = payable_venture(name: "Maya Design", slug: "maya-design")
      listed_offer(venture, name: "A3 poster", price_cents: 35_00)

      get fuime_directory_path

      expect(response).to have_http_status(:ok)
      expect(rendered).to include("Maya Design")
      expect(rendered).to include(fuime_storefront_path(slug: "maya-design"))
    end
  end

  describe "empty state talks to a founder, not a waiting buyer" do
    it "points at the /pay/ link that works at n=1" do
      get fuime_discover_path

      expect(response).to have_http_status(:ok)
      expect(rendered).to include("/pay/your-business/your-offer")
      expect(rendered).not_to match(/check back soon/i)
    end
  end

  describe "stays a listing, never a dispatch" do
    before do
      venture = payable_venture(name: "Maya Design", slug: "maya-design")
      listed_offer(venture, name: "A3 poster")
    end

    it "offers only neutral orderings" do
      expect(Fuime::DiscoverController::ORDERINGS.keys).to contain_exactly("newest", "name")
    end

    it "orders newest-first by default and ignores a quality ordering" do
      older = payable_venture(name: "Alpha Co", slug: "alpha-co")
      newer = payable_venture(name: "Zeta Co", slug: "zeta-co")
      listed_offer(older, name: "Alpha mow", created_at: 2.days.ago)
      listed_offer(newer, name: "Zeta mow", created_at: 1.hour.ago)

      get fuime_discover_path, params: { order: "highest_rated" }

      expect(response).to have_http_status(:ok)
      expect(rendered.index("Zeta Co")).to be < rendered.index("Alpha Co")
    end

    it "orders A-Z on request" do
      listed_offer(payable_venture(name: "Zeta Co", slug: "zeta-co"), name: "Zeta mow")
      listed_offer(payable_venture(name: "Alpha Co", slug: "alpha-co"), name: "Alpha mow")

      get fuime_discover_path, params: { order: "name" }

      expect(rendered.index("Alpha Co")).to be < rendered.index("Zeta Co")
    end

    it "shows no ratings, reviews, featured, popular or recommended copy" do
      get fuime_discover_path

      expect(rendered).not_to match(/\brating|\breview|\bstars?\b|response rate|completion rate/i)
      expect(rendered).not_to match(/featured|top rated|recommended|best match|verified pro|\bpopular\b|\btrending\b/i)
      expect(response.body).not_to match(/<input[^>]*type="search"/i)
    end

    it "says plainly that Fuime does not assign work or set rates" do
      get fuime_discover_path

      expect(rendered).to match(/does not assign work, set rates, or rank/i)
    end
  end

  describe "privacy" do
    it "names no operator, age, balance, tax or selling blocker" do
      operator = create(:user, :minor_with_guardian, full_name: "Maya Operator", birthday: 15.years.ago.to_date)
      venture = payable_venture(name: "Maya Design", slug: "maya-design")
      create(:organizer_position, event: venture, user: operator)
      listed_offer(venture, name: "A3 poster")

      get fuime_discover_path

      expect(rendered).to include("Maya Design")
      expect(rendered).not_to include("Maya Operator")
      expect(rendered).not_to match(/is 15\b/)
      expect(rendered).not_to match(/Balance:|Current balance|account balance/i)
      expect(rendered).not_to match(/self-employment|\$400/i)
      expect(rendered).not_to match(/suspended|not been approved/i)
      venture.selling_blockers.each { |blocker| expect(rendered).not_to include(blocker) }
    end
  end

  describe "GET /discover/:event_slug/:offer" do
    it "sends a listed payable offer to /b/:slug with no query string" do
      venture = payable_venture(name: "Maya Design", slug: "maya-design")
      offer = listed_offer(venture, name: "A3 poster")

      get fuime_discover_offer_path(event_slug: venture.slug, offer: offer.to_param)

      expect(response).to redirect_to(fuime_storefront_path(slug: venture.slug))
      expect(response.location).not_to include("?")
      expect(response.location).not_to include("offer_token")
      expect(response.location).not_to include("amount")
      expect(response.location).not_to include("price")
    end

    it "404s an unlisted offer rather than redirecting" do
      venture = payable_venture(name: "Maya Design", slug: "maya-design")
      offer = listed_offer(venture, name: "Private tutoring", listed: false)

      get fuime_discover_offer_path(event_slug: venture.slug, offer: offer.to_param)

      expect(response).to have_http_status(:not_found)
      expect(response).not_to be_redirect
      expect(rendered).to include("Not found")
      expect(rendered).not_to match(/isn't for sale|taken down|unlisted/i)
    end

    it "404s a draft, an archived offer, and a missing one" do
      venture = payable_venture(name: "Maya Design", slug: "maya-design")
      draft = create(:fuime_offer, event: venture, name: "Draft poster")
      archived = create(:fuime_offer, :archived, event: venture, name: "Archived poster")

      get fuime_discover_offer_path(event_slug: venture.slug, offer: draft.to_param)
      expect(response).to have_http_status(:not_found)

      get fuime_discover_offer_path(event_slug: venture.slug, offer: archived.to_param)
      expect(response).to have_http_status(:not_found)

      get fuime_discover_offer_path(event_slug: venture.slug, offer: "nosuchoffer")
      expect(response).to have_http_status(:not_found)
    end

    it "404s when the venture cannot be paid" do
      event = create(:event, name: "No Account Co", slug: "no-account-co",
                             business_category: "services", is_public: true, is_indexable: true)
      offer = create(:fuime_offer, event:, name: "Ghost mow")
      offer.update_column(:aasm_state, "published")

      get fuime_discover_offer_path(event_slug: event.slug, offer: offer.to_param)

      expect(response).to have_http_status(:not_found)
      expect(response).not_to be_redirect
    end

    it "leaves an unlisted private pay link working on /pay/" do
      venture = payable_venture(name: "Maya Design", slug: "maya-design")
      offer = listed_offer(venture, name: "Private tutoring", listed: false)

      get fuime_discover_offer_path(event_slug: venture.slug, offer: offer.to_param)
      expect(response).to have_http_status(:not_found)

      get fuime_payment_page_path(event_slug: venture.slug, offer: offer.to_param)
      expect(response).to have_http_status(:ok)
      expect(CGI.unescapeHTML(response.body)).to include("Private tutoring")
    end
  end
end
