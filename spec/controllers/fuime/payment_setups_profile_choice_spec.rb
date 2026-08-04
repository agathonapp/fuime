# frozen_string_literal: true

require "rails_helper"

# Fuime: choosing the account profile, which is the only moment it CAN be chosen.
#
# Stripe's `controller` property is create-only, so this decision is permanent per
# venture. The examples here are mostly about what must NOT be possible: a family
# reaching the loss-bearing profile without someone deliberately enabling it, and a URL
# parameter reinterpreting an account that already exists.
RSpec.describe Fuime::PaymentSetupsController do
  include SessionSupport

  render_views

  let(:venture) { create(:event, name: "Maya Prints", slug: "mayas-prints") }
  let(:minor) { create(:user, :minor) }
  let(:guardian) { create(:user, birthday: 40.years.ago.to_date) }

  before do
    create(:organizer_position, event: venture, user: minor)
    create(:guardianship, :active, guardian:, minor:)
  end

  def enable_cards!
    Flipper.enable(described_class::CARDS_FLAG, venture)
  end

  def stub_account_create(controller_hash)
    allow(Stripe::Account).to receive(:create).and_return(
      Stripe::Account.construct_from(
        id: "acct_choice_test",
        charges_enabled: false, payouts_enabled: false, details_submitted: false,
        livemode: false, controller: controller_hash, capabilities: {}, requirements: {}
      )
    )
    allow(Stripe::AccountSession).to receive(:create)
      .and_return(Stripe::AccountSession.construct_from(client_secret: "cs_test_1"))
  end

  def payments_only_controller
    { losses: { payments: "stripe" }, fees: { payer: "account" },
      requirement_collection: "stripe", stripe_dashboard: { type: "none" }
}
  end

  def cards_controller
    { losses: { payments: "application" }, fees: { payer: "application" },
      requirement_collection: "application", stripe_dashboard: { type: "none" }
}
  end

  describe "GET #show, the choice" do
    it "offers only the standard setup when cards are not enabled" do
      create_session(guardian, verified: true)

      get :show, params: { event_slug: venture.slug }

      expect(response.body).to include("Set up payments")
      expect(response.body).not_to include("get a business card")
    end

    it "offers both options once cards are enabled for the venture" do
      enable_cards!
      create_session(guardian, verified: true)

      get :show, params: { event_slug: venture.slug }

      expect(response.body).to include("Take payments")
      expect(response.body).to include("get a business card")
    end

    # `controller` is create-only, so re-offering the choice would promise something only
    # a full re-onboarding could deliver.
    it "stops offering the choice once an account exists" do
      enable_cards!
      create(:stripe_connected_account, :ready, event: venture, owner: guardian)
      create_session(guardian, verified: true)

      get :show, params: { event_slug: venture.slug }

      expect(response.body).not_to include("get a business card")
    end

    it "warns that the choice cannot be changed later" do
      enable_cards!
      create_session(guardian, verified: true)

      get :show, params: { event_slug: venture.slug }

      # A contiguous fragment, and no apostrophe. The sentence wraps across a line in the
      # template (so "an account later" is split by a newline) and ERB escapes "can't" to
      # `can&#39;t` — two separate reasons a longer match would fail on formatting rather
      # than on behaviour.
      expect(response.body).to match(/add card support/i)
      expect(response.body).to match(/setting this venture up again/i)
    end
  end

  describe "GET #new, creating the account" do
    it "creates a payments-only account by default" do
      stub_account_create(payments_only_controller)
      create_session(guardian, verified: true)

      get :new, params: { event_slug: venture.slug }

      expect(venture.reload.stripe_connected_account.controller_profile).to eq("payments_only")
    end

    it "creates a cards account when asked and the flag is on" do
      enable_cards!
      stub_account_create(cards_controller)
      create_session(guardian, verified: true)

      get :new, params: { event_slug: venture.slug, profile: "cards_enabled" }

      account = venture.reload.stripe_connected_account
      expect(account.controller_profile).to eq("cards_enabled")
      expect(account).to be_cards_profile
    end

    # THE security example. `?profile=cards_enabled` is a URL anyone can type, and the
    # cards profile is the one where Fuime carries every chargeback on a minor's business.
    # It must not be reachable by guessing a query string.
    it "ignores profile=cards_enabled when the flag is off" do
      stub_account_create(payments_only_controller)
      create_session(guardian, verified: true)

      get :new, params: { event_slug: venture.slug, profile: "cards_enabled" }

      expect(venture.reload.stripe_connected_account.controller_profile).to eq("payments_only")
      expect(Stripe::Account).to have_received(:create).with(
        hash_including(controller: hash_including(losses: { payments: "stripe" })),
        anything
      )
    end

    it "ignores an unrecognised profile param" do
      enable_cards!
      stub_account_create(payments_only_controller)
      create_session(guardian, verified: true)

      get :new, params: { event_slug: venture.slug, profile: "treasury" }

      expect(venture.reload.stripe_connected_account.controller_profile).to eq("payments_only")
    end

    # An existing account's profile is the only valid answer for it, so a stale or
    # tampered link cannot make the service raise on a profile mismatch.
    it "uses the existing account's profile regardless of the param" do
      # The account already exists, so #new goes on to mint an Account Session for the
      # embedded flow. Stubbed here because this example does not call stub_account_create.
      allow(Stripe::AccountSession).to receive(:create)
        .and_return(Stripe::AccountSession.construct_from(client_secret: "cs_test_1"))
      create(:stripe_connected_account, :ready, event: venture, owner: guardian)
      create_session(guardian, verified: true)

      expect {
        get :new, params: { event_slug: venture.slug, profile: "cards_enabled" }
      }.not_to raise_error

      expect(venture.reload.stripe_connected_account.controller_profile).to eq("payments_only")
    end
  end

  describe "where each profile sends the guardian" do
    # Payments-only collects through Stripe's embedded component.
    it "sends a payments-only venture to the embedded Stripe flow" do
      stub_account_create(payments_only_controller)
      create_session(guardian, verified: true)

      get :new, params: { event_slug: venture.slug }

      expect(response).to have_http_status(:ok)
    end

    # The cards profile sets `requirement_collection = application`, so Stripe's component
    # would collect nothing. It has to go to Fuime's own form instead.
    it "sends a cards venture to Fuime's own verification form" do
      enable_cards!
      stub_account_create(cards_controller)
      create_session(guardian, verified: true)

      get :new, params: { event_slug: venture.slug, profile: "cards_enabled" }

      expect(response).to redirect_to(fuime_requirement_collection_path(event_slug: venture.slug))
    end

    it "never asks Stripe for an account session on the cards profile" do
      enable_cards!
      stub_account_create(cards_controller)
      create_session(guardian, verified: true)

      get :new, params: { event_slug: venture.slug, profile: "cards_enabled" }

      expect(Stripe::AccountSession).not_to have_received(:create)
    end
  end

  describe "the teen's view" do
    it "never offers the choice to the teen" do
      enable_cards!
      create_session(minor, verified: true)

      get :show, params: { event_slug: venture.slug }

      expect(response.body).not_to include("get a business card")
    end

    it "refuses the teen creating an account at all" do
      enable_cards!
      stub_account_create(cards_controller)
      create_session(minor, verified: true)

      get :new, params: { event_slug: venture.slug, profile: "cards_enabled" }

      expect(venture.reload.stripe_connected_account).to be_nil
    end
  end
end
