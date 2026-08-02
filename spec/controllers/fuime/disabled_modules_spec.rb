# frozen_string_literal: true

require "rails_helper"

# Fuime: modules Fuime doesn't offer must be blocked at the request level, not
# merely hidden from the navigation.
# See docs/fuime/PRODUCTION_READINESS.md §2.3.
RSpec.describe AchTransfersController, type: :controller do
  include SessionSupport

  let(:event) { create(:event) }
  let(:adult) { create(:user, birthday: 30.years.ago.to_date) }

  describe "outbound money movement" do
    before do
      create(:organizer_position, user: adult, event:, role: :manager)
      create_session(adult, verified: true)
    end

    it "blocks a member from reaching ACH transfers by direct URL" do
      get :new, params: { event_id: event.id }

      expect(response).not_to have_http_status(:ok)
    end
  end

  describe "the disabled list" do
    subject(:disabled) { Fuime::DisabledModules::DISABLED_CONTROLLER_PREFIXES }

    it "covers every outbound money path" do
      expect(disabled).to include("ach_transfers", "increase_checks", "wires", "disbursements")
    end

    it "covers nonprofit fundraising" do
      expect(disabled).to include("donations", "card_grants")
    end

    it "covers card issuing" do
      expect(disabled).to include("stripe_cards")
    end

    # Fuime's own money-in and record-keeping must stay reachable.
    it "does NOT disable invoices, receipts, comments, or the ledger" do
      expect(disabled).not_to include("invoices", "receipts", "comments", "canonical_transactions")
    end

    # A typo here silently disables nothing, so assert each prefix resolves to
    # a real controller or namespace on disk.
    it "only lists prefixes that exist" do
      missing = disabled.reject do |prefix|
        Rails.root.join("app/controllers/#{prefix}_controller.rb").exist? ||
          Rails.root.join("app/controllers/#{prefix}").directory?
      end

      expect(missing).to be_empty, "unknown controller prefixes: #{missing.join(', ')}"
    end
  end

  describe "the guardianship allowlist" do
    subject(:allowed) { Fuime::GuardianshipEnforcement::ALLOWED_CONTROLLER_PATHS }

    # An entry naming a controller that isn't routed is dead weight that reads
    # as protection. Three of these shipped ("sessions",
    # "active_storage/blobs", "active_storage/representations") and matched
    # nothing — this is the check that finds them.
    it "only lists controllers that are actually routed" do
      routed = Rails.application.routes.routes.filter_map { |r| r.defaults[:controller] }.uniq

      expect(allowed - routed).to be_empty
    end

    # The allowlist is the escape hatch from the platform's central legal
    # control, so it must stay small and deliberate.
    it "does not include anything a parked teen doesn't need" do
      expect(allowed).not_to include("users/wrapped", "users/first", "events")
    end

    it "lets a parked teen reach the invite page and their own settings" do
      expect(allowed).to include("guardianships", "users", "logins")
    end
  end
end
