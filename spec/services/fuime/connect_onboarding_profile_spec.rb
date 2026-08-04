# frozen_string_literal: true

require "rails_helper"

# Fuime: the account-configuration profile, which is the one decision about a
# venture's Stripe account that can never be revised.
#
# Stripe's `controller` property is create-only — the Account update endpoint takes
# no controller parameters — so getting this wrong at creation means a family has to
# re-onboard onto a brand new account. Every example here exists because the failure
# it describes is permanent.
RSpec.describe Fuime::ConnectOnboardingService, "account profiles" do
  let(:venture) { create(:event) }
  let(:guardian) { create(:user, birthday: 40.years.ago.to_date) }

  def stub_account_create(controller_hash)
    account = Stripe::Account.construct_from(
      id: "acct_profile_test",
      charges_enabled: false,
      payouts_enabled: false,
      details_submitted: false,
      livemode: false,
      controller: controller_hash,
      capabilities: {},
      requirements: {}
    )
    allow(Stripe::Account).to receive(:create).and_return(account)
    account
  end

  def payments_only_controller
    {
      losses: { payments: "stripe" },
      fees: { payer: "account" },
      requirement_collection: "stripe",
      stripe_dashboard: { type: "none" }
    }
  end

  def cards_controller
    {
      losses: { payments: "application" },
      fees: { payer: "application" },
      requirement_collection: "application",
      stripe_dashboard: { type: "none" }
    }
  end

  describe "the profile definitions" do
    # These four values are the entire cost of supporting cards. If one of them
    # drifts, Fuime either silently takes on loss liability it did not intend or
    # loses the ability to issue cards it promised. Pinned literally rather than
    # derived, so a change has to be made on purpose.
    it "keeps Stripe liable and Stripe-collected on the default profile" do
      controller = described_class::PROFILES[:payments_only][:controller]

      expect(controller[:losses][:payments]).to eq("stripe")
      expect(controller[:fees][:payer]).to eq("account")
      expect(controller[:requirement_collection]).to eq("stripe")
    end

    it "moves liability, requirement collection and fees to Fuime on the cards profile" do
      controller = described_class::PROFILES[:cards_enabled][:controller]

      # Fuime absorbs every negative balance on this venture.
      expect(controller[:losses][:payments]).to eq("application")
      # The guardian's SSN and ID documents land in Fuime's systems.
      expect(controller[:requirement_collection]).to eq("application")
      # Fuime pays ~2.9% + 30¢ on every charge, which a 4% platform fee does not cover.
      expect(controller[:fees][:payer]).to eq("application")
    end

    it "requests card_issuing only on the cards profile" do
      expect(described_class::PROFILES[:cards_enabled][:capabilities]).to have_key(:card_issuing)
      expect(described_class::PROFILES[:payments_only][:capabilities]).not_to have_key(:card_issuing)
    end

    it "defaults to the profile that keeps Fuime out of the loss path" do
      expect(described_class::DEFAULT_PROFILE).to eq(:payments_only)
    end

    it "refuses a profile it does not know" do
      expect {
        described_class.new(event: venture, guardian:, profile: :treasury)
      }.to raise_error(described_class::UnknownProfile)
    end
  end

  describe "creating an account" do
    it "sends the default controller config when no profile is given" do
      stub_account_create(payments_only_controller)

      described_class.new(event: venture, guardian:).find_or_create_account!

      expect(Stripe::Account).to have_received(:create).with(
        hash_including(controller: described_class::PROFILES[:payments_only][:controller]),
        anything
      )
    end

    it "sends the cards controller config and requests card_issuing" do
      stub_account_create(cards_controller)

      described_class.new(event: venture, guardian:, profile: :cards_enabled).find_or_create_account!

      expect(Stripe::Account).to have_received(:create).with(
        hash_including(
          controller: described_class::PROFILES[:cards_enabled][:controller],
          capabilities: hash_including(card_issuing: { requested: true })
        ),
        anything
      )
    end

    it "records the requested profile on the local row" do
      stub_account_create(cards_controller)

      record = described_class.new(event: venture, guardian:, profile: :cards_enabled)
                              .find_or_create_account!

      expect(record.controller_profile).to eq("cards_enabled")
      expect(record).to be_cards_profile
    end

    # The reason the profile is written BEFORE the Stripe call. A retry that fell
    # back to the default would create a payments-only account for a family who
    # asked for a card, and that account can never be upgraded.
    it "records the profile before the Stripe call, so a retry requests the same one" do
      allow(Stripe::Account).to receive(:create).and_raise(Stripe::APIError.new("timeout"))
      service = described_class.new(event: venture, guardian:, profile: :cards_enabled)

      expect { service.find_or_create_account! }.to raise_error(Stripe::APIError)

      row = venture.reload.stripe_connected_account
      expect(row).to be_present
      expect(row.stripe_id).to be_nil
      expect(row.controller_profile).to eq("cards_enabled")
    end

    it "mirrors the controller config Stripe actually returned" do
      stub_account_create(cards_controller)

      record = described_class.new(event: venture, guardian:, profile: :cards_enabled)
                              .find_or_create_account!

      expect(record.controller["losses"]["payments"]).to eq("application")
      expect(record).to be_controller_matches_requested_profile
    end

    # The failure the mixed-fleet inference could actually produce: Stripe accepts
    # the call but builds a Stripe-liable account anyway.
    it "detects Stripe returning a different config than was requested" do
      stub_account_create(payments_only_controller)

      record = described_class.new(event: venture, guardian:, profile: :cards_enabled)
                              .find_or_create_account!

      expect(record).not_to be_controller_matches_requested_profile
      expect(record).not_to be_ready_for_cards
    end
  end

  describe "an account that already exists" do
    it "reuses it when the profile matches, without touching Stripe" do
      allow(Stripe::Account).to receive(:create)
      existing = create(:stripe_connected_account, :ready, event: venture, owner: guardian)

      record = described_class.new(event: venture, guardian:).find_or_create_account!

      expect(record).to eq(existing)
      expect(Stripe::Account).not_to have_received(:create)
    end

    # `controller` cannot be changed, so there is no third answer here. Raising is
    # the only alternative to silently doing the wrong thing in one direction or
    # the other.
    it "refuses to serve a cards request from a payments-only account" do
      create(:stripe_connected_account, :ready, event: venture, owner: guardian)

      expect {
        described_class.new(event: venture, guardian:, profile: :cards_enabled).find_or_create_account!
      }.to raise_error(described_class::UnknownProfile, /create-only|re-onboarded/i)
    end

    it "refuses to serve a payments-only request from a cards account" do
      create(:stripe_connected_account, :cards_active, event: venture, owner: guardian)

      expect {
        described_class.new(event: venture, guardian:).find_or_create_account!
      }.to raise_error(described_class::UnknownProfile)
    end
  end

  describe "onboarding surface for the cards profile" do
    # The embedded component is built for requirement_collection=stripe. The cards
    # profile inverts that, making Fuime responsible for collecting the guardian's
    # identity details, which is a different flow with different obligations (L4:
    # never store ID images). Serving the wrong one to a real guardian would either
    # collect nothing or do nothing.
    it "refuses rather than serving a flow built for Stripe-collected requirements" do
      service = described_class.new(event: venture, guardian:, profile: :cards_enabled)

      expect {
        service.account_session_client_secret
      }.to raise_error(described_class::OnboardingPathNotImplemented, /requirement_collection=application/)
    end

    it "still serves the default profile" do
      stub_account_create(payments_only_controller)
      allow(Stripe::AccountSession).to receive(:create)
        .and_return(Stripe::AccountSession.construct_from(client_secret: "cs_test_123"))

      service = described_class.new(event: venture, guardian:)

      expect(service.account_session_client_secret).to eq("cs_test_123")
    end
  end

  describe "StripeConnectedAccount#ready_for_cards?" do
    it "is false for a payments-only venture however healthy" do
      expect(create(:stripe_connected_account, :ready)).not_to be_ready_for_cards
    end

    it "is false while card_issuing is still pending" do
      account = create(:stripe_connected_account, :cards_active)
      account.update!(capabilities: account.capabilities.merge("card_issuing" => "pending"))

      expect(account).not_to be_ready_for_cards
    end

    it "is false when Stripe built a different config than requested" do
      expect(create(:stripe_connected_account, :profile_mismatch)).not_to be_ready_for_cards
    end

    it "is true only when the profile, the config and the capability all agree" do
      expect(create(:stripe_connected_account, :cards_active)).to be_ready_for_cards
    end
  end
end
