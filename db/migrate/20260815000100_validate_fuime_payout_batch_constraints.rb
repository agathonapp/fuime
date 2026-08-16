# frozen_string_literal: true

# Second half of CreateFuimePayoutBatches, split for the same reason as
# ValidatePayoutRequestDestinationConstraints: validating a foreign key or a check
# constraint takes a lock proportional to the table, so it happens in its own
# migration rather than inside the one that adds the columns.
class ValidateFuimePayoutBatchConstraints < ActiveRecord::Migration[8.0]
  def change
    validate_foreign_key :fuime_payout_batches, :users, column: :approved_by_id
    validate_foreign_key :fuime_payout_batches, :users, column: :paid_by_id
    validate_check_constraint :fuime_payout_batches, name: "fuime_payout_batches_state_known"
    validate_check_constraint :fuime_payout_batches, name: "fuime_payout_batches_period_ordered"

    validate_foreign_key :payout_requests, :fuime_payout_batches, column: :payout_batch_id
    validate_check_constraint :payout_requests, name: "payout_requests_destination_known"
    validate_check_constraint :payout_requests, name: "payout_requests_reserve_not_negative"
  end

end
