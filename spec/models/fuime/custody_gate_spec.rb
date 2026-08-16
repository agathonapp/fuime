# frozen_string_literal: true

require "rails_helper"

# Fuime: the model-level half of the custody gate.
#
# Fuime::DisabledModules stops a request reaching a custody feature. That is the
# front door, and it is not enough on its own — a record that already exists
# keeps behaving however its model says it behaves, and the two places that
# matters are both about spending money Fuime would have to advance:
#
#   * Event#can_front_balance? — whether unsettled money counts as spendable.
#   * StripeCard#balance_available — whether an existing card approves a swipe.
#
# Blocking the controllers would have left both of those answering yes.
#
# See docs/fuime/MOR_MIGRATION_PLAN.md §1 C2 and C3.
RSpec.describe "custody gate" do
  describe "Event#can_front_balance?" do
    # The column is what upstream uses to decide fronting per-org. Fuime keeps it
    # (Rule 2) and makes it inert while custody is off, so these two examples are
    # the whole contract: the column is ignored below, honoured above.
    it "is false while sponsor banking is off, even for a venture whose column says true" do
      event = create(:event, can_front_balance: true)

      expect(event.can_front_balance?).to be(false)
    end

    it "honours the column once sponsor banking is on", :sponsor_banking do
      expect(create(:event, can_front_balance: true).can_front_balance?).to be(true)
      expect(create(:event, can_front_balance: false).can_front_balance?).to be(false)
    end

    # The reason the gate exists rather than the mechanism. Fronted money is money
    # Fuime has advanced against sales Stripe has not released; counting it as
    # spendable is what lets a teenager spend funds that do not exist yet.
    it "keeps fronted money out of the spendable balance" do
      event = create(:event, can_front_balance: true)
      create(:canonical_pending_transaction, amount_cents: 5_000, event:, fronted: true)

      expect(event.balance_v2_cents).to eq(0)
    end

    it "counts fronted money as spendable once sponsor banking is on", :sponsor_banking do
      event = create(:event, can_front_balance: true)
      create(:canonical_pending_transaction, amount_cents: 5_000, event:, fronted: true)

      expect(event.balance_v2_cents).to eq(5_000)
    end

    # New ventures must not arrive pre-authorised for credit. Upstream's default
    # was TRUE, so without the migration every venture would switch fronting on
    # the moment a sponsor bank flipped the flag — see the migration's header.
    it "defaults to off for a newly created venture" do
      expect(create(:event).can_front_balance).to be(false)
    end
  end

  describe "StripeCard#balance_available" do
    let(:event) { create(:event) }
    let(:card)  { create(:stripe_card, :with_stripe_id, event:) }

    before { create(:canonical_transaction, amount_cents: 10_000, event:) }

    # Specs run against test keys, which is the carve-out that keeps the Issuing
    # demo working. Asserted so that a change to card_issuing_permitted? cannot
    # quietly zero the demo instead of the live path.
    it "reports the ledger balance in test mode, leaving the demo intact" do
      expect(card.balance_available).to eq(event.balance_available_v2_cents)
      expect(card.balance_available).to be > 0
    end

    # The one that matters. A swipe is funded from Fuime's own platform Issuing
    # balance; with no sponsor bank behind it, approving one extends
    # uncollateralised credit to a minor's business.
    it "is zero in live mode without a sponsor bank, so an existing card declines" do
      allow(StripeService).to receive(:live?).and_return(true)

      expect(card.balance_available).to eq(0)
    end

    it "reports the ledger balance in live mode once sponsor banking exists", :sponsor_banking do
      allow(StripeService).to receive(:live?).and_return(true)

      expect(card.balance_available).to eq(event.balance_available_v2_cents)
    end

    # Zero rather than raising, deliberately. This feeds authorisation decisions,
    # and Stripe reads an exception or a timeout as its own decision to make — a
    # gate that fails open at the terminal is worse than no gate.
    it "declines by returning zero rather than raising" do
      allow(StripeService).to receive(:live?).and_return(true)

      expect { card.balance_available }.not_to raise_error
    end
  end
end
