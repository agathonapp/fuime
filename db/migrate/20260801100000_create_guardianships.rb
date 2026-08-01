# frozen_string_literal: true

# Fuime guardianship: links a guardian (parent) to a minor (teen business owner)
class CreateGuardianships < ActiveRecord::Migration[8.0]
  def change
    create_table :guardianships do |t|
      t.references :guardian, null: false, foreign_key: { to_table: :users }
      t.references :minor, null: false, foreign_key: { to_table: :users }
      t.integer :status, default: 0, null: false # 0=pending, 1=active, 2=revoked
      t.datetime :agreement_signed_at
      t.string :invite_token
      t.datetime :invite_sent_at
      t.timestamps
    end

    add_index :guardianships, [:guardian_id, :minor_id], unique: true
    add_index :guardianships, :invite_token, unique: true
  end
end
