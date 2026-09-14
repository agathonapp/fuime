# frozen_string_literal: true

# Fuime: validation half of CreateFuimeWebhookEndpoints, per the house rule that
# a constraint's table-scanning lock gets its own deploy.
class ValidateFuimeWebhookDeliveryStatus < ActiveRecord::Migration[8.1]
  def change
    validate_check_constraint :fuime_webhook_deliveries,
                              name: "fuime_webhook_deliveries_status_known"
  end

end
