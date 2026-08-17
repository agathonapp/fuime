# frozen_string_literal: true

# Fuime: where an operator's money goes, under merchant-of-record.
#
# ── What this replaces ──────────────────────────────────────────────────────
#
# The Connect onboarding screen. Today a guardian must give Stripe an SSN last-4,
# a home address, a phone number, an MCC, a business URL and ToS acceptance
# BEFORE a teenager can sell anything — for a business that has earned nothing
# yet. That is the single biggest drop-off in the funnel and it is asked at the
# worst possible moment.
#
# Under MoR the money is Fuime's own revenue from Fuime's own sale, so there is
# no merchant account for the operator to open. All that is needed is somewhere
# to send their share, asked **when they have money to send** rather than before
# they have made a sale. Same deferral Whop uses (WHOP_EVALUATION.md §4).
#
# ── ⚠️ No account numbers live here, and that is structural ─────────────────
#
# `AddDestinationToPayoutRequests` already committed to this and the reasoning
# has not changed: Fuime collecting a minor's (or their guardian's) bank
# credentials creates exactly the store of sensitive data CLAUDE.md L4 says not
# to hold, and it buys no capability — the originator needs them, Fuime does not.
#
# So this table holds a **tokenized reference to an object at a processor**
# (`provider` + `provider_reference`) plus the scraps needed to render "Chase
# ••1234" on a page. There is deliberately no `account_number` and no
# `routing_number` column, and a check constraint makes the last-4 field
# incapable of holding a full one.
#
# ── Why `provider` is a column and not an assumption ────────────────────────
#
# Plaid verifies an account; **Plaid does not move money** (MOR_MIGRATION_PLAN
# §4.3). Something else originates the ACH — Stripe, Slash or Mercury — and which
# one is still an open diligence question. Storing the provider means the
# unanswered half can be answered later without a migration, and means a row
# always says which system its reference is meaningful to.
class CreateFuimePayoutMethods < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def change
    create_table :fuime_payout_methods do |t|
      t.references :event, null: false, index: { algorithm: :concurrently }

      # Who added it. The operator or their guardian — recorded because a payout
      # destination is a claim about where money should go, and "who said so" is
      # the first question anybody asks when it turns out to be wrong.
      t.references :added_by, null: false, index: { algorithm: :concurrently }

      # plaid | stripe | manual. See the header for why this is stored.
      t.string :provider, null: false

      # The token at that provider. Never digits.
      t.string :provider_reference

      # Display only — "Chase ••1234". Never enough to originate anything.
      t.string :institution_name
      t.string :last4

      # The name on the account, as the provider reports it. Kept because a
      # mismatch between this and the guardian on file is the cheapest fraud
      # signal available, and because paying an account in somebody else's name
      # is the thing a payout review is looking for.
      t.string :account_holder_name

      # pending | verified | failed | removed
      t.string :aasm_state, null: false, default: "pending"
      t.datetime :verified_at
      t.text :failure_reason

      t.timestamps
    end

    add_foreign_key :fuime_payout_methods, :events, validate: false
    add_foreign_key :fuime_payout_methods, :users, column: :added_by_id, validate: false

    add_check_constraint :fuime_payout_methods,
                         "provider IN ('plaid', 'stripe', 'manual')",
                         name: "fuime_payout_methods_provider_known",
                         validate: false

    add_check_constraint :fuime_payout_methods,
                         "aasm_state IN ('pending', 'verified', 'failed', 'removed')",
                         name: "fuime_payout_methods_state_known",
                         validate: false

    # The structural half of "no account numbers here". A four-character ceiling
    # means this column cannot hold an account number even if somebody later
    # writes code that tries — the database refuses before the mistake ships.
    add_check_constraint :fuime_payout_methods,
                         "last4 IS NULL OR length(last4) <= 4",
                         name: "fuime_payout_methods_last4_is_last4",
                         validate: false

    # One live destination per venture. Money going to two places is a question
    # nobody wants to answer during a payout run, and "which account?" is not a
    # decision to make at send time.
    add_index :fuime_payout_methods, :event_id,
              unique: true,
              where: "aasm_state <> 'removed'",
              name: "index_live_fuime_payout_methods_on_event",
              algorithm: :concurrently
  end
end
