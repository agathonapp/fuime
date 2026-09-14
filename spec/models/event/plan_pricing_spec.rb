# frozen_string_literal: true

require "rails_helper"

# Fuime: the pricing model as assertions.
#
# ── 2026-09-14: one flat price ───────────────────────────────────────────────
#
# 7% + a $19.99 family plan became 5% + 50¢, flat, with nothing gated and no
# monthly fee. Anything outside the standard rate is a sales conversation.
#
# What these pin is that the price stays ONE number. The previous version of
# this file existed because the family plan had quietly grown a cheaper rate
# that paid Fuime's best customers to be customers; the failure mode now is the
# opposite and simpler — a second tier reappearing, or copy quoting the
# percentage without the floor.
RSpec.describe "Fuime pricing" do
  describe "the one rate" do
    it "is 5% plus a 50¢ floor" do
      expect(Event::Plan::Free::REVENUE_FEE).to eq(0.05)
      expect(Event::Plan::MINIMUM_FEE_CENTS).to eq(50)
    end

    it "charges no monthly fee" do
      expect(Event::Plan::Free.new.monthly_fee_cents).to eq(0)
    end

    # A percentage alone is not the price. Under merchant-of-record a $5 sale
    # pays the 50¢ floor — 10%, not 5% — so copy quoting "5%" on its own
    # describes a price Fuime does not charge (L8).
    it "states the floor alongside the rate wherever it is advertised" do
      expect(Event::Plan.fuime_price_label).to eq("5% + $0.50")
      expect(Event::Plan::Free.new.description).to include(Event::Plan.fuime_price_label)
      expect(Event::Plan::Free.new.label).to include(Event::Plan.fuime_price_label)
    end

    it "points anyone outside the standard rate at a conversation, not a tier" do
      expect(Event::Plan::Free.new.description).to match(/custom pricing/i)
    end

    # The regression this file exists to catch: a second tier reappearing.
    it "sells no upgrade, because there is nothing to upgrade to" do
      expect(Event::Plan::Free.new.description).not_to match(/family plan|\$19\.99|per month|\/mo/i)
    end
  end

  describe "the retired family plan" do
    it "is retired and never offered" do
      expect(Event::Plan::Pro.new).to be_retired
      expect(Event::Plan::Pro.selectable?).to be false
    end

    it "charges the same rate as everyone else, so nobody on it is worse off" do
      expect(Event::Plan::Pro.new.revenue_fee).to eq(Event::Plan::Free.new.revenue_fee)
    end

    # Deliberately still reports $19.99. That is what STRIPE is billing these
    # families until somebody cancels; a plan object reporting $0 while a
    # parent's card is charged would make the app lie about a real debit.
    it "still reports the monthly fee Stripe is actually charging" do
      expect(Event::Plan::Pro.new.monthly_fee_cents).to eq(1999)
    end

    it "tells the family it buys nothing and should be cancelled" do
      expect(Event::Plan::Pro.new.description).to match(/retired/i)
      expect(Event::Plan::Pro.new.description).to match(/cancel/i)
    end
  end

  describe "features" do
    it "gates nothing — the developer API is included" do
      expect(Event::Plan::Free.new.api_keys_enabled?).to be true
    end

    it "gives the standard plan and the free plan exactly the same features" do
      expect(Event::Plan::Standard.new.features - Event::Plan::Free.new.features).to be_empty
    end

    # The short list of things that must NEVER be gated: withholding them
    # strands a founder's own money, or removes the guardian control the whole
    # model rests on (L2).
    it "leaves the founder's own money and oversight ungated" do
      free = Event::Plan::Free.new

      expect(free.features).to include("invoices")
      expect(Event::Plan.available_features).not_to include("payouts", "ledger", "taxes", "guardian_visibility")
    end
  end
end
