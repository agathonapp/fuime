# frozen_string_literal: true

require "rails_helper"

# Fuime: the card screens.
#
# The design being asserted is the authorization SPLIT, not just that authorization
# exists. A teen may freeze a card but not unfreeze it, may see limits but not raise them.
# Freeze-but-not-unfreeze is the whole idea: freezing only ever reduces what is spendable,
# so the person who notices a lost card first should be able to act, while restoring spend
# stays with the adult who carries the liability.
RSpec.describe Fuime::CardsController do
  include SessionSupport

  render_views

  let(:venture) { create(:event, name: "Maya Prints", slug: "mayas-prints") }
  let(:minor) { create(:user, :minor, birthday: 15.years.ago.to_date) }
  let(:guardian) { create(:user, birthday: 40.years.ago.to_date) }

  let!(:account) do
    create(:stripe_connected_account, :cards_active, event: venture, owner: guardian)
  end

  let(:cardholder) { create(:venture_cardholder, event: venture, user: minor) }
  let!(:card) { create(:venture_card, venture_cardholder: cardholder, stripe_id: "ic_1") }

  # Guarded rather than unconditional: `let!(:card)` builds the cardholder first, and the
  # venture_cardholder factory creates the position itself as part of satisfying its own
  # validations. Creating a second one raises ("User is already an organizer of this
  # event"), and which runs first depends on `let!` declaration order — so this does not
  # depend on that order at all.
  before do
    unless OrganizerPosition.exists?(user_id: minor.id, event_id: venture.id, deleted_at: nil)
      create(:organizer_position, event: venture, user: minor)
    end

    create(:guardianship, :active, guardian:, minor:)
  end

  def stub_card_update(status: "active", limit: 25_000, allowed: Fuime::CardSpendPolicy.allowed_categories)
    allow(Stripe::Issuing::Card).to receive(:update).and_return(
      Stripe::Issuing::Card.construct_from(
        id: "ic_1", last4: "4242", brand: "Visa", exp_month: 12, exp_year: Date.current.year + 3,
        status:, type: "virtual",
        spending_controls: { allowed_categories: allowed, spending_limits: [{ amount: limit, interval: "monthly" }] }
      )
    )
  end

  def stub_card_create(id: "ic_new")
    allow(Stripe::Issuing::Card).to receive(:create).and_return(
      Stripe::Issuing::Card.construct_from(
        id:, last4: "9999", brand: "Visa", exp_month: 12, exp_year: Date.current.year + 3,
        status: "active", type: "virtual",
        spending_controls: {
          allowed_categories: Fuime::CardSpendPolicy.allowed_categories,
          spending_limits: [{ amount: 25_000, interval: "monthly" }]
        }
      )
    )
  end

  describe "GET #index" do
    it "shows cards to the teen" do
      create_session(minor, verified: true)

      get :index, params: { event_slug: venture.slug }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("4242")
    end

    it "shows cards to the guardian" do
      create_session(guardian, verified: true)

      get :index, params: { event_slug: venture.slug }

      expect(response).to have_http_status(:ok)
    end

    # Required by Stripe's US Issuing compliance rules wherever the program is described.
    it "carries the required commercial-purpose disclosure and no forbidden phrasing" do
      create_session(minor, verified: true)

      get :index, params: { event_slug: venture.slug }

      expect(Fuime::CardSpendPolicy.copy_violations(response.body)).to be_empty
    end

    # Never rendered, and never received: Stripe shows the number to the cardholder
    # through its own components, which keeps Fuime out of PCI scope.
    it "never renders a full card number" do
      create_session(minor, verified: true)

      get :index, params: { event_slug: venture.slug }

      expect(response.body).not_to match(/\b4242\s*4242\s*4242\s*4242\b/)
    end

    it "offers the teen a freeze button but no limit controls" do
      create_session(minor, verified: true)

      get :index, params: { event_slug: venture.slug }

      expect(response.body).to include("Freeze")
      expect(response.body).not_to include("Issue card")
      expect(response.body).not_to include("New limit")
    end

    it "offers the guardian the limit and cancel controls" do
      create_session(guardian, verified: true)

      get :index, params: { event_slug: venture.slug }

      expect(response.body).to include("Issue card")
      expect(response.body).to include("New limit")
    end

    # A card without the allowlist is an unrestricted commercial card, which is a
    # compliance problem rather than a cosmetic one, so it is called out loudly.
    it "flags a card that lost its spending restrictions" do
      card.update!(commercial_controls_applied: false)
      create_session(guardian, verified: true)

      get :index, params: { event_slug: venture.slug }

      expect(response.body).to match(/Spending restrictions missing/i)
    end

    it "refuses an unrelated user" do
      create_session(create(:user), verified: true)

      get :index, params: { event_slug: venture.slug }

      expect(response).not_to have_http_status(:ok)
    end
  end

  describe "POST #create" do
    let(:other_minor) { create(:user, :minor) }
    let!(:other_holder) do
      create(:organizer_position, event: venture, user: other_minor)
      create(:venture_cardholder, event: venture, user: other_minor)
    end

    it "lets the guardian issue a card" do
      stub_card_create
      create_session(guardian, verified: true)

      expect {
        post :create, params: { event_slug: venture.slug, venture_cardholder_id: other_holder.id,
                                spending_limit: "100.00"
}
      }.to change(VentureCard, :count).by(1)

      expect(flash[:notice]).to match(/Card issued/i)
    end

    # Issuing creates a liability the guardian carries. Not the teen's to create.
    it "refuses the teen" do
      stub_card_create
      create_session(minor, verified: true)

      expect {
        post :create, params: { event_slug: venture.slug, venture_cardholder_id: other_holder.id }
      }.not_to change(VentureCard, :count)
    end

    it "surfaces a refusal from the issuing service" do
      create_session(guardian, verified: true)
      other_holder.update!(terms_accepted_at: nil, terms_version: nil)

      post :create, params: { event_slug: venture.slug, venture_cardholder_id: other_holder.id }

      expect(flash[:alert]).to match(/terms/i)
    end
  end

  describe "PATCH #update" do
    it "lets the guardian raise the limit" do
      stub_card_update(limit: 50_000)
      create_session(guardian, verified: true)

      patch :update, params: { event_slug: venture.slug, id: card.id, spending_limit: "$500.00" }

      expect(card.reload.spending_limit_cents).to eq(50_000)
    end

    it "refuses the teen raising their own limit" do
      stub_card_update(limit: 50_000)
      create_session(minor, verified: true)

      patch :update, params: { event_slug: venture.slug, id: card.id, spending_limit: "500" }

      expect(card.reload.spending_limit_cents).to eq(25_000)
      expect(Stripe::Issuing::Card).not_to have_received(:update)
    end

    it "asks again rather than failing on an unusable amount" do
      stub_card_update
      create_session(guardian, verified: true)

      patch :update, params: { event_slug: venture.slug, id: card.id, spending_limit: "abc" }

      expect(flash[:alert]).to match(/at least \$1/i)
      expect(Stripe::Issuing::Card).not_to have_received(:update)
    end

    # The policy is checked against the venture in the URL, so a global lookup would let a
    # guardian of one venture act on another venture's card by id.
    it "will not touch a card belonging to another venture" do
      stub_card_update
      other_card = create(:venture_card)
      create_session(guardian, verified: true)

      expect {
        patch :update, params: { event_slug: venture.slug, id: other_card.id, spending_limit: "500" }
      }.to raise_error(ActiveRecord::RecordNotFound)
    end
  end

  describe "POST #freeze" do
    # The deliberate exception. A teenager who lost their card cannot wait for a parent.
    it "lets the TEEN freeze a card" do
      stub_card_update(status: "inactive")
      create_session(minor, verified: true)

      post :freeze, params: { event_slug: venture.slug, id: card.id }

      expect(card.reload.status).to eq("inactive")
      expect(flash[:notice]).to match(/frozen/i)
    end

    it "lets the guardian freeze a card too" do
      stub_card_update(status: "inactive")
      create_session(guardian, verified: true)

      post :freeze, params: { event_slug: venture.slug, id: card.id }

      expect(card.reload.status).to eq("inactive")
    end

    it "refuses an unrelated user" do
      stub_card_update(status: "inactive")
      create_session(create(:user), verified: true)

      post :freeze, params: { event_slug: venture.slug, id: card.id }

      expect(card.reload.status).to eq("active")
    end
  end

  describe "POST #unfreeze" do
    before { card.update!(status: "inactive") }

    it "lets the guardian unfreeze" do
      stub_card_update(status: "active")
      create_session(guardian, verified: true)

      post :unfreeze, params: { event_slug: venture.slug, id: card.id }

      expect(card.reload.status).to eq("active")
    end

    # THE asymmetry. Without this, freeze/unfreeze would be a route around the guardian's
    # control of what is spendable.
    it "refuses the teen, who may freeze but not restore spending" do
      stub_card_update(status: "active")
      create_session(minor, verified: true)

      post :unfreeze, params: { event_slug: venture.slug, id: card.id }

      expect(card.reload.status).to eq("inactive")
      expect(Stripe::Issuing::Card).not_to have_received(:update)
    end
  end

  describe "DELETE #destroy" do
    it "lets the guardian cancel a card" do
      stub_card_update(status: "canceled")
      create_session(guardian, verified: true)

      delete :destroy, params: { event_slug: venture.slug, id: card.id }

      expect(card.reload.status).to eq("canceled")
      expect(flash[:notice]).to match(/can't be undone/i)
    end

    it "refuses the teen" do
      stub_card_update(status: "canceled")
      create_session(minor, verified: true)

      delete :destroy, params: { event_slug: venture.slug, id: card.id }

      expect(card.reload.status).to eq("active")
    end
  end
end
