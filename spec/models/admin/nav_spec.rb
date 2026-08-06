# frozen_string_literal: true

require "rails_helper"

RSpec.describe Admin::Nav do
  describe "#sections" do
    it "returns a list of sections" do
      instance = described_class.new(page_title: "")

      expect(instance.sections).to be_a(Array)
      expect(instance.sections).to all(be_a(described_class::Section))
    end

    # Fuime: examples use Invoices — Donations left the nav with the rest of
    # the HCB nonprofit money-in (see FUIME-DISABLED notes in Admin::Nav).
    it "marks the appropriate section and item as active" do
      instance = described_class.new(page_title: "Invoices")

      active_section = instance.sections.filter(&:active?).sole
      expect(instance.active_section).to eq(active_section)
      expect(active_section.name).to eq("Incoming Money")

      active_item = instance.sections.flat_map(&:items).filter(&:active?).sole
      expect(active_item.name).to eq("Invoices")
    end

    it "performs basic normalization when finding the active item and section" do
      instance = described_class.new(page_title: "  invoices")

      expect(instance.active_section.items.find(&:active?).name).to eq("Invoices")
    end
  end

  describe described_class::Section do
    describe "#task_sum" do
      it "returns the sum of all counts marked as tasks" do
        instance = described_class.new(
          name: "Dinosaurs",
          items: [
            Admin::Nav::Item.new(name: "Orpheus", path: "/", count: ->{ 11 }, count_type: :tasks),
            Admin::Nav::Item.new(name: "Littlefoot", path: "/", count: ->{ 22 }, count_type: :tasks),
            Admin::Nav::Item.new(name: "Barney", path: "/", count: ->{ 44 }, count_type: :records)
          ]
        )

        expect(instance.task_sum).to eq(33)
      end
    end

    describe "#counter_sum" do
      it "returns the sum of all counts marked as records" do
        instance = described_class.new(
          name: "Dinosaurs",
          items: [
            Admin::Nav::Item.new(name: "Orpheus", path: "/", count: -> { 11 }, count_type: :records),
            Admin::Nav::Item.new(name: "Littlefoot", path: "/", count: -> { 22 }, count_type: :records),
            Admin::Nav::Item.new(name: "Barney", path: "/", count: -> { 44 }, count_type: :tasks)
          ]
        )

        expect(instance.counter_sum).to eq(33)
      end
    end
  end
end
