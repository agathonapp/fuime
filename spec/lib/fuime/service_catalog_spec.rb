# frozen_string_literal: true

require "rails_helper"

# Fuime: the catalog, and the two constraints on it that are easy to break by
# being helpful.
RSpec.describe Fuime::ServiceCatalog do
  describe "the catalog" do
    # `digital` was opened on 2026-08-20; `crafts`, `food` and `other` are still
    # closed. The assertion is against the eligibility list rather than a literal,
    # so closing a category makes this fail loudly instead of leaving templates on
    # /learn for something nobody can sell.
    it "offers only categories a venture can actually sell under today" do
      categories = described_class.services.map(&:category).uniq

      expect(categories).to contain_exactly("services", "digital")
      expect(categories - Event::BUSINESS_CATEGORIES).to be_empty
      expect(categories - Fuime::OperatorEligibility::ELIGIBLE_CATEGORIES).to be_empty
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

    # The /learn fields, where the pressure now lands hardest: an offer is a name
    # AND a price everywhere else in the product, so an idea carrying only the
    # name looks unfinished. It is not unfinished — it is the half Fuime is
    # allowed to write. See the class header.
    it "never puts one in an offer idea, a customer source, or a warning" do
      described_class.services.each do |service|
        copy = Array(service.offer_ideas).flat_map { |idea| [idea[:name], idea[:unit_label]] } +
               Array(service.first_customers) + Array(service.watch_out)

        copy.compact.each do |line|
          price_shaped.each do |pattern|
            expect(line).not_to match(pattern), "#{service.key} suggests a price: #{line.inspect}"
          end
        end
      end
    end

    # A price cannot arrive through the pre-fill link either. `offer_ideas` is
    # rendered into a query string that opens the new-offer form, and
    # Fuime::OffersController::PREFILLABLE is what decides which keys survive —
    # so an idea growing a `price:` key must fail here rather than quietly
    # becoming a Fuime-written number in an operator's price box.
    it "carries no key the offer form would accept as a price" do
      described_class.services.each do |service|
        Array(service.offer_ideas).each do |idea|
          expect(idea.keys).to contain_exactly(:name, :unit_label),
                               "#{service.key} has an offer idea with unexpected keys: #{idea.keys.inspect}"
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

  # ── The /learn half of a template ─────────────────────────────────────────
  #
  # These three fields are what makes a catalog entry a browsable starter
  # template rather than a dropdown option (LearnController). They are optional
  # at the struct level so a service added without them degrades to a shorter
  # page — but every service that ships today has them, and this is what says so.
  describe "every template is worth opening" do
    it "lists things to sell, as a name and a unit and nothing else" do
      described_class.services.each do |service|
        expect(service.offer_ideas).to be_present, "#{service.key} has nothing to list"

        service.offer_ideas.each do |idea|
          expect(idea[:name]).to be_present
          expect(idea[:name].length).to be <= Fuime::Offer::MAX_NAME_LENGTH
          expect(idea[:unit_label].to_s.length).to be <= Fuime::Offer::MAX_UNIT_LABEL_LENGTH
        end
      end
    end

    it "says where the first customers come from" do
      described_class.services.each do |service|
        expect(service.first_customers).to be_present, "#{service.key} has no customer sources"
        expect(service.first_customers.length).to be >= 3
      end
    end

    it "says what goes wrong in that particular trade" do
      described_class.services.each do |service|
        expect(service.watch_out).to be_present, "#{service.key} has no warnings"
        expect(service.watch_out.length).to be >= 3
      end
    end

  end

  # ── The thing Fuime cannot do, asserted so no template promises it ────────
  #
  # `Fuime::Offer` has no recurring concept and merchant-of-record checkout is
  # `mode: "payment"`. An operator can sell access to software; they cannot bill
  # a customer monthly for it. A template saying otherwise would be describing a
  # product that does not exist, which is the L8 failure exactly.
  #
  # When recurring billing ships, these two examples fail. That is the intended
  # behaviour: somebody has to come back and rewrite the copy, rather than the
  # copy silently having been wrong and then silently becoming right.
  describe "no template offers to bill a customer monthly" do
    # The line is automatic renewal, not the word "month". Selling a month of
    # something for a single up-front payment is fine and is how a prepaid block
    # already works ("Block of four sessions"). What Fuime cannot do is charge
    # the customer again by itself, so that is what the copy may not promise.
    #
    # This started life as a blanket ban on "per month" and immediately caught
    # `lawn_and_garden` offering "Weekly mow through the season, per month" —
    # which was a real problem in the copy rather than a false positive, and is
    # now "A month of weekly mows, paid up front".
    it "lists nothing that renews itself" do
      described_class.services.each do |service|
        Array(service.offer_ideas).each do |idea|
          text = "#{idea[:name]} #{idea[:unit_label]}"

          expect(text).not_to match(/subscription|recurring|auto.?renew|billed monthly|every month/i),
                              "#{service.key} lists a recurring charge Fuime cannot bill: #{text.inspect}"
        end

        expect(service.description_prompt).not_to match(/subscription|recurring|auto.?renew/i)
      end
    end

    # The positive half. "Nothing promises a subscription" is satisfied by saying
    # nothing at all, which leaves somebody building a SaaS product and finding
    # out at launch. The template most likely to assume monthly billing says so.
    it "warns the one template that would otherwise assume it" do
      web_apps = described_class.find("web_apps")

      expect(web_apps.watch_out.join(" ")).to match(/cannot charge your customers monthly/i)
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
      # `food` rather than `digital`: digital became sellable on 2026-08-20 and
      # four templates now resolve to it, so it is no longer the empty case.
      stub_const("Fuime::OperatorEligibility::ELIGIBLE_CATEGORIES", %w[food].freeze)

      expect(described_class.sellable).to be_empty
    end

    it "drops the software templates if digital ever closes again" do
      stub_const("Fuime::OperatorEligibility::ELIGIBLE_CATEGORIES", %w[services].freeze)

      expect(described_class.sellable.map(&:key)).not_to include("web_apps", "digital_downloads")
      expect(described_class.sellable).not_to be_empty
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
