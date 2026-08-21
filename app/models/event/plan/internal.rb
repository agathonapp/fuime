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
    class Internal < FeeWaived
      def self.selectable?
        true
      end

      def label
        "Fuime internal (engineering only)"
      end

      def description
        "Engineering use only. Backs the ledger's own clearing and fee accounts — never assign this to a real venture."
      end

      def features
        Event::Plan.available_features
      end

      def requires_reimbursement_expense_categorization?
        true
      end

      def omit_stats
        true
      end

      def contract_required?
        false
      end

    end

  end

end
