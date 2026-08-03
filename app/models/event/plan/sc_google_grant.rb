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
    class ScGoogleGrant < Standard
      # Hack Club grant program. Fuime does not administer it.
      def self.selectable?
        false
      end

      def label
        "South Carolina Google Grant"
      end

      def contract_skip_prefills
        {
          "Contract Signee" => ["The Project"],
          "Fuime"           => ["Fuime ID", "Signature"]
        }
      end

    end

  end

end
