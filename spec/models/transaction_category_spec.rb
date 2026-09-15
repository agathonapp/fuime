# frozen_string_literal: true

require "rails_helper"

RSpec.describe TransactionCategory do
  describe "slug" do
    it "must be present" do
      instance = described_class.new(slug: "")
      instance.validate
      expect(instance.errors[:slug]).to include("can't be blank")
    end

    it "must be unique" do
      _existing = described_class.create!(slug: "rent")

      instance = described_class.new(slug: "rent")
      instance.validate
      expect(instance.errors[:slug]).to include("has already been taken")
    end

    it "must be part of the list" do
      instance = described_class.new(slug: "energy-drinks")
      instance.validate
      expect(instance.errors[:slug]).to include("is not included in the list")
    end
  end

  # FUIME: `hq_only` shipped from upstream and was never read — every category
  # list offered Fuime's own bookkeeping categories to teen founders. See the
  # comment on the scope.
  describe ".operator_visible" do
    it "excludes hq_only categories" do
      hq_only = described_class.create!(slug: "hcb-revenue")
      ordinary = described_class.create!(slug: "rent")

      expect(described_class.operator_visible).to include(ordinary)
      expect(described_class.operator_visible).not_to include(hq_only)
    end

    it "is composable with `or`, so an active filter can be kept visible" do
      hq_only = described_class.create!(slug: "hcb-revenue")
      ordinary = described_class.create!(slug: "rent")

      relation = described_class.operator_visible.or(described_class.where(id: hq_only))

      expect(relation).to include(ordinary, hq_only)
    end
  end

end
