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
    class TenPercent < Standard
      # Legacy HCB fiscal-sponsorship fee tier. Retained for existing rows only.
      def self.selectable?
        false
      end

      # Retired, so it must not inherit Standard's "Fuime standard"
      # label — Fuime does not offer this rate.
      def label
        "legacy HCB fiscal sponsorship (#{revenue_fee_label})"
      end

      def revenue_fee
        0.1
      end

    end

  end

end
