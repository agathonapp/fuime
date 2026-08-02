# frozen_string_literal: true

# Fuime: validate the revoked_by FK added unvalidated in the previous migration.
class ValidateRevokedByForeignKeyOnGuardianships < ActiveRecord::Migration[8.0]
  def change
    validate_foreign_key :guardianships, :users, column: :revoked_by_id
  end
end
