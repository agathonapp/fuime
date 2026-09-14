# frozen_string_literal: true

# Fuime: let a founder's own server hear about their sales.
#
# `PADDLE_GAP_ANALYSIS.md` §3.8 called this the first-order developer gap, and
# it was the starkest absence in the whole comparison: no table, no deliverer,
# no signer, no retry queue. A seller's server was never told a sale happened —
# the only "did I get paid" signal was polling the payment-links API or opening
# the app. Every competitor has this, and it is what lets somebody build ON
# Fuime rather than merely use it.
#
# ── Two tables, because an event and a delivery attempt are different things ──
#
# This is the distinction Paddle draws between an `evt_` and an `ntf_`, and it
# is worth copying: one thing happened, and it may be delivered to N endpoints,
# each with its own retry state. Collapsing them means a failing endpoint
# rewrites history for a sale that certainly occurred.
#
#   * `fuime_webhook_endpoints` — where a venture wants events sent.
#   * `fuime_webhook_deliveries` — one row per (event, endpoint) attempt chain.
#
# ── The secret ───────────────────────────────────────────────────────────────
#
# Encrypted at rest like Fuime::ApiKey's token, and shown to the founder exactly
# once. It signs the payload so their server can prove a request came from
# Fuime; anyone who can read it can forge sales into their system.
class CreateFuimeWebhookEndpoints < ActiveRecord::Migration[8.1]
  def change
    create_table :fuime_webhook_endpoints do |t|
      t.references :event, null: false, foreign_key: true
      t.string :url, null: false
      t.text :encrypted_secret, null: false
      # A founder with three endpoints needs to know which is which, and "the
      # one ending in /hooks" is not an answer when both do.
      t.string :description
      # Disable rather than delete: an endpoint that broke at 2am should be
      # switchable off without losing its delivery history, which is the only
      # evidence of what went wrong.
      t.boolean :enabled, null: false, default: true
      t.datetime :last_delivered_at
      t.datetime :disabled_at

      t.timestamps
    end

    create_table :fuime_webhook_deliveries do |t|
      t.references :fuime_webhook_endpoint, null: false, foreign_key: true,
                                            index: { name: "index_fuime_deliveries_on_endpoint" }
      # The idempotency key a receiver dedupes on, and the key retries reuse.
      # Unique per endpoint: one sale delivered to two endpoints is two rows
      # carrying the same event id, which is correct — each has its own fate.
      t.string :event_id, null: false
      t.string :event_type, null: false
      t.jsonb :payload, null: false, default: {}
      t.string :status, null: false, default: "pending"
      t.integer :attempts, null: false, default: 0
      t.datetime :next_attempt_at
      t.integer :response_code
      t.text :last_error
      t.datetime :delivered_at

      t.timestamps
    end

    add_index :fuime_webhook_deliveries, [:fuime_webhook_endpoint_id, :event_id],
              unique: true, name: "index_fuime_deliveries_unique_per_endpoint"
    # The queue query: what is due to be sent.
    add_index :fuime_webhook_deliveries, [:status, :next_attempt_at],
              name: "index_fuime_deliveries_on_status_and_due"

    add_check_constraint :fuime_webhook_deliveries,
                         "status IN ('pending', 'delivered', 'failed')",
                         name: "fuime_webhook_deliveries_status_known",
                         validate: false
  end

end
