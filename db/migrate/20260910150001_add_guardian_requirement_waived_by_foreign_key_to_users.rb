# frozen_string_literal: true

# Fuime: add the waived_by FK separately from the column, and validate it in a
# second step, so users does not take a blocking lock on itself.
class AddGuardianRequirementWaivedByForeignKeyToUsers < ActiveRecord::Migration[8.0]
  def change
    add_foreign_key :users, :users, column: :guardian_requirement_waived_by_id, validate: false
  end
end
