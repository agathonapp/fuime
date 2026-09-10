# frozen_string_literal: true

# Fuime: validate the waived_by FK added unvalidated in the previous migration.
class ValidateGuardianRequirementWaivedByForeignKeyOnUsers < ActiveRecord::Migration[8.0]
  def change
    validate_foreign_key :users, :users, column: :guardian_requirement_waived_by_id
  end
end
