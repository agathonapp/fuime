# frozen_string_literal: true

require "rails_helper"

RSpec.describe Event::Plan, type: :model do
  # `Event::Plan.available_plans` is `descendants`, so it only sees the plans
  # Zeitwerk has already autoloaded. `config.eager_load` is `ENV["CI"].present?`
  # in the test environment, which makes every assertion about the *set* of
  # plans depend on what an earlier spec happened to reference. Force the load.
  before { Rails.application.eager_load! }

  describe "#forces_transparency?" do
    it "is false by default" do
      expect(Event::Plan::Standard.new.forces_transparency?).to eq(false)
    end

    it "is true for the 2025 and 2026 Argosy plans" do
      expect(Event::Plan::Argosy2025.new.forces_transparency?).to eq(true)
      expect(Event::Plan::Argosy2026.new.forces_transparency?).to eq(true)
    end

    it "is true for plans inheriting from an Argosy plan" do
      expect(Event::Plan::ArgosyFtcSim2025.new.forces_transparency?).to eq(true)
    end

    it "is false for the 2024 Argosy plan" do
      expect(Event::Plan::Argosy2024.new.forces_transparency?).to eq(false)
    end
  end

  describe ".selectable_plans" do
    it "is exactly the lineup Fuime offers" do
      expect(Event::Plan.selectable_plans).to contain_exactly(
        Event::Plan::Free,
        Event::Plan::Standard,
        Event::Plan::Founders,
        Event::Plan::School,
        Event::Plan::SpendOnly,
        Event::Plan::CardsOnly,
        Event::Plan::Terminated,
        Event::Plan::Internal
      )
    end

    it "excludes the plans inherited from HCB" do
      expect(Event::Plan.legacy_plans).to include(
        Event::Plan::HackClubAffiliate,
        Event::Plan::HackClubHQ,
        Event::Plan::HighSchoolHackathon,
        Event::Plan::ScGoogleGrant,
        Event::Plan::SalaryAccount,
        Event::Plan::FeeWaived,
        Event::Plan::TenPercent,
        Event::Plan::Argosy2025,
        Event::Plan::ArgosyFtcSim2025
      )
    end

    it "accounts for every available plan" do
      expect(Event::Plan.selectable_plans + Event::Plan.legacy_plans)
        .to match_array(Event::Plan.available_plans)
    end
  end

  describe ".select_options" do
    it "offers only the selectable plans" do
      expect(Event::Plan.select_options.map(&:last))
        .to match_array(Event::Plan.selectable_plans.map(&:name))
    end

    it "keeps an organization's retired plan in the options so saving can't move it" do
      options = Event::Plan.select_options(Event::Plan::HighSchoolHackathon.name)

      expect(options.map(&:last)).to include(Event::Plan::HighSchoolHackathon.name)
    end

    it "does not duplicate a plan that is already selectable" do
      options = Event::Plan.select_options(Event::Plan::Standard.name)

      expect(options.map(&:last).tally[Event::Plan::Standard.name]).to eq(1)
    end

    it "ignores a blank or unrecognised current plan" do
      expect(Event::Plan.select_options(nil)).to eq(Event::Plan.select_options)
      expect(Event::Plan.select_options("Event::Plan::Nope")).to eq(Event::Plan.select_options)
    end
  end

  describe "#revenue_fee" do
    # Reads the constant rather than restating the number: the rate is a product
    # decision (it moved 4% -> 5% when merchant-of-record made Stripe's fee
    # Fuime's own cost), and a pricing change should not read as a failing test.
    # What is asserted is that Standard IS the fallback rate and that the label
    # renders it.
    it "charges the fallback rate on the standard plan" do
      rate = Event::Plan::FALLBACK_REVENUE_FEE

      expect(Event::Plan::Standard.new.revenue_fee).to eq(rate)
      expect(Event::Plan::Standard.new.label)
        .to eq("Fuime standard (#{ActionController::Base.helpers.number_to_percentage(rate * 100, precision: 1)})")
    end

    it "waives the fee on the founders plan" do
      expect(Event::Plan::Founders.new.revenue_fee).to eq(0.00)
      expect(Event::Plan::Founders.new.label).to eq("Fuime founders (0.0%)")
    end
  end

  describe "labels and descriptions" do
    it "never mentions Hack Club on a plan Fuime offers" do
      copy = Event::Plan.selectable_plans.flat_map { |plan| [plan.new.label, plan.new.description] }

      expect(copy).to all(satisfy { |text| !text.match?(/hack club|hcb/i) })
    end
  end
end
