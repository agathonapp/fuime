# frozen_string_literal: true

# Fuime: what a venture's card is allowed to buy, and the copy that must accompany it.
#
# ── This file is a compliance control, not a convenience ─────────────────────
#
# A Stripe Issuing card is a business-purpose COMMERCIAL CHARGE CARD. The terms are
# explicit and they are not Fuime's to soften:
#
#   "You may only use your card for business or commercial purchases on behalf of
#    your Accountholder. You may not use your card for personal, family or
#    household purposes."
#     — Celtic Bank Authorized User Terms
#
#   "The Program is only available for business purposes… your Card Account is a
#    commercial account and does not provide all consumer protections."
#     — Celtic Spend Card Accountholder Terms §3.1, §6.2
#
# So "business purchases only" cannot be left as a sentence in an agreement a
# fifteen-year-old scrolled past. `spending_controls.allowed_categories` is how it
# becomes true at the network level, before a decline is a compliance incident.
#
# ── Why an ALLOWLIST and not a blocklist ────────────────────────────────────
#
# Stripe accepts `allowed_categories` OR `blocked_categories`, not both, so this is
# a real fork. The allowlist is correct because of how each one fails:
#
#   * a category missing from an ALLOWLIST => a legitimate purchase is declined.
#     The teen is annoyed, files a request, and the list grows. Recoverable.
#   * a category missing from a BLOCKLIST => a minor buys something personal on a
#     commercial card. That is the violation the terms exist to prevent, it is
#     invisible until an audit, and it is not recoverable.
#
# Fail closed. Stripe's category enum also grows over time, and a blocklist silently
# permits every category Stripe adds after this file was written.
#
# ── Where these strings come from ───────────────────────────────────────────
#
# Copied verbatim from app/services/breakdown_engine/categorizer.rb, which is
# upstream HCB code already running against Stripe's real category enum. They are
# NOT typed from memory or from the API reference: several are easy to get subtly
# wrong (`package_stores_beer_wine_and_liquor` carries an "and";
# `furniture_home_furnishings_and_equipment_stores_except_appliances` is one token),
# and an invalid category makes the whole Card create call fail.
module Fuime
  class CardSpendPolicy
    # ── ALLOWED: things a teen business actually buys ────────────────────────

    # Inventory, materials, tools. The core of a maker business.
    SUPPLIES = %w[
      miscellaneous_specialty_retail discount_stores wholesale_clubs
      home_supply_warehouse_stores miscellaneous_general_merchandise
      department_stores hardware_stores industrial_supplies variety_stores
      used_merchandise_and_secondhand_stores
      furniture_home_furnishings_and_equipment_stores_except_appliances
      sporting_goods_stores plumbing_heating_equipment_and_supplies
      hardware_equipment_and_supplies book_stores
      books_periodicals_and_newspapers news_dealers_and_newsstands
      record_stores
    ].freeze

    # Craft and art materials. Disproportionately important here: a large share of
    # teen ventures are physical-goods makers.
    MATERIALS = %w[artists_supply_and_craft_shops].freeze

    # Packaging, labels, printing, office supply.
    OFFICE = %w[
      stationery_stores_office_and_school_supply_stores
      stationary_office_supplies_printing_and_writing_paper
    ].freeze

    # Software and hardware. `digital_goods_applications` is how a teen buys the
    # design tool their business runs on; `digital_goods_games` is deliberately NOT
    # here (see ENTERTAINMENT below).
    TECH = %w[
      electronics_stores computer_software_stores computer_programming
      computer_network_services digital_goods_large_volume
      digital_goods_applications computers_peripherals_and_software
      electrical_parts_and_equipment digital_goods_media
    ].freeze

    # Services a business buys: accounting, legal, printing, contractors.
    SERVICES = %w[
      miscellaneous_business_services professional_services
      information_retrieval_services legal_services_attorneys
      employment_temp_agencies secretarial_support_services
      miscellaneous_general_services quick_copy_repro_and_blueprint
      insurance_underwriting_premiums
    ].freeze

    # Product photography, which every storefront needs.
    CREATIVE = %w[photographic_studios commercial_photography_art_and_graphics].freeze

    # Ads and fulfilment. `public_warehousing_and_storage` covers holding stock.
    MARKETING = %w[
      advertising_services miscellaneous_publishing_and_printing
      direct_marketing_other public_warehousing_and_storage
      direct_marketing_combination_catalog_and_retail_merchant
      direct_marketing_subscription
    ].freeze

    # SHIPPING IS LOAD-BEARING. A physical-goods business that cannot pay for
    # postage cannot operate, and this is the category most likely to be forgotten.
    SHIPPING_AND_COMMS = %w[
      courier_services postal_services_government_only
      telecommunication_services consulting_public_relations
    ].freeze

    ALLOWED_CATEGORIES = (
      SUPPLIES + MATERIALS + OFFICE + TECH + SERVICES + CREATIVE + MARKETING + SHIPPING_AND_COMMS
    ).uniq.freeze

    # ── EXCLUDED, with the reason recorded ──────────────────────────────────
    #
    # Documented rather than merely absent, because "why can't I buy X?" is a
    # support question with a real answer, and because a future reader adding a
    # category needs to know which omissions were deliberate.

    # Cash and cash equivalents. These defeat every other control on this list: a
    # gift card or a stored-value load converts a restricted commercial card into
    # unrestricted spending money, which is precisely the failure mode that makes
    # "business purchases only" unenforceable. Non-negotiable.
    EXCLUDED_CASH_EQUIVALENT = %w[
      wires_money_orders non_fi_stored_value_card_purchase_load
      financial_institutions gift_card_novelty_and_souvenir_shops
    ].freeze

    # The textbook "personal, family or household purposes" the terms forbid.
    EXCLUDED_PERSONAL = %w[
      eating_places_restaurants fast_food_restaurants grocery_stores_supermarkets
      miscellaneous_food_stores caterers drinking_places bakeries
      package_stores_beer_wine_and_liquor drug_stores_and_pharmacies
      medical_services
    ].freeze

    # Where a minor's discretionary spending actually goes. `digital_goods_games`
    # and `hobby_toy_and_game_shops` are the specific purchases that would turn a
    # compliant card into a violation, so they are named here rather than left to
    # a general omission.
    EXCLUDED_ENTERTAINMENT = %w[
      digital_goods_games hobby_toy_and_game_shops motion_picture_theaters
      theatrical_ticket_agencies miscellaneous_recreation_services
      cable_satellite_and_other_pay_television_and_radio
    ].freeze

    # Defensible as a business expense for some ventures, but far too easy to spend
    # personally, so they are opt-in per venture rather than on by default.
    # Clothing in particular: a teen printing custom shirts genuinely buys blanks
    # from a clothing store, and a teen buying jeans uses the same category.
    EXCLUDED_PENDING_REVIEW = %w[
      miscellaneous_apparel_and_accessory_shops mens_womens_clothing_stores
      family_clothing_stores automotive_parts_and_accessories_stores
      taxicabs_limousines airlines_air_carriers hotels_motels_and_resorts
      travel_agencies_tour_operators service_stations automated_fuel_dispensers
      parking_lots_garages car_rental_agencies colleges_universities utilities
    ].freeze

    # ── Required and forbidden copy ─────────────────────────────────────────
    #
    # Stripe's US Issuing compliance rules do not leave this to Fuime's judgement:
    # the commercial-purpose sentence is REQUIRED wherever the card program is
    # described, and the consumer-flavoured phrasings are FORBIDDEN. See
    # docs/fuime/LEGAL_RESEARCH.md. Pinned here with a spec so a well-meaning copy
    # edit cannot quietly remove the required line or reintroduce a banned one.
    REQUIRED_DISCLOSURE =
      "can only be used for commercial purposes, and can't be used for personal, " \
      "family, or household purposes"

    FORBIDDEN_PHRASES = [
      "Personal cards",
      "Get consumer cards",
      "for anything you want"
    ].freeze

    class << self
      # Handed straight to Stripe as `spending_controls[allowed_categories]`.
      def allowed_categories
        ALLOWED_CATEGORIES
      end

      def allows?(category)
        ALLOWED_CATEGORIES.include?(category.to_s)
      end

      # Why a category is not permitted, as a sentence for the teen who just got
      # declined. A decline with no explanation is how a family concludes the card
      # is broken and stops using the product.
      def refusal_reason(category)
        category = category.to_s

        return nil if allows?(category)

        case category
        when *EXCLUDED_CASH_EQUIVALENT
          "Cards can't be used for cash, gift cards, or money transfers."
        when *EXCLUDED_PERSONAL
          "This is a business card, so it can't be used for food, drink, or personal shopping."
        when *EXCLUDED_ENTERTAINMENT
          "This is a business card, so it can't be used for games or entertainment."
        when *EXCLUDED_PENDING_REVIEW
          "This category isn't enabled yet. If it's a real business expense, ask your " \
          "guardian to request it and we'll review it."
        else
          "This category isn't on the approved list for business purchases. If it's a " \
          "genuine business expense, ask your guardian to request it."
        end
      end

      # Guard for any copy describing the card program. Returns the problems found,
      # empty when the text is compliant.
      #
      # HTML entities are normalised first because the main thing worth checking is
      # RENDERED output, and the required disclosure contains an apostrophe ("can't")
      # that ERB emits as `can&#39;t`. Without this, a page carrying the disclosure
      # correctly would be reported as missing it — a false alarm that would train
      # someone to ignore the check.
      def copy_violations(text)
        text = CGI.unescapeHTML(text.to_s)
        problems = []

        if text.exclude?(REQUIRED_DISCLOSURE)
          problems << "missing the required commercial-purpose disclosure"
        end

        FORBIDDEN_PHRASES.each do |phrase|
          problems << "uses the forbidden phrase #{phrase.inspect}" if text.include?(phrase)
        end

        problems
      end

    end

  end
end
