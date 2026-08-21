# frozen_string_literal: true

require "rails_helper"

RSpec.describe EventPolicy, type: :policy do
  # FUIME-DISABLED surfaces.
  #
  # Fuime::DisabledModules blocks writes but deliberately leaves GETs alone, so
  # for Cards, Donations and Google Workspace the nav item stayed visible and
  # the overview page rendered in full — every CTA on it bouncing off the write
  # filter with "That feature isn't available on Fuime." Standard is the default
  # plan for new organizations (EventService::Create) and it enables cards,
  # donations, google_workspace and promotions, so every Fuime business saw all
  # four.
  #
  # These predicates gate both the nav entry (EventsHelper::NAV_ITEMS) and the
  # controller action's `authorize`, so pinning them false closes the page and
  # the link together.
  #
  # Each example uses a manager on an approved Standard-plan organization —
  # precisely the user upstream grants access to. A weaker subject would pass
  # for the wrong reason.
  describe "FUIME-DISABLED overview pages" do
    let(:manager) { create(:user) }
    # `approved` is the initial AASM state on Event, so a plain create is
    # already approved — which is what card_overview?/donation_overview?
    # required upstream.
    let(:event) { create(:event, plan_type: Event::Plan::Standard) }

    before { create(:organizer_position, event:, user: manager, role: :manager) }

    subject(:policy) { described_class.new(manager, event) }

    it "denies the Donations overview even though the plan enables donations" do
      expect(event.plan.donations_enabled?).to eq(true)
      expect(policy.donation_overview?).to eq(false)
    end

    it "denies the Google Workspace overview even though the plan enables it" do
      expect(event.plan.google_workspace_enabled?).to eq(true)
      expect(policy.g_suite_overview?).to eq(false)
    end

    it "denies the Perks page even though the plan enables promotions" do
      expect(event.plan.promotions_enabled?).to eq(true)
      expect(policy.promotions?).to eq(false)
    end

    # The termination PDF generates a fiscal-sponsorship termination agreement
    # naming The Hack Foundation as the counterparty. Auditor-gated upstream,
    # so an auditor is the subject that would have been allowed.
    it "denies the termination agreement to an auditor" do
      auditor_policy = described_class.new(create(:user, :make_auditor), event)

      expect(auditor_policy.termination?).to eq(false)
    end

    # Admins are exempt from Fuime::DisabledModules, but these pages are not
    # about privilege — the products do not exist on Fuime — so the denial must
    # hold regardless of who is asking.
    it "denies all of them to an admin" do
      admin_policy = described_class.new(create(:user, :make_admin), event)

      expect(admin_policy.donation_overview?).to eq(false)
      expect(admin_policy.g_suite_overview?).to eq(false)
      expect(admin_policy.promotions?).to eq(false)
      expect(admin_policy.termination?).to eq(false)
    end

    # The public donation *page* is a separate predicate. Disabling the org's
    # donation overview must not silently take it with it.
    it "does not disable unrelated predicates on the same policy" do
      expect(policy.show?).to eq(true)
      expect(policy.reimbursements?).to eq(true)
    end
  end

  # Cards were on the list above until test-mode issuing was turned back on.
  # These pin the upstream conditions the stub used to swallow, so the page
  # cannot quietly come back for organizations that should not have it.
  describe "#card_overview? (re-enabled for test-mode issuing)" do
    let(:manager) { create(:user) }
    let(:event) { create(:event, plan_type: Event::Plan::Standard) }

    before { create(:organizer_position, event:, user: manager, role: :manager) }

    it "allows a manager on an approved organization whose plan enables cards" do
      expect(event.plan.cards_enabled?).to eq(true)
      expect(described_class.new(manager, event).card_overview?).to eq(true)
    end

    # Terminated is the only plan that switches cards off, which makes it the
    # only subject that can prove the plan condition is still consulted.
    it "denies it when the plan does not enable cards" do
      terminated = create(:event, plan_type: Event::Plan::Terminated)
      create(:organizer_position, event: terminated, user: manager, role: :manager)

      expect(terminated.plan.cards_enabled?).to eq(false)
      expect(described_class.new(manager, terminated).card_overview?).to eq(false)
    end

    # Not simply "a stranger": `show?` is satisfied by transparency, so on a
    # public organization an outsider legitimately sees the card list upstream.
    # A private organization is what proves `show?` is still being consulted.
    it "denies it to an outsider on a private organization" do
      private_event = create(:event, plan_type: Event::Plan::Standard, is_public: false)

      expect(described_class.new(create(:user), private_event).card_overview?).to eq(false)
    end
  end

  describe "#sub_organizations?" do
    # Fuime: `publishes_ledger` as well as `is_public`.
    #
    # This block's subject is which CHILDREN a viewer may see, and that logic is
    # unchanged. What changed is the gate on the page itself: `sub_organizations?`
    # aliases `async_sub_organization_balance?`, so a signed-out visitor reading it
    # gets each sub-venture's balance — which on a school programme is a per-student
    # figure. It now needs the parent to have opted into publishing its ledger, not
    # merely to have a storefront. See AddPublishesLedgerToEvents.
    let(:event) { create(:event, is_public: true, publishes_ledger: true) }

    subject { described_class.new(nil, event).sub_organizations? }

    context "when the parent has not opted into publishing its ledger" do
      let(:event) { create(:event, is_public: true, publishes_ledger: false) }

      before { create(:event, parent: event, is_public: true) }

      it { is_expected.to eq(false) }
    end

    context "when the only sub-organization is private" do
      before { create(:event, parent: event, is_public: false) }

      it { is_expected.to eq(false) }
    end

    context "when the only sub-organization is hidden" do
      before { create(:event, parent: event, is_public: true, hidden_at: Time.current) }

      it { is_expected.to eq(false) }
    end

    context "when a transparent sub-organization exists" do
      before { create(:event, parent: event, is_public: true) }

      it { is_expected.to eq(true) }
    end

    context "when the only sub-organization has been deleted" do
      before { create(:event, parent: event, is_public: true).destroy }

      it { is_expected.to eq(false) }
    end

    context "as an organizer of an organization whose roster is entirely private" do
      let(:organizer) { create(:user) }

      subject { described_class.new(organizer, event).sub_organizations? }

      before do
        create(:organizer_position, user: organizer, event:)
        create(:event, parent: event, is_public: false)
      end

      it { is_expected.to eq(true) }
    end
  end

  describe "#create_sub_organization?" do
    let(:event) { create(:event) }
    let(:user) { create(:user) }

    subject { described_class.new(user, event).create_sub_organization? }

    before do
      allow(User).to receive(:system_user).and_return(create(:user, email: User::SYSTEM_USER_EMAIL))
    end

    context "when sub-organizations are not enabled on the event" do
      before { create(:organizer_position, user:, event:, role: :manager) }

      it { is_expected.to eq(false) }
    end

    context "when sub-organizations are enabled" do
      before { event.config.update!(subevent_plan: Event::Plan::Standard.name) }

      context "as a manager" do
        before { create(:organizer_position, user:, event:, role: :manager) }

        it { is_expected.to eq(true) }
      end

      context "as a member" do
        before { create(:organizer_position, user:, event:, role: :member) }

        it "is denied by default" do
          is_expected.to eq(false)
        end

        it "is allowed when the member_subevent_creation flag is enabled for the event" do
          Flipper.enable(:member_subevent_creation, event)

          is_expected.to eq(true)
        end
      end

      context "as a reader" do
        before do
          create(:organizer_position, user:, event:, role: :reader)
          Flipper.enable(:member_subevent_creation, event)
        end

        it "is denied even when the flag is enabled" do
          is_expected.to eq(false)
        end
      end

      context "as an admin without a position" do
        let(:user) { create(:user, :make_admin) }

        it { is_expected.to eq(true) }
      end

      context "as a manager of an ancestor org creating on a subevent" do
        let(:subevent) { create(:event, parent: event) }

        subject { described_class.new(user, subevent).create_sub_organization? }

        before do
          create(:organizer_position, user:, event:, role: :manager)
          subevent.config.update!(subevent_plan: Event::Plan::Standard.name)
        end

        it "is allowed without the flag" do
          is_expected.to eq(true)
        end
      end
    end
  end

  describe "#ledger?" do
    # Fuime: these cover the rewritten ledger, which is closed by default since
    # 2026-08-21 — it rendered an empty page for a venture that had taken money.
    # The feature is PAUSED, not deleted (Rule 2), so its specs still run, with
    # the switch in the state they describe. The closure itself is asserted in
    # spec/policies/ledger_kill_switch_spec.rb.
    around do |example|
      previous = ENV["FUIME_NEW_LEDGER"]
      ENV["FUIME_NEW_LEDGER"] = "true"
      example.run
    ensure
      ENV["FUIME_NEW_LEDGER"] = previous
    end

    let(:event) { create(:event) }
    let(:user) { create(:user) }

    subject { described_class.new(user, event).ledger? }

    context "as a reader" do
      before { create(:organizer_position, user:, event:, role: :reader) }

      it "is denied without either ledger flag" do
        is_expected.to eq(false)
      end

      it "is allowed when the event has new_ledger_2026_06_30 enabled" do
        Flipper.enable(:new_ledger_2026_06_30, event)

        is_expected.to eq(true)
      end

      it "is allowed when the user has opted into new_ledger_2026_07_17" do
        Flipper.enable_actor(:new_ledger_2026_07_17, user)

        is_expected.to eq(true)
      end
    end

    context "as a non-member with the opt-in flag enabled" do
      before { Flipper.enable_actor(:new_ledger_2026_07_17, user) }

      it "is denied" do
        is_expected.to eq(false)
      end
    end

    context "as an auditor" do
      let(:user) { create(:user, :make_auditor) }

      it "is allowed without either flag" do
        is_expected.to eq(true)
      end
    end
  end
end
