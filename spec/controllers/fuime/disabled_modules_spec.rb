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
    # `blocked_prefixes`, not DISABLED_CONTROLLER_PREFIXES. What is turned off is
    # no longer one constant: the custody modules moved behind
    # Fuime::Features.sponsor_banking? so that a sponsor bank re-enables them by
    # configuration rather than by editing this concern (CLAUDE.md Rule 2).
    # Reading the raw constant would assert where an entry is filed; this asserts
    # what a teenager typing a URL actually gets, which is what these tests were
    # always about.
    subject(:disabled) { Fuime::DisabledModules.blocked_prefixes }

    it "covers every outbound money path" do
      expect(disabled).to include("ach_transfers", "increase_checks", "wires", "disbursements")
    end

    it "covers nonprofit fundraising" do
      expect(disabled).to include("donations", "card_grants")
    end

    # Card issuing was here until test-mode issuing was turned back on. The
    # HTML surface is deliberately open now; the v4 API is not (see below), and
    # Emburse — a dead upstream integration Fuime never had — stays blocked.
    #
    # Specs run against Stripe TEST keys, so this is the test-mode arm of
    # Fuime::Features.card_issuing_permitted? — a card here spends nothing real.
    # The live-mode arm, where these same prefixes ARE blocked, is asserted below.
    it "no longer covers HTML card issuing, but still covers Emburse" do
      expect(disabled).not_to include("stripe_cards", "stripe_cardholders")
      expect(disabled).to include("emburse_cards", "emburse_card_requests")
    end

    # The promise the 2026-08-02 card decision made in a comment and nothing
    # enforced: "blocked again the moment this fork points at anything but test
    # keys." Issuing spends from a platform balance Fuime funds itself, so in live
    # mode without a sponsor bank it is uncollateralised credit to a minor.
    it "covers card issuing once the fork points at live Stripe keys" do
      allow(StripeService).to receive(:live?).and_return(true)

      live_blocked = Fuime::DisabledModules.blocked_prefixes

      expect(live_blocked).to include("stripe_cards", "stripe_cardholders", "fuime/cards")
    end

    # The other half of the flag's contract: everything gated on sponsor banking
    # comes back when a sponsor bank exists, without a code change.
    it "releases the custody modules when sponsor banking is enabled" do
      allow(Fuime::Features).to receive(:sponsor_banking?).and_return(true)

      expect(Fuime::DisabledModules.blocked_prefixes)
        .not_to include("ach_transfers", "wires", "disbursements", "check_deposits")
    end

    # ...but never the modules that are off for product reasons rather than
    # licensing ones. No partner bank makes Fuime a fiscal sponsor.
    it "keeps nonprofit fundraising blocked even with sponsor banking enabled" do
      allow(Fuime::Features).to receive(:sponsor_banking?).and_return(true)

      expect(Fuime::DisabledModules.blocked_prefixes)
        .to include("donations", "card_grants", "g_suite")
    end

    # Fuime's own money-in and record-keeping must stay reachable.
    it "does NOT disable invoices, receipts, comments, or the ledger" do
      expect(disabled).not_to include("invoices", "receipts", "comments", "canonical_transactions")
    end

    # Reimbursements are "hide nav", not disable (FUIME_HACKATHON_SPEC §WON'T).
    # Blocking them silently no-opped report PATCHes — success responses that
    # changed nothing.
    it "does NOT disable reimbursements" do
      expect(disabled).not_to include("reimbursement", "reimbursements")
    end

    # The v4 API exposes the same capabilities under a different path. Blocking
    # only the HTML controller leaves the API as an open back door.
    it "disables the API twin of every disabled HTML module that has one" do
      api_controllers = Dir.glob(Rails.root.join("app/controllers/api/v4/*_controller.rb"))
                           .map { |f| "api/v4/#{File.basename(f, '_controller.rb')}" }

      unguarded = api_controllers.reject { |api| disabled.include?(api) }.select do |api|
        disabled.include?(api.sub("api/v4/", ""))
      end

      expect(unguarded).to be_empty,
                           "API endpoints left open while their HTML module is disabled: #{unguarded.join(', ')}"
    end

    # A typo here silently disables nothing, so assert each prefix resolves to
    # a real controller or namespace on disk.
    #
    # Across ALL lists, not just the currently-blocked ones: a typo in the
    # sponsor-banking list would lie dormant and only fail open on the day someone
    # turns custody on, which is the worst possible day to discover it.
    it "only lists prefixes that exist" do
      missing = Fuime::DisabledModules.all_gated_prefixes.reject do |prefix|
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
