# frozen_string_literal: true

require "rails_helper"

# Fuime: the embedded management surface — the replacement for the Stripe
# Dashboard a guardian deliberately does not have.
#
# Every example here guards a rule that is invisible in the rendered page but
# decides whether one of Fuime's promises is real. See docs/fuime/EMBEDDED_CONNECT.md.
RSpec.describe Fuime::ConnectOnboardingService, "management sessions" do
  let(:venture) { create(:event) }
  let(:guardian) { create(:user, birthday: 40.years.ago.to_date) }
  let(:service) { described_class.new(event: venture, guardian:) }

  describe "MANAGEMENT_COMPONENTS" do
    subject(:components) { described_class::MANAGEMENT_COMPONENTS }

    it "gives the guardian every surface a Stripe Dashboard would be needed for" do
      # If one of these is dropped, a family silently acquires a reason to open
      # stripe.com — which they cannot do, because the account has no dashboard.
      expect(components.keys).to contain_exactly(
        :notification_banner, :account_management, :payouts, :documents
      )
    end

    it "does not let the payouts component move money" do
      # Enabling either of these puts a "Pay out now" button in front of the
      # guardian, routing money around Fuime::PayoutService's approval flow — the
      # only thing that makes "the teen asks, the adult decides" an audited record
      # rather than a story.
      expect(components.dig(:payouts, :features, :standard_payouts)).to be false
      expect(components.dig(:payouts, :features, :instant_payouts)).to be false
    end

    it "does not let the payouts component change the payout schedule" do
      # Accounts are created on a manual schedule precisely so nothing leaves
      # until an adult decides it should. A guardian switching to automatic daily
      # would drain the balance on a timer while every screen in Fuime kept
      # describing an approval gate that no longer existed.
      expect(components.dig(:payouts, :features, :edit_payout_schedule)).to be false
    end

    it "lets the guardian manage their own bank account" do
      # The one write the management surface must allow. Without it a guardian
      # whose bank details change has nowhere to fix them.
      expect(components.dig(:account_management, :features, :external_account_collection)).to be true
      expect(components.dig(:payouts, :features, :external_account_collection)).to be true
    end
  end

  describe "#management_session_client_secret" do
    it "refuses when the venture has no Stripe account" do
      # Unlike the onboarding secret, this must never create one. Otherwise a
      # stray GET on a management URL brings a real Stripe account into being for
      # a venture nobody ever onboarded.
      expect(Stripe::Account).not_to receive(:create)

      expect { service.management_session_client_secret }
        .to raise_error(described_class::AccountNotProvisioned)
    end

    it "mints a session against the account for the requested components" do
      create(:stripe_connected_account, event: venture, owner: guardian, stripe_id: "acct_manage_1")

      expect(Stripe::AccountSession).to receive(:create).with(
        hash_including(
          account: "acct_manage_1",
          components: described_class::MANAGEMENT_COMPONENTS
        ),
        hash_including(:api_key)
      ).and_return(Stripe::AccountSession.construct_from(client_secret: "cs_manage"))

      expect(service.management_session_client_secret).to eq("cs_manage")
    end
  end

  describe "#account_session_client_secret" do
    it "asks Stripe to collect a bank account during onboarding" do
      # Without this the guardian finishes "setup" having proved their identity
      # but with no payout destination — money the family can collect and never
      # receive.
      expect(
        described_class::ONBOARDING_COMPONENTS.dig(:account_onboarding, :features, :external_account_collection)
      ).to be true
    end
  end
end
