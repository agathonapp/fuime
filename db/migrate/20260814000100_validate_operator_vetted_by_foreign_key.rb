# frozen_string_literal: true

# Fuime: validate the foreign key added unvalidated by AddOperatorVettingToEvents.
#
# Split into its own migration because validating an FK locks both tables against
# writes while Postgres checks every existing row. Adding it unvalidated and
# validating separately keeps each step's lock short — the standard
# strong_migrations pattern, and the one
# 20260806120100_validate_payout_request_destination_constraints already follows.
#
# There is genuinely nothing to find: `events.operator_vetted_by_id` was created
# in the previous migration, so every existing row is NULL. This exists so the
# constraint is enforced going forward rather than merely declared.
class ValidateOperatorVettedByForeignKey < ActiveRecord::Migration[8.1]
  def change
    validate_foreign_key :events, column: :operator_vetted_by_id
  end

end
