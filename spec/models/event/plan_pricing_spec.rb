# frozen_string_literal: true

require "rails_helper"

# Fuime: the pricing model as assertions (2026-08-21).
#
# The family plan used to undercut the free plan's rate, which meant Fuime paid
# its best customers to be customers. These pin the shape it was changed to:
# the plan sells UNLIMITED VENTURES and PAID FEATURES, at an unchanged rate.
RSpec.describe "Fuime pricing" do
  describe "the family plan's rate" do
    it "matches the free plan rather than discounting it" do
      expect(Event::Plan::Pro::REVENUE_FEE).to eq(Event::Plan::Free::REVENUE_FEE)
    end

    # The regression that matters: if someone lowers Pro again, a high-volume
    # family costs Fuime more in forgone fees than the subscription brings in.
    it "does not undercut the free plan" do
      expect(Event::Plan::Pro.new.revenue_fee).to be >= Event::Plan::Free.new.revenue_fee
    end

    it "still charges a monthly fee, which is where the plan's value now sits" do
      expect(Event::Plan::Pro.new.monthly_fee_cents).to be > 0
      expect(Event::Plan::Free.new.monthly_fee_cents).to eq(0)
    end
  end

  describe "the developer API as a paid feature" do
    it "is off on the free plan" do
      expect(Event::Plan::Free.new.api_keys_enabled?).to be false
    end

    it "is on for the family plan" do
      expect(Event::Plan::Pro.new.api_keys_enabled?).to be true
    end

    # Everything else the free plan had, it keeps. Gating is meant to be one
    # feature, not a quiet reduction of the free tier.
    it "takes nothing else away from the free plan" do
      expect(Event::Plan::Standard.new.features - Event::Plan::Free.new.features)
        .to contain_exactly("api_keys")
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
