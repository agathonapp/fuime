# frozen_string_literal: true

require "rails_helper"

# Fuime: policy resolution through the event tree, for the school structure
# (School Event -> Student sub org Event, grants on the sub org).
#
# The case that matters most is "inherits through an empty local setting":
# CardGrant's before_validation :create_card_grant_setting manufactures an EMPTY
# CardGrantSetting on the grant's own event, so every grant has a local setting
# whether anyone configured one or not. If an empty level were treated as a
# constraint, that automatic row would zero out the school's allowlist and the
# card would be unrestricted — failing open, which is the exact opposite of what
# a school is buying.
RSpec.describe CardGrant, type: :model do
  describe "inherited spending policy" do
    # transfer_money runs DisbursementService::Create, which needs a funded source
    # event. Stubbed here for the same reason as card_grant_spec.rb.
    before do
      allow_any_instance_of(described_class).to receive(:transfer_money)
    end

    let(:school) { create(:event) }
    let(:sub_org) { create(:event, parent: school) }

    def grant_on(event, **attrs)
      create(:card_grant, event:, **attrs)
    end

    it "reaches a grant on a sub org from policy set only on the school" do
      create(:card_grant_setting, event: school, category_lock: "hardware_stores, wholesale_clubs")

      grant = grant_on(sub_org, category_lock: [])

      expect(grant.allowed_categories).to contain_exactly("hardware_stores", "wholesale_clubs")
    end

    it "inherits through the empty setting auto-created on the grant's own event" do
      create(:card_grant_setting, event: school, category_lock: "hardware_stores")

      grant = grant_on(sub_org, category_lock: [])

      # The local setting exists and is empty; it must read as "inherit", not
      # "allow nothing", and must not widen to unrestricted either.
      expect(grant.setting.event).to eq(sub_org)
      expect(grant.setting.category_lock).to be_blank
      expect(grant.allowed_categories).to eq(["hardware_stores"])
    end

    it "lets a grant narrow the school's allowlist" do
      create(:card_grant_setting, event: school, category_lock: "hardware_stores, wholesale_clubs")

      grant = grant_on(sub_org, category_lock: ["hardware_stores"])

      expect(grant.allowed_categories).to eq(["hardware_stores"])
    end

    it "does not let a grant add a category the school never allowed" do
      create(:card_grant_setting, event: school, category_lock: "hardware_stores")

      grant = grant_on(sub_org, category_lock: ["betting_casino_gambling"])

      # Upstream's union returned both. Intersecting is what makes "tighten,
      # never loosen" true; nothing survives, so nothing is permitted.
      expect(grant.allowed_categories).to be_empty
      expect(grant.allowed_categories).not_to include("betting_casino_gambling")
    end

    it "accumulates bans down the tree so a school ban cannot be undone" do
      create(:card_grant_setting, event: school, banned_categories: "automated_cash_disburse")

      grant = grant_on(sub_org, banned_categories: ["digital_goods_games"])

      expect(grant.disallowed_categories)
        .to contain_exactly("automated_cash_disburse", "digital_goods_games")
    end

    it "resolves through more than one level of ancestry" do
      create(:card_grant_setting, event: school, category_lock: "hardware_stores, wholesale_clubs")
      cohort = create(:event, parent: school)
      create(:card_grant_setting, event: cohort, category_lock: "hardware_stores")
      venture = create(:event, parent: cohort)

      grant = grant_on(venture, category_lock: [])

      expect(grant.allowed_categories).to eq(["hardware_stores"])
    end

    it "leaves an unconfigured tree unrestricted, as upstream behaves today" do
      grant = grant_on(sub_org, category_lock: [])

      expect(grant.allowed_categories).to be_empty
    end

    describe "contradictory policy" do
      it "reports a conflict when the levels share nothing" do
        create(:card_grant_setting, event: school, category_lock: "hardware_stores")

        grant = grant_on(sub_org, category_lock: ["betting_casino_gambling"])

        expect(grant.allowed_categories).to be_empty
        expect(grant.spending_policy_conflict?).to be true
      end

      it "does not report a conflict when nothing is configured" do
        grant = grant_on(sub_org, category_lock: [])

        # Same empty allowlist, opposite meaning: unrestricted by design, which is
        # upstream's behaviour and must not start raising.
        expect(grant.allowed_categories).to be_empty
        expect(grant.spending_policy_conflict?).to be false
      end

      it "refuses to activate a card rather than shipping an empty allowlist" do
        create(:card_grant_setting, event: school, category_lock: "hardware_stores")
        grant = grant_on(sub_org, category_lock: ["betting_casino_gambling"])
        grant.update_column(:stripe_card_id, nil)

        expect { grant.create_stripe_card("127.0.0.1") }
          .to raise_error(Errors::CardGrantPolicyConflictError, /no restrictions at all/)
      end
    end

    it "takes the nearest level that sets a keyword lock" do
      create(:card_grant_setting, event: school, keyword_lock: "school-supply")

      grant = grant_on(sub_org, keyword_lock: nil)

      expect(grant.keyword_lock).to eq("school-supply")
    end
  end
end
