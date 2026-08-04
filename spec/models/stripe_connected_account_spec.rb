# frozen_string_literal: true

require "rails_helper"

# Fuime: the guardian-owned Stripe account for a venture.
#
# The value of these examples is concentrated in two places, and both are
# judgement calls that a future refactor could plausibly "fix" into a bug:
#
#   1. Outstanding requirements do NOT block payments. Stripe leaves requirements
#      on accounts it is still happy to charge for; treating that as an outage
#      would take a working venture's storefront down.
#   2. Charging and paying out are separate questions. Collapsing them produces
#      the one failure a fifteen-year-old cannot debug — money arrives, then
#      appears stuck.
RSpec.describe StripeConnectedAccount, type: :model do
  describe "#status" do
    it "is :not_started before the Stripe account exists" do
      account = build(:stripe_connected_account, stripe_id: nil)

      expect(account.status).to eq(:not_started)
      expect(account.ready_for_payments?).to be false
    end

    it "is :incomplete when the guardian started but did not submit" do
      expect(build(:stripe_connected_account, :incomplete).status).to eq(:incomplete)
    end

    it "is :verifying when submitted but not yet chargeable" do
      account = build(:stripe_connected_account, :verifying)

      expect(account.status).to eq(:verifying)
      expect(account.onboarding_submitted?).to be true
      # The distinction the return path depends on: they finished their part, and
      # the venture still cannot take money.
      expect(account.ready_for_payments?).to be false
    end

    it "is :ready when Stripe reports charges enabled and the capability active" do
      account = build(:stripe_connected_account, :ready)

      expect(account.status).to eq(:ready)
      expect(account.ready_for_payments?).to be true
      expect(account.ready_for_payouts?).to be true
    end

    it "is :disabled when Stripe gives a disabled_reason" do
      account = build(:stripe_connected_account, :disabled)

      expect(account.status).to eq(:disabled)
      expect(account.ready_for_payments?).to be false
      expect(account.status_description).to include("paused")
    end
  end

  # (1) above.
  describe "outstanding requirements on a working account" do
    let(:account) { build(:stripe_connected_account, :ready_action_needed) }

    it "still accepts payments" do
      expect(account.ready_for_payments?).to be true
    end

    it "reports the requirement without describing the venture as blocked" do
      expect(account.requirements_outstanding?).to be true
      expect(account.status).to eq(:ready_action_needed)
      expect(account.status_description).to include("can accept payments")
    end
  end

  # (2) above.
  describe "charging versus paying out" do
    let(:account) { build(:stripe_connected_account, :ready_no_payouts) }

    it "separates the two so the UI can say which one is outstanding" do
      expect(account.ready_for_payments?).to be true
      expect(account.ready_for_payouts?).to be false
      expect(account.status).to eq(:ready_no_payouts)
    end
  end

  # A capability that has not gone active must not be read as "ready" just
  # because charges_enabled happens to be true.
  describe "capability gating" do
    it "is not ready when card_payments is pending despite charges_enabled" do
      account = build(:stripe_connected_account, :ready,
                      capabilities: { "card_payments" => "pending", "transfers" => "active" })

      expect(account.ready_for_payments?).to be false
    end
  end

  describe "#sync_from_stripe!" do
    let(:account) { create(:stripe_connected_account, :incomplete) }

    # A Stripe::Account double shaped like the real object: nested fields respond
    # as objects, not hashes, which is exactly what tripped the naive `.to_h`.
    def stripe_account(overrides = {})
      Stripe::Account.construct_from({
        id: account.stripe_id,
        charges_enabled: true,
        payouts_enabled: true,
        details_submitted: true,
        livemode: false,
        requirements: { currently_due: [], disabled_reason: nil },
        capabilities: { card_payments: "active", transfers: "active" }
      }.deep_merge(overrides))
    end

    it "mirrors Stripe's answer onto the row" do
      account.sync_from_stripe!(stripe_account)

      expect(account.reload).to have_attributes(
        charges_enabled: true,
        payouts_enabled: true,
        details_submitted: true
      )
      expect(account.card_payments_capability).to eq("active")
      expect(account.ready_for_payments?).to be true
      expect(account.stripe_synced_at).to be_present
    end

    it "records disabled_reason out of the requirements object" do
      account.sync_from_stripe!(
        stripe_account(charges_enabled: false, requirements: { disabled_reason: "under_review" })
      )

      expect(account.reload.disabled_reason).to eq("under_review")
      expect(account.status).to eq(:disabled)
    end

    # Fuime runs test mode even in production, so a live account and a test one
    # must be distinguishable in the database rather than inferred from Rails.env.
    it "mirrors livemode" do
      account.sync_from_stripe!(stripe_account(livemode: true))

      expect(account.reload.livemode).to be true
    end

    # Set once, on first completed submission — a later re-verification cycle
    # must not rewrite the date the guardian originally finished.
    it "does not overwrite onboarded_at on a later sync" do
      account.sync_from_stripe!(stripe_account)
      first = account.reload.onboarded_at
      expect(first).to be_present

      travel 1.day do
        account.sync_from_stripe!(stripe_account)
      end

      expect(account.reload.onboarded_at).to be_within(1.second).of(first)
    end

    it "tolerates an account with no requirements or capabilities yet" do
      bare = Stripe::Account.construct_from(
        id: account.stripe_id, charges_enabled: false,
        payouts_enabled: false, details_submitted: false, livemode: false
      )

      expect { account.sync_from_stripe!(bare) }.not_to raise_error
      expect(account.reload.requirements).to eq({})
      expect(account.capabilities).to eq({})
    end
  end

  describe "one account per venture" do
    # The commingling guarantee. Two ventures sharing a Stripe account would
    # recombine their revenue, which is the property the whole migration away
    # from the pooled account exists to remove.
    it "rejects a second account for the same event" do
      first = create(:stripe_connected_account)

      expect { create(:stripe_connected_account, event: first.event) }
        .to raise_error(ActiveRecord::RecordNotUnique)
    end
  end
end
