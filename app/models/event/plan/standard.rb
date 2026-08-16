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
    class Standard < Plan
      def revenue_fee
        Event::Plan::FALLBACK_REVENUE_FEE
      end

      # Fuime: $15/mo alongside the 5% rate (founder's pricing, 2026-08-14).
      #
      # ── Why the instance_of? guard ─────────────────────────────────────────
      #
      # Eleven plans subclass Standard, and only two of them (Free, Pro) state
      # their own answer. Charging from this method unguarded would have started
      # billing $15/mo to `fee_waived`, `terminated`, `spend_only`, `cards_only`,
      # `sc_google_grant` and the four legacy HCB rate plans — every one of which
      # exists precisely because somebody is NOT paying the standard price.
      #
      # So the charge attaches to the Standard tier itself and not to the
      # inheritance tree beneath it. `#description` in this same class already
      # draws that line the same way, which is the convention being followed
      # rather than a new one being invented.
      #
      # Env-tunable for the same reason Pro's is: a price is a business decision
      # and should not need a Ruby deploy to change.
      def monthly_fee_cents
        return 0 unless instance_of?(Event::Plan::Standard)

        ENV.fetch("FUIME_STANDARD_MONTHLY_CENTS", "1500").to_i
      end

      def label
        "Fuime standard (#{revenue_fee_label})"
      end

      def description
        if self.instance_of?(Event::Plan::Standard)
          "The default plan for a teen-run venture: money in, cards, receipts, and reimbursements, with Fuime's #{revenue_fee_label} fee on revenue."
        else
          "Has access to all standard features"
        end
      end

      def features
        Event::Plan.available_features - %w[card_grants unrestricted_disbursements front_disbursements]
      end

      def receipt_required?
        true
      end

      def exempt_from_wire_minimum?
        false
      end

      def requires_reimbursement_expense_categorization?
        false
      end

      def omit_stats
        false
      end

      def writeable?
        true # false if an organization should be read-only
      end

      def hidden?
        false
      end

      def mileage_rate(date)
        return 67 if date < Date.new(2025, 1, 1)
        return 70 if date < Date.new(2025, 3, 27)
        return 14 if date < Date.new(2025, 4, 11) # https://hackclub.slack.com/archives/C047Y01MHJQ/p1743055747682219

        70
      end

      def contract_required?
        true
      end

      def card_lockable?
        true
      end

      def contract_skip_prefills
        {}
      end

    end

  end

end
