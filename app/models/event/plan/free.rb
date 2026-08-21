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
    # Fuime: the zero-friction entry plan, and the D2C default for new ventures.
    #
    # 7% is not arbitrary — it is HCB's own nonprofit rate, which makes the
    # sentence honest and easy: "free to start, same rate Hack Club charges;
    # drop to 4% with the family plan." A kid can start selling before any
    # adult has entered a card: the guardian signs the guardianship (free),
    # and Fuime earns only when the kid does.
    class Free < Standard
      REVENUE_FEE = 0.07

      # Fuime: everything Standard has, minus the developer API.
      #
      # The one feature the family plan sells beyond unlimited ventures. See
      # Event::Plan.available_features for why the list of safe-to-gate things
      # is so short.
      def features
        super - %w[api_keys]
      end


      def self.selectable?
        true
      end

      def revenue_fee
        REVENUE_FEE
      end

      def monthly_fee_cents
        0
      end

      def label
        "Fuime free (#{revenue_fee_label})"
      end

      def description
        "Free to start, one venture — Fuime keeps #{revenue_fee_label} of what it collects. " \
          "The family plan is #{Event::Plan::Pro.new.revenue_fee_label} with unlimited businesses."
      end

    end

  end

end
