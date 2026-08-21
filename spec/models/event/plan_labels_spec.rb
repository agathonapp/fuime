# frozen_string_literal: true

require "rails_helper"

# Fuime: what the admin plan picker says.
#
# This exists because of a screenshot. The dropdown read:
#
#     Fuime internal organization / Fuime standard (5.0%) / Fuime free (7.0%)
#     terminated / card-only / spend-only / school / Fuime founders (0.0%)
#
# Four of the eight were HCB leftovers wearing lowercase HCB labels, in a control
# that decides what a venture is CHARGED. An admin comping a school on launch day
# should not have to guess whether "school" is a Fuime plan or something inherited
# from a fiscal-sponsorship product, and the plan that starts a $15/month bill
# should say so.
RSpec.describe Event::Plan, "labels" do
  describe "every plan an admin can assign" do
    it "names Fuime, so nothing in the picker looks like an HCB leftover" do
      labels = described_class.selectable_plans.map { |plan| plan.new.label }

      expect(labels).to all(start_with("Fuime"))
    end

    it "explains itself, so the picker is not a list of jargon" do
      described_class.selectable_plans.each do |plan|
        expect(plan.new.description).to be_present, "#{plan.name} has no description"
      end
    end
  end

  describe "stating the price" do
    it "shows BOTH halves on the only plan that charges both" do
      # Standard is a percentage AND a subscription. The label used to print only
      # the percentage, so moving a venture onto it silently started a monthly bill.
      expect(Event::Plan::Standard.new.label).to eq("Fuime standard (5.0% + $15.00/mo)")
    end

    it "names the family plan's real price" do
      expect(Event::Plan::Pro.new.label).to eq("Fuime family (7.0% + $19.99/mo)")
    end

    it "collapses to just the rate when nothing is billed monthly" do
      expect(Event::Plan::Free.new.label).to eq("Fuime free (7.0%)")
      expect(Event::Plan::Free.new.monthly_fee_label).to be_nil
    end

    it "omits a rate on the plans that cannot collect money at all" do
      # Both inherit Standard's revenue_fee and would print "5.0%" against
      # revenue they can never take.
      expect(Event::Plan::Terminated.new.label).not_to include("%")
      expect(Event::Plan::CardsOnly.new.label).not_to include("%")
    end
  end

  describe ".select_options" do
    # The picker bug this pins: a venture on a retired plan is not in
    # `selectable_plans`, so a <select> built from that list renders its FIRST
    # option as selected — and submitting the form silently migrates the venture.
    it "keeps a venture's current plan in the list even when retired" do
      expect(Event::Plan::Argosy2024.selectable?).to be false

      options = described_class.select_options(Event::Plan::Argosy2024.name)

      expect(options.map(&:last)).to include(Event::Plan::Argosy2024.name)
    end

    it "does not offer retired plans to a venture that is not on one" do
      options = described_class.select_options(Event::Plan::Free.name)

      expect(options.map(&:last)).not_to include(Event::Plan::Argosy2024.name)
    end
  end
end
