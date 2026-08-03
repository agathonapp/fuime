# frozen_string_literal: true

require "rails_helper"

RSpec.describe FuimeHelper, type: :helper do
  # The banner is the one place Fuime tells every visitor that no real money
  # moves. Getting the condition wrong is silent in both directions: too eager
  # and it undercuts a live product, too shy and a storefront quietly asks a
  # stranger for a card number it cannot charge.
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
