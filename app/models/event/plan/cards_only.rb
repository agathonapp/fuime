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
    class CardsOnly < Standard
      # No rate in the label because this plan cannot collect: it inherits
      # Standard's `revenue_fee` and would print "5.0%" against money it never
      # takes in.
      def label
        "Fuime cards only (no money in)"
      end

      def description
        "Spending cards only — the venture cannot collect money at all. For ventures funded from elsewhere, or ones parked while something is sorted out."
      end

      def features
        %w[cards]
      end

      def omit_stats
        false
      end

    end

  end

end
