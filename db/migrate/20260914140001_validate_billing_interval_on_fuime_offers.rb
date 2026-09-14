# frozen_string_literal: true

# Fuime: the validation half of AddBillingIntervalToFuimeOffers. Separate
# migration because validating a check constraint scans the table under a lock,
# and the house rule is that the lock gets its own deploy.
class ValidateBillingIntervalOnFuimeOffers < ActiveRecord::Migration[8.1]
  def change
    validate_check_constraint :fuime_offers, name: "fuime_offers_billing_interval_known"
  end

end
