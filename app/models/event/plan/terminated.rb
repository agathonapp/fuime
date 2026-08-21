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
    class Terminated < Standard
      # Fuime: every label in the picker names the product and its rate, so an
      # admin reading a dropdown can tell a Fuime plan from an HCB leftover
      # without opening the source. This one carries no rate on purpose — a
      # terminated venture cannot take a payment, so a percentage would be a
      # number that never applies.
      def label
        "Fuime terminated (frozen and hidden)"
      end

      def description
        "Ends the venture: every card is frozen, money in is refused, and it disappears from the directory. Assigning this freezes cards immediately."
      end

      def features
        %w[documentation]
      end

      def writeable?
        false
      end

      def hidden?
        true
      end

    end

  end

end
