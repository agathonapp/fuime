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
    class SpendOnly < Standard
      def revenue_fee
        0.00
      end

      # This one genuinely is 0%, so it says so.
      def label
        "Fuime spend down (0.0%, no money in)"
      end

      def description
        "Money in is blocked; the venture spends down the balance it already has, with cards, transfers and reimbursements intact. No fee, because there is no revenue to take one from."
      end

      def features
        %w[cards transfers promotions google_workspace documentation reimbursements]
      end

    end

  end

end
