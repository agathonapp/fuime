# frozen_string_literal: true

require "rails_helper"

# Fuime: issuing a business card on a venture's own Stripe account.
#
# The examples that matter most are the refusals. An unrestricted card in a
# fifteen-year-old's hands is a compliance incident that surfaces months later in an
# audit, so this service is written to fail rather than to degrade, and these pin each
# of those failures.
RSpec.describe Fuime::CardIssuingService do
  let(:venture) { create(:event) }
  let(:minor) { create(:user, :minor, birthday: 15.years.ago.to_date) }
  let(:guardian) { create(:user, birthday: 40.years.ago.to_date) }

  let(:service) { described_class.new(event: venture) }

  let(:address) do
    { line1: "1 Founders Way", city: "Austin", state: "TX", postal_code: "78701" }
  end

  before do
    create(:organizer_position, event: venture, user: minor)
    create(:guardianship, :active, guardian:, minor:)
  end

  # A venture whose Stripe account was created FOR cards and has issuing live.
  def enable_cards!
    create(:stripe_connected_account, :cards_active, event: venture, owner: guardian)
  end

  def stub_cardholder(id: "ich_test_1", status: "active")
    holder = Stripe::Issuing::Cardholder.construct_from(id:, status:, requirements: {})
    allow(Stripe::Issuing::Cardholder).to receive(:create).and_return(holder)
    holder
  end

  def stub_card(id: "ic_test_1", allowed: Fuime::CardSpendPolicy.allowed_categories, limit: 25_000)
    card = Stripe::Issuing::Card.construct_from(
      id:, last4: "4242", brand: "Visa", exp_month: 12, exp_year: Date.current.year + 3,
      status: "active", type: "virtual",
      spending_controls: {
        allowed_categories: allowed,
        spending_limits: [{ amount: limit, interval: "monthly" }]
      }
    )
    allow(Stripe::Issuing::Card).to receive(:create).and_return(card)
    allow(Stripe::Issuing::Card).to receive(:update).and_return(card)
    card
  end

  describe "#find_or_create_cardholder!" do
    before { enable_cards! }

    it "registers the teen as an authorized user" do
      stub_cardholder

      record = service.find_or_create_cardholder!(
        user: minor, role: VentureCardholder::AUTHORIZED_USER, billing_address: address
      )

      expect(record).to be_authorized_user
      expect(record.stripe_id).to eq("ich_test_1")
      expect(record.status).to eq("active")
    end

    it "registers the guardian as the accountholder" do
      stub_cardholder

      record = service.find_or_create_cardholder!(
        user: guardian, role: VentureCardholder::ACCOUNTHOLDER, billing_address: address
      )

      expect(record).to be_accountholder
    end

    # Stripe has a first-class field for this, so the acceptance becomes a fact Stripe
    # holds rather than a claim in Fuime's database.
    it "reports the terms acceptance to Stripe" do
      stub_cardholder

      service.find_or_create_cardholder!(
        user: minor, role: VentureCardholder::AUTHORIZED_USER,
        billing_address: address, terms_ip: "203.0.113.9"
      )

      expect(Stripe::Issuing::Cardholder).to have_received(:create).with(
        hash_including(
          individual: hash_including(
            card_issuing: { user_terms_acceptance: hash_including(ip: "203.0.113.9") }
          )
        ),
        anything
      )
    end

    it "issues on the venture's own connected account" do
      stub_cardholder
      account = venture.stripe_connected_account

      service.find_or_create_cardholder!(
        user: minor, role: VentureCardholder::AUTHORIZED_USER, billing_address: address
      )

      expect(Stripe::Issuing::Cardholder).to have_received(:create).with(
        anything, hash_including(stripe_account: account.stripe_id)
      )
    end

    # A second Stripe Cardholder for the same person would split their card history.
    it "is idempotent per person per venture" do
      stub_cardholder

      first = service.find_or_create_cardholder!(
        user: minor, role: VentureCardholder::AUTHORIZED_USER, billing_address: address
      )
      second = described_class.new(event: venture).find_or_create_cardholder!(
        user: minor, role: VentureCardholder::AUTHORIZED_USER, billing_address: address
      )

      expect(second.id).to eq(first.id)
      expect(Stripe::Issuing::Cardholder).to have_received(:create).once
    end

    it "refuses without a full billing address" do
      stub_cardholder

      expect {
        service.find_or_create_cardholder!(
          user: minor, role: VentureCardholder::AUTHORIZED_USER,
          billing_address: { line1: "1 Founders Way" }
        )
      }.to raise_error(described_class::MissingBillingAddress, /city|state|postal_code/)
    end

    # The assertion the whole arrangement rests on. A minor recorded as the
    # Accountholder would misstate who carries the card liability.
    it "will not record a minor as the accountholder" do
      stub_cardholder

      expect {
        service.find_or_create_cardholder!(
          user: minor, role: VentureCardholder::ACCOUNTHOLDER, billing_address: address
        )
      }.to raise_error(ActiveRecord::RecordInvalid, /adult/i)
    end

    it "leaves a retryable row when Stripe fails mid-create" do
      allow(Stripe::Issuing::Cardholder).to receive(:create).and_raise(Stripe::APIError.new("boom"))

      expect {
        service.find_or_create_cardholder!(
          user: minor, role: VentureCardholder::AUTHORIZED_USER, billing_address: address
        )
      }.to raise_error(described_class::Error)

      row = VentureCardholder.find_by(event: venture, user: minor)
      expect(row).to be_present
      expect(row.stripe_id).to be_nil
    end
  end

  describe "cards on a venture that cannot have them" do
    # `controller` is create-only, so this is permanent rather than a "not yet".
    it "refuses on a payments-only venture and says re-onboarding is needed" do
      create(:stripe_connected_account, :ready, event: venture, owner: guardian)

      expect {
        service.find_or_create_cardholder!(
          user: minor, role: VentureCardholder::AUTHORIZED_USER, billing_address: address
        )
      }.to raise_error(described_class::CardsNotAvailable, /set up again/i)
    end

    it "refuses when Stripe has not activated card issuing yet" do
      account = create(:stripe_connected_account, :cards_enabled, :ready, event: venture, owner: guardian)
      account.update!(capabilities: account.capabilities.merge("card_issuing" => "pending"))

      expect {
        service.find_or_create_cardholder!(
          user: minor, role: VentureCardholder::AUTHORIZED_USER, billing_address: address
        )
      }.to raise_error(described_class::CardsNotAvailable, /hasn't enabled card issuing/i)
    end

    it "refuses when Stripe built a different account config than requested" do
      create(:stripe_connected_account, :profile_mismatch, event: venture, owner: guardian)

      expect {
        service.find_or_create_cardholder!(
          user: minor, role: VentureCardholder::AUTHORIZED_USER, billing_address: address
        )
      }.to raise_error(described_class::CardsNotAvailable)
    end
  end

  describe "#issue_card!" do
    before { enable_cards! }

    let(:cardholder) { create(:venture_cardholder, event: venture, user: minor) }

    it "issues a virtual card and mirrors what Stripe returned" do
      stub_card

      card = service.issue_card!(cardholder:)

      expect(card.stripe_id).to eq("ic_test_1")
      expect(card.last4).to eq("4242")
      expect(card.card_type).to eq(VentureCard::VIRTUAL)
      expect(card).to be_active
    end

    # The control that makes "business purchases only" real rather than aspirational.
    it "sends Fuime's category allowlist as spending controls" do
      stub_card

      service.issue_card!(cardholder:)

      expect(Stripe::Issuing::Card).to have_received(:create).with(
        hash_including(
          spending_controls: hash_including(
            allowed_categories: Fuime::CardSpendPolicy.allowed_categories
          )
        ),
        anything
      )
    end

    # Stripe accepts one or the other. Sending a blocklist instead would fail open on
    # every category Stripe adds after this code was written.
    it "never sends blocked_categories, which would fail open" do
      stub_card

      service.issue_card!(cardholder:)

      expect(Stripe::Issuing::Card).to have_received(:create) do |params, _opts|
        expect(params[:spending_controls]).not_to have_key(:blocked_categories)
        expect(params[:spending_controls]).to have_key(:allowed_categories)
      end
    end

    it "applies a spending limit rather than issuing an open card" do
      stub_card(limit: 10_000)

      card = service.issue_card!(cardholder:, spending_limit_cents: 10_000)

      expect(card.spending_limit_cents).to eq(10_000)
      expect(card.spending_limit_interval).to eq("monthly")
    end

    it "defaults to a modest limit when none is given" do
      stub_card

      service.issue_card!(cardholder:)

      expect(Stripe::Issuing::Card).to have_received(:create).with(
        hash_including(
          spending_controls: hash_including(
            spending_limits: [{ amount: described_class::DEFAULT_SPENDING_LIMIT_CENTS, interval: "monthly" }]
          )
        ),
        anything
      )
    end

    # THE most important example here. A card Stripe returned without the allowlist is
    # an unrestricted commercial card in a minor's hands, so it is cancelled rather
    # than left live.
    it "cancels the card and raises when Stripe did not apply the controls" do
      stub_card(allowed: %w[hardware_stores])

      expect {
        service.issue_card!(cardholder:)
      }.to raise_error(described_class::ControlsNotApplied, /cancelled/i)

      expect(Stripe::Issuing::Card).to have_received(:update).with(
        "ic_test_1", { status: "canceled" }, anything
      )
    end

    it "refuses a cardholder who has not accepted the terms" do
      stub_card
      pending_holder = create(:venture_cardholder, :terms_pending, event: venture, user: minor)

      expect {
        service.issue_card!(cardholder: pending_holder)
      }.to raise_error(described_class::TermsNotAccepted)

      expect(Stripe::Issuing::Card).not_to have_received(:create)
    end

    # An acceptance of a superseded version does not carry forward.
    it "refuses a cardholder whose accepted terms are out of date" do
      stub_card
      stale = create(:venture_cardholder, :stale_terms, event: venture, user: minor)

      expect { service.issue_card!(cardholder: stale) }.to raise_error(described_class::TermsNotAccepted)
    end

    it "refuses a cardholder Stripe has not activated" do
      stub_card
      inactive = create(:venture_cardholder, :inactive, event: venture, user: minor)

      expect { service.issue_card!(cardholder: inactive) }.to raise_error(described_class::CardsNotAvailable)
    end
  end

  describe "#update_spending_limit!" do
    before { enable_cards! }

    it "pushes the new limit to Stripe and mirrors it back" do
      stub_card(limit: 50_000)
      cardholder = create(:venture_cardholder, event: venture, user: minor)
      card = create(:venture_card, venture_cardholder: cardholder, stripe_id: "ic_test_1")

      service.update_spending_limit!(card:, spending_limit_cents: 50_000)

      expect(card.reload.spending_limit_cents).to eq(50_000)
    end

    # Changing a limit must not be a way to quietly drop the category restrictions.
    it "resends the category allowlist alongside the new limit" do
      stub_card(limit: 50_000)
      cardholder = create(:venture_cardholder, event: venture, user: minor)
      card = create(:venture_card, venture_cardholder: cardholder, stripe_id: "ic_test_1")

      service.update_spending_limit!(card:, spending_limit_cents: 50_000)

      expect(Stripe::Issuing::Card).to have_received(:update).with(
        "ic_test_1",
        hash_including(
          spending_controls: hash_including(
            allowed_categories: Fuime::CardSpendPolicy.allowed_categories
          )
        ),
        anything
      )
    end
  end
end
