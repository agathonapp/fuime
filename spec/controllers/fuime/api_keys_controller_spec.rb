# frozen_string_literal: true

require "rails_helper"

# Fuime: the screen where an operator gets a key for their own software.
#
# `render_views` throughout and deliberately so. The page shows a live secret
# exactly once, and the two ways this feature fails in front of a teenager are a
# template that 500s and a key that is never actually displayed — neither of
# which a controller-only spec can see.
RSpec.describe Fuime::ApiKeysController, type: :controller do
  include SessionSupport
  render_views

  let(:teen) { create(:user, birthday: 16.years.ago.to_date, verified: true) }
  let(:guardian) { create(:user, birthday: 40.years.ago.to_date, verified: true) }
  let(:stranger) { create(:user, birthday: 30.years.ago.to_date, verified: true) }
  let(:event) { create(:event) }

  before do
    create(:organizer_position, event:, user: teen)
    create(:guardianship, :active, guardian:, minor: teen)
  end

  describe "the page" do
    it "renders for the operator" do
      create_session(teen, verified: true)

      get :index, params: { event_slug: event.slug }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Developer")
    end

    it "renders with keys and links on it" do
      key, = Fuime::ApiKey.mint!(event:, created_by: teen, name: "My website")
      Fuime::Offer.create!(event:, name: "Quote for Dana", price_cents: 4500,
                           listed: false, created_via: "api", fuime_api_key: key)
      create_session(teen, verified: true)

      get :index, params: { event_slug: event.slug }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("My website")
      expect(response.body).to include("Quote for Dana")
      # The masked form, never the secret — which the page cannot show anyway.
      expect(response.body).to include(key.display)
    end

    it "shows a guardian the keys without a way to mint one" do
      create_session(guardian, verified: true)

      Fuime::ApiKey.mint!(event:, created_by: teen, name: "My website")

      get :index, params: { event_slug: event.slug }

      # Sees it (visibility without control, as on the offers screen) but gets no
      # form to make another. `rails-controller-testing` is not in the Gemfile, so
      # this reads the rendered page rather than an assigns() ivar.
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("My website")
      expect(response.body).not_to include("Create a key")
    end

    # Pundit::NotAuthorizedError is rescued by ApplicationController, so these
    # assert the effect rather than the exception — same as the offers spec.
    it "refuses a stranger" do
      create_session(stranger, verified: true)

      get :index, params: { event_slug: event.slug }

      expect(response).not_to have_http_status(:ok)
    end
  end

  describe "minting" do
    it "creates a key and shows the plaintext exactly once" do
      create_session(teen, verified: true)

      post :create, params: { event_slug: event.slug, name: "My website" }

      key = event.fuime_api_keys.sole
      expect(key.name).to eq("My website")

      # Shown in the response that CREATED it — not carried to a later request.
      #
      # This used to travel in `flash[:fuime_fresh_api_key]`, and the app has no
      # session_store initializer, so the session is Rails' default COOKIE store:
      # that wrote a live credential into the browser's cookie jar and replayed it
      # on the next request. Security review 2026-08-20, F-08.
      expect(response).to have_http_status(:ok)
      fresh = response.body[/#{Regexp.escape(Fuime::ApiKey::PREFIX)}[A-Za-z0-9_-]+/]
      expect(fresh).to be_present
      expect(Fuime::ApiKey.authenticate(fresh)).to eq(key)

      # The assertion that matters: the secret is in the page, and in no cookie.
      expect(flash.to_hash.values.join).not_to include(Fuime::ApiKey::PREFIX)

      # And still exactly once — a later load of the same page does not show it.
      get :index, params: { event_slug: event.slug }
      expect(response.body).not_to include(fresh)
    end

    # A key is the power to name an amount and ask a customer for it, which is
    # pricing by another route — so it carries the pricing gate, not a weaker one.
    it "refuses a guardian, who does not set prices" do
      create_session(guardian, verified: true)

      expect { post :create, params: { event_slug: event.slug, name: "Nope" } }
        .not_to(change { event.fuime_api_keys.count })
    end

    it "refuses more keys than the cap allows" do
      Fuime::ApiKey::MAX_LIVE_KEYS.times { |i| Fuime::ApiKey.mint!(event:, created_by: teen, name: "k#{i}") }
      create_session(teen, verified: true)

      expect { post :create, params: { event_slug: event.slug, name: "One too many" } }
        .not_to(change { event.fuime_api_keys.live.count })
      expect(flash[:alert]).to be_present
    end
  end

  describe "revoking" do
    it "stops the key working immediately" do
      key, plain = Fuime::ApiKey.mint!(event:, created_by: teen, name: "Leaked")
      create_session(teen, verified: true)

      delete :destroy, params: { event_slug: event.slug, id: key.id }

      expect(key.reload).to be_revoked
      expect(Fuime::ApiKey.authenticate(plain)).to be_nil
    end

    # Revoking a key means "this program can no longer ask for money". It does
    # not mean the $45 a customer was already sent should stop working — taking
    # a link down is its own action, on the link.
    it "leaves links the key already made alone" do
      key, = Fuime::ApiKey.mint!(event:, created_by: teen, name: "Leaked")
      offer = Fuime::Offer.create!(event:, name: "Already sent", price_cents: 4500,
                                   listed: false, created_via: "api", fuime_api_key: key)
      create_session(teen, verified: true)

      delete :destroy, params: { event_slug: event.slug, id: key.id }

      expect(offer.reload).not_to be_archived
    end

    it "refuses a guardian" do
      key, = Fuime::ApiKey.mint!(event:, created_by: teen, name: "Theirs")
      create_session(guardian, verified: true)

      delete :destroy, params: { event_slug: event.slug, id: key.id }

      expect(key.reload).not_to be_revoked
    end
  end

  # The property that makes it reasonable to paste a key into a prompt at all.
  describe "what a key is worth to whoever steals it" do
    it "is never recoverable in plaintext from the record" do
      key, plain = Fuime::ApiKey.mint!(event:, created_by: teen, name: "Website")

      raw = Fuime::ApiKey.connection.select_one(
        "SELECT * FROM fuime_api_keys WHERE id = #{key.id}"
      )

      expect(raw.values.map(&:to_s)).not_to include(plain)
      expect(raw["token_ciphertext"]).to be_present
      expect(raw.to_s).not_to include(plain)
    end
  end

end
