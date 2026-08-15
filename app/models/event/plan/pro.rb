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
    # Fuime: the family plan — a monthly subscription that covers EVERY venture
    # the guardian signs for ("unlimited businesses"), at the lower 4% rate.
    #
    # Not directly selectable in a plan picker, deliberately: Pro is not a
    # per-venture choice, it is a property of the FAMILY. It is granted by the
    # guardian's Stripe Billing subscription (Fuime::Subscription with no
    # event) and resolved at read time in Event#billing_plan, the same
    # resolution-over-state pattern the School plan uses — so an upgrade or a
    # lapse takes effect everywhere at once with no rows to sweep.
    #
    # Price is env-tunable; $15/mo default per the founder's 2026-08-05 pricing
    # decision ($15-20 band).
    class Pro < Standard
      # ⚠️ 3% is BELOW Stripe's own rate on any normal teen-sized sale.
      #
      # Under merchant-of-record Fuime is the seller, so Stripe's 2.9% + 30¢ comes
      # out of Fuime's balance rather than the family's. Fuime's margin per sale is
      # therefore `(rate − 2.9%) × amount − 30¢`, and at 3% that leaves 0.1%:
      #
      #     break-even amount = 30¢ ÷ (3% − 2.9%) = 30¢ ÷ 0.001 = $300.00
      #
      # So **every Pro sale under $300 loses Fuime money**, and a $100 sale loses
      # about 20¢. The $19.99 subscription is what has to cover that, which works
      # for a low-volume/high-ticket operator and inverts for the opposite:
      #
      #     20 sales × $100/mo   →  −$4.00 of margin, +$19.99 sub  =  +$15.99 ✅
      #     200 sales × $10/mo   →  −$58.00 of margin, +$19.99 sub =  −$38.01 ❌
      #
      # The second row is the ordinary shape of a teen business selling stickers or
      # small commissions, so this is a real exposure rather than a rounding note.
      # The standard fix is a per-transaction floor (`max(rate × amount, floor)`),
      # which is what Gumroad and Etsy do and what the 30¢ exists to recover.
      #
      # Deliberately NOT applied here: pricing is the founder's decision and this
      # file should implement it, not quietly correct it. See
      # docs/fuime/MOR_MIGRATION_PLAN.md §8.6 for the numbers and the options.
      REVENUE_FEE = 0.03

      def self.selectable?
        false
      end

      def revenue_fee
        REVENUE_FEE
      end

      def monthly_fee_cents
        ENV.fetch("FUIME_PRO_MONTHLY_CENTS", "1999").to_i
      end

      def label
        "Fuime family (#{revenue_fee_label} + monthly)"
      end

      def description
        "The family plan: every business your kids run, #{revenue_fee_label} on revenue, " \
          "one monthly subscription billed to the parent."
      end

    end

  end

end
