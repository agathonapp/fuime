# frozen_string_literal: true

class CreateFuimeSubscriptions < ActiveRecord::Migration[8.0]
  def change
    create_table :fuime_subscriptions do |t|
      t.references :event, null: false, foreign_key: true, index: { unique: true }
      t.references :billed_to, null: false, foreign_key: { to_table: :users }
      t.string :stripe_customer_id
      t.string :stripe_subscription_id, index: { unique: true, where: "stripe_subscription_id IS NOT NULL" }
      t.string :status, null: false, default: "incomplete"
      t.datetime :current_period_end
      t.boolean :cancel_at_period_end, null: false, default: false
      t.timestamps
    end
  end
end
