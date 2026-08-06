# frozen_string_literal: true

class CreateFuimeSubscriptions < ActiveRecord::Migration[8.0]
  def change
    create_table :fuime_subscriptions do |t|
      # Nullable: a FAMILY subscription (the Pro plan) belongs to the guardian
      # and covers all their ventures, so it has no single event. Amended
      # in-place before this migration ever shipped — it exists only on the
      # unmerged PR that introduced it.
      t.references :event, null: true, foreign_key: true, index: { unique: true, where: "event_id IS NOT NULL" }
      t.references :billed_to, null: false, foreign_key: { to_table: :users }
      t.string :stripe_customer_id
      t.string :stripe_subscription_id, index: { unique: true, where: "stripe_subscription_id IS NOT NULL" }
      t.string :status, null: false, default: "incomplete"
      t.datetime :current_period_end
      t.boolean :cancel_at_period_end, null: false, default: false
      t.timestamps
    end

    # One family subscription per guardian.
    add_index :fuime_subscriptions, :billed_to_id, unique: true, where: "event_id IS NULL",
              name: "index_fuime_subscriptions_family_per_guardian"
  end
end
