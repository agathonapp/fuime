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

    # Fuime G2: /admin/cohorts already auto-admits, but it lived off the nav
    # while Applications and Vetting (the graveyard after a complete apply)
    # were the only queues operators opened. The item has to sit in
    # Organizations, next to those two, and highlight when you are on it.
    it "lists Cohorts in Organizations next to Applications and Vetting" do
      instance = described_class.new(page_title: "Cohorts (Fuime)")
      organizations = instance.sections.find { |section| section.name == "Organizations" }
      names = organizations.items.map(&:name)

      expect(names).to include("Applications (Fuime)", "Cohorts (Fuime)", "Operator vetting (Fuime)")
      expect(names.index("Applications (Fuime)")).to be < names.index("Cohorts (Fuime)")
      expect(names.index("Cohorts (Fuime)")).to be < names.index("Operator vetting (Fuime)")

      item = organizations.items.find { |entry| entry.name == "Cohorts (Fuime)" }
      expect(item.path).to eq(Rails.application.routes.url_helpers.cohorts_admin_index_path)
      expect(item).to be_active
      expect(item).to be_task_count?
      expect(instance.active_section).to eq(organizations)
    end

    it "badges Cohorts with the number of live codes" do
      admin = create(:user, :make_admin, birthday: 40.years.ago.to_date)
      Fuime::Cohort.create!(
        name: "Founders Weekend",
        code: "LIVECODE",
        created_by: admin,
        rationale: "I know everyone attending.",
        expires_at: 2.days.from_now,
        max_members: 50
      )
      Fuime::Cohort.create!(
        name: "Last month",
        code: "DEADCODE",
        created_by: admin,
        rationale: "I knew everyone attending.",
        expires_at: 2.days.ago,
        max_members: 50
      )

      instance = described_class.new(page_title: "")
      item = instance.sections.flat_map(&:items).find { |entry| entry.name == "Cohorts (Fuime)" }

      expect(item.count).to eq(1)
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
