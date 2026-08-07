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
      REVENUE_FEE = 0.04

      def self.selectable?
        false
      end

      def revenue_fee
        REVENUE_FEE
      end

      def monthly_fee_cents
        ENV.fetch("FUIME_PRO_MONTHLY_CENTS", "1500").to_i
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
