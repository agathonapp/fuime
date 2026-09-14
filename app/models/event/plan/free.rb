# frozen_string_literal: true

# == Schema Information
#
# Table name: event_plans
#
#  id          :bigint           not null, primary key
#  aasm_state  :string           not null
#  inactive_at :datetime
#  type        :string
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#  event_id    :bigint           not null
#
# Indexes
#
#  index_event_plans_on_event_id  (event_id)
#
# Foreign Keys
#
#  fk_rails_...  (event_id => events.id)
#
class Event
  class Plan
    # Fuime: THE plan. One flat price, everything included.
    #
    # ── 2026-09-14: 7% + a $19.99 family plan became 5% + 50¢, flat ──────────
    #
    # Founder's decision, matching the merchant-of-record market: Paddle, Lemon
    # Squeezy and Polar's entry tier are all 5% + 50¢ to the cent, and none of
    # them charges a monthly fee. Anything outside the standard rate is a
    # conversation with sales, not a tier in a picker.
    #
    # What went away with the monthly fee: the family plan gated exactly two
    # things — a second venture, and API keys — at the SAME take-rate as Free.
    # It was a feature gate wearing a pricing tier's clothes. Both are now
    # included for everyone, so there is one number to explain and no upgrade
    # screen between a founder and the thing they came to do.
    #
    # ⚠️ The 50¢ floor is not decoration and must be quoted with the rate. Under
    # merchant-of-record Stripe's 2.9% + 30¢ comes out of FUIME's balance, so at
    # 5% alone the break-even is 30¢ ÷ (5% − 2.9%) = $14.29, and every sale below
    # that loses money. `Event::Plan::MINIMUM_FEE_CENTS` is what makes small
    # baskets viable — see Event#fuime_fee_cents_on, which applies it only under
    # MoR. Copy that says "5%" without the floor describes a price Fuime does not
    # charge (L8).
    class Free < Standard
      REVENUE_FEE = 0.05

      # Fuime: everything Standard has. Nothing is withheld.
      #
      # `api_keys` was subtracted here while the family plan existed — the one
      # paid-only feature. With one flat price there is nothing to withhold it
      # for, and a founder ready to use the API is exactly the founder worth
      # keeping.

      def self.selectable?
        true
      end

      def revenue_fee
        REVENUE_FEE
      end

      def monthly_fee_cents
        0
      end

      # States the floor alongside the rate, because the floor is part of the
      # price — see the class header.
      def label
        "Fuime (#{Event::Plan.fuime_price_label})"
      end

      def description
        "One price, no monthly fee: Fuime keeps #{Event::Plan.fuime_price_label} of what it " \
          "collects, and nothing until you sell. Unlimited businesses and API keys included. " \
          "Selling at scale? Talk to us about custom pricing."
      end

    end

  end

end
