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
    # Fuime's fee waiver for early ventures. Same capabilities as Standard,
    # no platform fee. Replaces upstream's bare FeeWaived plan, which rendered
    # in pickers as an unexplained "full fiscal sponsorship (0.0%)".
    class Founders < FeeWaived
      def self.selectable?
        true
      end

      def label
        "Fuime founders (#{revenue_fee_label})"
      end

      def description
        "Every standard feature with Fuime's revenue fee waived — for early ventures and ones we've onboarded by hand."
      end

    end

  end

end
