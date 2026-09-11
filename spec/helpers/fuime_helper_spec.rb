# frozen_string_literal: true

require "rails_helper"

RSpec.describe FuimeHelper, type: :helper do
  describe "#fuime_legal_seller" do
    it "is Ninth Street Labs, LLC and not Fuime LLC" do
      expect(helper.fuime_legal_seller).to eq("Ninth Street Labs, LLC")
      expect(helper.fuime_legal_seller).not_to include("Fuime LLC")
    end
  end

  describe "#fuime_status_line" do
    it "names Ninth Street Labs, LLC as seller without calling the brand Fuime LLC" do
      expect(helper.fuime_status_line).to eq(
        "Private beta · live payments. Ninth Street Labs, LLC (Fuime) is the seller of record."
      )
      expect(helper.fuime_status_line).not_to include("Fuime LLC")
    end
  end

  describe "#fuime_footer_ownership" do
    it "states seller, legal payee, and destination approval" do
      expect(helper.fuime_footer_ownership).to include("Ninth Street Labs, LLC, doing business as Fuime")
      expect(helper.fuime_footer_ownership).to include("legal payee")
      expect(helper.fuime_footer_ownership).to include("approve the destination before the first payout")
      expect(helper.fuime_footer_ownership).not_to include("Venture accounts are opened")
    end
  end

  # The banner is leftover chrome for a deploy whose Stripe keys are not live.
  # Getting the condition wrong is silent in both directions: too eager and it
  # undercuts a live product, too shy and a storefront has no standing status.
  describe "#show_test_mode_banner?" do
    def in_env(name)
      allow(Rails).to receive(:env).and_return(ActiveSupport::EnvironmentInquirer.new(name))
      yield
    end

    it "is hidden once Stripe is live — the banner must not outlive its truth" do
      allow(StripeService).to receive(:live?).and_return(true)

      in_env("production") do
        expect(helper.show_test_mode_banner?).to be false
      end
    end

    it "is shown on a deployed environment running test-mode Stripe" do
      allow(StripeService).to receive(:live?).and_return(false)

      in_env("production") do
        expect(helper.show_test_mode_banner?).to be true
      end
    end

    it "is shown on staging too" do
      allow(StripeService).to receive(:live?).and_return(false)

      in_env("staging") do
        expect(helper.show_test_mode_banner?).to be true
      end
    end

    # Test mode is the obvious default locally; the banner would be noise in
    # development and would have to be asserted around in every view spec.
    %w[development test].each do |env|
      it "is hidden in #{env}" do
        allow(StripeService).to receive(:live?).and_return(false)

        in_env(env) do
          expect(helper.show_test_mode_banner?).to be false
        end
      end
    end
  end
end
