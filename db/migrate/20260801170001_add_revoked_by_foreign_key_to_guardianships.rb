# frozen_string_literal: true

# Fuime: add the revoked_by FK separately from the column, and validate it in a
# second step, so neither guardianships nor users takes a blocking lock.
class AddRevokedByForeignKeyToGuardianships < ActiveRecord::Migration[8.0]
  def change
    add_foreign_key :guardianships, :users, column: :revoked_by_id, validate: false
  end
end
