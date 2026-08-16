# frozen_string_literal: true

require "rails_helper"

# Fuime: the catalog, and the two constraints on it that are easy to break by
# being helpful.
RSpec.describe Fuime::ServiceCatalog do
  describe "the catalog" do
    it "offers only categories a venture can actually sell under today" do
      categories = described_class.services.map(&:category).uniq

      expect(categories).to eq(["services"])
      expect(categories - Event::BUSINESS_CATEGORIES).to be_empty
    end

    it "keeps every service key unique" do
      keys = described_class.services.map(&:key)

      expect(keys.uniq).to eq(keys)
    end

    it "gives every service a checklist worth reading" do
      described_class.services.each do |service|
        expect(service.checklist).to be_present, "#{service.key} has no checklist"
        expect(service.checklist.length).to be >= 3
      end
    end

    it "resolves a key to its category, and an unknown key to nothing" do
      expect(described_class.category_for("tutoring")).to eq("services")
      # nil rather than a default: "services" is the value that unblocks selling
      # under merchant-of-record, so guessing it would be guessing an approval.
      expect(described_class.category_for("crypto_arbitrage")).to be_nil
    end
  end

  # ── The constraint that will be under constant pressure ────────────────────
  #
  # The most useful line a starter template could carry is "most people charge
  # about $25 for this", and it is the one line Fuime may not write. §8.3 D2's
  # mitigation for worker misclassification is that operators control their own
  # pricing and that Fuime never sets rates — a *suggested* rate is a set rate
  # with a softer verb, and an examiner would read it as one.
  #
  # Asserted against every template rather than trusted to a comment, because
  # somebody will eventually want to be helpful here.
  describe "no template suggests a price" do
    price_shaped = [
      /\$\s?\d/, # $25, $ 25
      /\d+\s*(dollars|bucks)/i,
      /\b(charge|price|rate|cost)s?\s+(about|around|roughly|typically|usually|approximately)\b/i,
      /\b(typical|average|going|suggested|recommended)\s+(rate|price|charge)\b/i,
      /\bper hour\s*[:-]\s*\d/i
    ].freeze

    it "never puts a number or a suggested rate in a checklist" do
      described_class.services.each do |service|
        service.checklist.each do |item|
          price_shaped.each do |pattern|
            expect(item).not_to match(pattern),
                                "#{service.key} checklist suggests a price: #{item.inspect}"
          end
        end
      end
    end

    it "never puts one in a blurb or a description prompt" do
      described_class.services.each do |service|
        [service.blurb, service.description_prompt].each do |copy|
          price_shaped.each do |pattern|
            expect(copy).not_to match(pattern), "#{service.key} suggests a price: #{copy.inspect}"
          end
        end
      end
    end

    # The positive half — the checklists should actively tell an operator the
    # number is theirs. Without this, "no price" could be satisfied by saying
    # nothing at all, which leaves a 16-year-old with no idea it is their call.
    it "tells the operator the rate is theirs to set" do
      described_class.services.each do |service|
        expect(service.checklist.join(" ")).to match(/your own rate/i),
                                               "#{service.key} never says the rate is the operator's"
      end
    end
  end

  # ── The exclusions, asserted so removing them is a deliberate act ──────────
  #
  # Under merchant-of-record Fuime is the legal seller of whatever the operator
  # sells. For lawn mowing the failure is a badly cut lawn; for childcare it is
  # injury to a child, which is a different order of liability and a conversation
  # nobody has had. See the class header — this is a launch-scope judgement, not
  # a permanent one.
  describe "childcare and physical coaching are not on the list" do
    it "offers nothing that puts a minor in an operator's physical care" do
      names = described_class.services.map { |s| "#{s.name} #{s.blurb}" }.join(" ").downcase

      expect(names).not_to match(/babysit|childcare|child care|nann(y|ies)|day ?care/)
      expect(names).not_to match(/\bcoach(ing)?\b/)
    end
  end

  describe ".sellable" do
    it "is what a venture may actually be created under right now" do
      expect(described_class.sellable).to eq(described_class.services)
    end

    # The reason .sellable exists separately from .services: opening a category
    # later should be able to widen the catalog without also widening the picker
    # on the same commit.
    it "narrows when the eligible categories narrow" do
      stub_const("Fuime::OperatorEligibility::ELIGIBLE_CATEGORIES", %w[digital].freeze)

      expect(described_class.sellable).to be_empty
    end
  end

  describe "starting points" do
    it "offers the three-way fork" do
      expect(described_class::STARTING_POINT_KEYS)
        .to contain_exactly("have_business", "have_idea", "from_template")
    end

    # Whop's third card is "clone a proven business". Cloning requires holding
    # real operators up as proven, and ranking operators is exactly what §8.3 D2
    # forbids — the same reasoning that made /directory a listing rather than a
    # dispatch. Fuime's third card is a Fuime-authored template, which names
    # nobody.
    it "does not offer to clone or rank another operator's business" do
      copy = described_class::STARTING_POINTS.map { |p| "#{p.name} #{p.blurb}" }.join(" ").downcase

      expect(copy).not_to match(/clone|copy an|proven|top|best|successful|popular/)
    end
  end
end
