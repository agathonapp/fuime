# frozen_string_literal: true

require "rails_helper"

# Fuime G3: marketing and /billing must state the Plan that Checkout charges.
#
# Event::Plan::Pro is $19.99/mo + 7% (same take-rate as Free). It unlocks
# unlimited ventures and API keys. It is not a cheaper fee. Stripe Billing
# creates `fuime_monthly_<cents>` from Plan#monthly_fee_cents — there is no
# unused $15 Pro price to "correct" toward.
RSpec.describe "Fuime pricing truth (G3)" do
  marketing_files = %w[
    site/index.html
    site/pricing.html
    site/parents.html
    site/site.js
    site/docs/BRIEF.md
  ].map { |rel| Rails.root.join(rel) }

  it "charges Pro at $19.99/mo and the same 7% as Free" do
    expect(Event::Plan::Pro.new.monthly_fee_cents).to eq(1999)
    expect(Event::Plan::Pro::REVENUE_FEE).to eq(Event::Plan::Free::REVENUE_FEE)
    expect(Event::Plan::Free::REVENUE_FEE).to eq(0.07)
  end

  it "does not advertise the retired $15/mo + 4% Pro on marketing pages" do
    marketing_files.each do |path|
      body = File.read(path)
      expect(body).not_to include("$15/mo + 4%"), "#{path} still sells Pro at $15 + 4%"
      expect(body).not_to include("Pro is $15"), "#{path} still sells Pro at $15"
      expect(body).not_to include("plus 4%"), "#{path} still claims a 4% Pro fee"
      expect(body).not_to include("drops to 4%"), "#{path} still implies a rate cut"
    end
  end

  it "states the live Pro price and same-rate unlock on every public price page" do
    %w[site/index.html site/pricing.html site/parents.html].each do |rel|
      body = File.read(Rails.root.join(rel))
      expect(body).to include("$19.99"), "#{rel} is missing $19.99"
      expect(body).to include("API keys"), "#{rel} is missing the API-key unlock"
      expect(body).to include("7%"), "#{rel} is missing the 7% take-rate"
    end
  end
end
