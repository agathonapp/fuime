# frozen_string_literal: true

# Second half of AddDestinationToPayoutRequests. Split for the same reason as
# ValidateLegalEntityPayoutMethodFkOnReimbursementReports: validating a foreign key
# or check constraint takes a lock proportional to the table, so it is done in its
# own migration rather than inside the one that adds the columns.
class ValidatePayoutRequestDestinationConstraints < ActiveRecord::Migration[8.0]
  def change
    validate_foreign_key :payout_requests, :users, column: :settled_by_id
    validate_check_constraint :payout_requests, name: "payout_requests_destination_known"
  end
end
