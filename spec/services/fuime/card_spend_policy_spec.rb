# frozen_string_literal: true

require "rails_helper"

# Fuime: the allowlist is what makes "business purchases only" true at the network
# level instead of a sentence in an agreement a fifteen-year-old scrolled past.
#
# Celtic's terms forbid using the card "for personal, family or household purposes",
# and Stripe's Issuing compliance rules dictate specific copy. Both are pinned here,
# because both fail silently: nobody notices a missing category until a purchase is
# declined, and nobody notices a removed disclosure until it is quoted back at them.
RSpec.describe Fuime::CardSpendPolicy do
  describe "the allowlist" do
    it "permits the things a teen business actually buys" do
      %w[
        artists_supply_and_craft_shops
        hardware_stores
        wholesale_clubs
        stationery_stores_office_and_school_supply_stores
        computer_software_stores
        digital_goods_applications
        advertising_services
        commercial_photography_art_and_graphics
        miscellaneous_business_services
      ].each do |category|
        expect(described_class).to allow_category(category), "expected #{category} to be allowed"
      end
    end

    # Shipping is the category most likely to be forgotten, and a physical-goods
    # business that cannot pay for postage cannot operate at all.
    it "permits shipping and postage" do
      expect(described_class).to allow_category("courier_services")
      expect(described_class).to allow_category("postal_services_government_only")
    end

    # These defeat every other control on the list: a gift card or a stored-value
    # load converts a restricted commercial card into unrestricted spending money.
    it "never permits cash or cash equivalents" do
      %w[
        wires_money_orders
        non_fi_stored_value_card_purchase_load
        financial_institutions
        gift_card_novelty_and_souvenir_shops
      ].each do |category|
        expect(described_class).not_to allow_category(category), "#{category} must never be allowed"
      end
    end

    it "does not permit food, drink or pharmacy" do
      %w[
        eating_places_restaurants
        grocery_stores_supermarkets
        package_stores_beer_wine_and_liquor
        drinking_places
        drug_stores_and_pharmacies
      ].each do |category|
        expect(described_class).not_to allow_category(category), "#{category} must not be allowed"
      end
    end

    # The specific purchases that would turn a compliant commercial card into a
    # violation.
    it "does not permit games or entertainment" do
      %w[
        digital_goods_games
        hobby_toy_and_game_shops
        motion_picture_theaters
      ].each do |category|
        expect(described_class).not_to allow_category(category), "#{category} must not be allowed"
      end
    end

    it "has no category in both the allowlist and an exclusion list" do
      excluded = described_class::EXCLUDED_CASH_EQUIVALENT +
                 described_class::EXCLUDED_PERSONAL +
                 described_class::EXCLUDED_ENTERTAINMENT +
                 described_class::EXCLUDED_PENDING_REVIEW

      expect(described_class.allowed_categories & excluded).to be_empty
    end

    it "contains no duplicates, which Stripe would reject" do
      categories = described_class.allowed_categories

      expect(categories).to eq(categories.uniq)
    end

    # Every string here has to exist in Stripe's enum or the whole Card create call
    # fails. They were copied from BreakdownEngine::Categorizer, which is upstream
    # HCB code already running against the real API, rather than typed from memory.
    it "uses only category strings that appear in upstream HCB's verified list" do
      upstream = File.read(Rails.root.join("app/services/breakdown_engine/categorizer.rb"))

      described_class.allowed_categories.each do |category|
        expect(upstream).to include(category), "#{category} is not in the verified upstream list"
      end
    end
  end

  describe "refusal reasons" do
    it "gives no reason for a permitted category" do
      expect(described_class.refusal_reason("hardware_stores")).to be_nil
    end

    # A decline with no explanation is how a family concludes the card is broken.
    it "explains cash equivalents specifically" do
      expect(described_class.refusal_reason("wires_money_orders")).to match(/cash, gift cards, or money transfers/i)
    end

    it "explains personal spending specifically" do
      expect(described_class.refusal_reason("eating_places_restaurants")).to match(/food, drink, or personal shopping/i)
    end

    it "points opt-in categories at the guardian rather than dead-ending" do
      expect(described_class.refusal_reason("family_clothing_stores")).to match(/ask your guardian/i)
    end

    # Stripe adds categories over time, so an unrecognised one must still produce a
    # sentence rather than nil.
    it "still explains a category it has never heard of" do
      expect(described_class.refusal_reason("interdimensional_portal_rentals")).to be_present
    end
  end

  describe "required and forbidden copy" do
    # Stripe's US Issuing compliance rules require this sentence wherever the card
    # program is described. It is not Fuime's to reword.
    it "accepts copy carrying the required commercial-purpose disclosure" do
      text = "Your Fuime card #{described_class::REQUIRED_DISCLOSURE}."

      expect(described_class.copy_violations(text)).to be_empty
    end

    it "flags copy that omits the disclosure" do
      violations = described_class.copy_violations("Get your Fuime card today.")

      expect(violations).to include(match(/missing the required commercial-purpose disclosure/i))
    end

    it "flags each forbidden consumer-flavoured phrase" do
      described_class::FORBIDDEN_PHRASES.each do |phrase|
        text = "#{described_class::REQUIRED_DISCLOSURE}. #{phrase}!"

        expect(described_class.copy_violations(text)).to include(match(/forbidden phrase/i)),
                                                         "expected #{phrase.inspect} to be flagged"
      end
    end
  end

  # Keeps the examples above readable; the repetition otherwise drowns the intent.
  matcher :allow_category do |category|
    match { |policy| policy.allows?(category) }
  end
end
