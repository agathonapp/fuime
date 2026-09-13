# frozen_string_literal: true

module Api
  module Entities
    class HcbFee < LinkedObjectBase
      when_expanded do
        expose :amount_cents, documentation: { type: "integer" }
        format_as_date do
          expose :created_at, as: :date
        end
        expose :aasm_state, as: :status, documentation: {
          values: %w[
            pending
            in_transit
            settled
          ]
        }

      end

      # Fuime: the schema name shown in the public API reference. The class,
      # the `hcb_fee_id` param and every route path keep their upstream spelling
      # (Rule 6) — only the name a reader sees changes.
      def self.entity_name
        "Fuime Fee"
      end

    end
  end
end
