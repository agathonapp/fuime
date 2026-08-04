# frozen_string_literal: true

# Fuime: the Stripe account a guardian owns on behalf of a venture.
#
# This is the table that ends the pooled-account model. Today every payment
# lands in Fuime's own Stripe balance and a ledger row says whose it is, which
# in production is money transmission (docs/fuime/LEGAL_RESEARCH.md §3, and
# CLAUDE.md L1). The replacement is one Stripe connected account per venture,
# owned by the guardian who signed for it: Stripe holds and settles the funds,
# Fuime takes a platform fee, and Fuime is never in the flow of funds.
#
# Why one account per venture rather than one per guardian: a Stripe account
# represents a business. Sharing one across two ventures would recommingle their
# revenue, which is the exact property we are trying to get rid of — so
# `event_id` is UNIQUE here, and a guardian with two teens onboards twice.
#
# Why the Stripe fields are mirrored rather than derived on demand: whether a
# venture can take a payment has to be answerable without a network call, on
# every storefront render. Stripe remains the source of truth and pushes changes
# via `account.updated`; `stripe_synced_at` records how stale the mirror is, and
# nothing here is trusted for authorization without it.
class CreateStripeConnectedAccounts < ActiveRecord::Migration[8.0]
  def change
    create_table :stripe_connected_accounts do |t|
      # One per venture. The unique index is the commingling guarantee.
      t.references :event, null: false, foreign_key: true, index: { unique: true }

      # The adult who legally owns this account and is its Stripe
      # representative. Recorded separately from the guardianship because the
      # guardianship can be revoked while the Stripe account continues to exist
      # and belong to them — it is theirs, not Fuime's, and Fuime must not imply
      # it can take it away.
      t.references :owner, null: false, foreign_key: { to_table: :users }

      # acct_… . Nullable: the row is created before the API call so a crash
      # mid-create cannot orphan a Stripe account we have no record of. The
      # partial unique index below still forbids two rows sharing an id.
      t.text :stripe_id

      # Mirrored from the Stripe Account object. Defaults are the safe answer to
      # "can this venture take money?" for a row we have not synced yet.
      t.boolean :charges_enabled, null: false, default: false
      t.boolean :payouts_enabled, null: false, default: false
      t.boolean :details_submitted, null: false, default: false

      # requirements.disabled_reason — why Stripe has switched the account off.
      t.string :disabled_reason

      # The whole `requirements` object, so a guardian can be told what is
      # actually outstanding instead of "something went wrong". Shape is
      # Stripe's, not ours, which is why it is jsonb and not columns.
      t.jsonb :requirements, null: false, default: {}

      # capabilities — `{"card_payments" => "active", "transfers" => "pending"}`.
      # Mirrored because `charges_enabled` alone does not distinguish "can take
      # card payments" from "can be paid out", and conflating those produces a
      # dead end nobody can explain to a fifteen-year-old: money arrives and then
      # appears stuck. Also jsonb because Stripe adds capabilities over time.
      t.jsonb :capabilities, null: false, default: {}

      # Whether this account exists in Stripe live mode. Fuime runs test mode by
      # default *including in production* (StripeService.mode), so without this a
      # test account and a live one are indistinguishable in the database — and
      # "is this real money?" must never be a guess.
      t.boolean :livemode, null: false, default: false

      t.datetime :onboarding_started_at
      t.datetime :onboarded_at
      t.datetime :stripe_synced_at

      t.timestamps
    end

    # Partial: many rows may legitimately have no stripe_id yet (see above), and
    # NULLs are distinct in a plain unique index only by accident of standard —
    # being explicit is cheaper than relying on it.
    add_index :stripe_connected_accounts,
              :stripe_id,
              unique: true,
              where: "stripe_id IS NOT NULL"
  end
end
