# frozen_string_literal: true

# Fuime: money arriving into a school's own Stripe balance, so it has something to award.
#
# SchoolAward moves money that is already there — it reattributes between subledgers
# and deliberately makes no Stripe call. That leaves an obvious hole, recorded as the
# open question on the awards work: **nothing put money into the school's account in
# the first place.** A school with a $0 balance can award nothing, so the awards
# feature demoed but could not run.
#
# ── Why a top-up and not a transfer ──────────────────────────────────────────
#
# Three ways money could reach a connected account's balance, and only one is
# available to Fuime:
#
#   * Stripe::Transfer from the platform balance — requires Fuime to hold the money
#     first. That is the custody problem (L1) and it is the whole reason this
#     architecture exists. Never.
#   * A direct charge — the school pays itself by card and loses ~2.9% moving its
#     own money. Works, and is absurd.
#   * Stripe::Topup — an ACH pull from the school's OWN bank account into its OWN
#     Stripe balance. Fuime is not a party to it; it asks Stripe, on the school's
#     behalf, to move the school's money between two accounts the school owns.
#
# ── Why this table exists at all, given Stripe has the Topup object ──────────
#
# Because the ledger, not Stripe, is what awards spend against. `Event#balance_v2_cents`
# sums canonical transactions; a top-up that Stripe knows about but the ledger does
# not would be invisible to Fuime::SchoolAwardService#available_to_award_cents, and
# the school would be told it has no money while its Stripe balance says otherwise.
# This row is the join between the Stripe object and the ledger line, and the place
# a failure reason can be shown to a business office that is wondering where its
# money went.
#
# ── Top-ups Fuime did not initiate ──────────────────────────────────────────
#
# A school administrator can add funds from the Stripe Dashboard directly, and Stripe
# creates a Topup object and fires the same webhooks when they do. So `requested_by`
# is nullable and the recorder does not require a row to exist before it posts to the
# ledger — the same principle Fuime::ConnectPayoutRecorder documents for payouts made
# outside Fuime. The webhook is the load-bearing part; the in-app button is
# convenience. This matters more than usual here, because whether a Stripe-liability
# connected account may create top-ups at all is unverified (see the service).
class CreateSchoolFundings < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    create_table :school_fundings do |t|
      t.references :event, null: false, foreign_key: true, index: false
      t.integer :amount_cents, null: false

      # Nullable on purpose — see the class comment. A top-up created in the Stripe
      # Dashboard has no Fuime user behind it.
      t.references :requested_by, null: true, foreign_key: { to_table: :users }

      # Nullable because the row is written before Stripe answers, and because a
      # failed create leaves a record worth keeping. Unique when present so a
      # replayed webhook cannot produce a second row for one real top-up.
      t.string :stripe_topup_id

      t.string :status, null: false, default: "pending"
      t.string :failure_code
      t.text :failure_message

      # When the money actually became available. Distinct from updated_at, which
      # moves for reasons that are not this.
      t.datetime :succeeded_at

      t.timestamps
    end

    add_index :school_fundings, :event_id, algorithm: :concurrently
    add_index :school_fundings, :stripe_topup_id, unique: true,
                                                  where: "stripe_topup_id IS NOT NULL",
                                                  algorithm: :concurrently
    add_index :school_fundings, [:event_id, :created_at], algorithm: :concurrently

    # A top-up of zero or a negative amount is not a thing. Validated separately so
    # the constraint does not lock the table while it is added.
    add_check_constraint :school_fundings, "amount_cents > 0",
                         name: "school_fundings_amount_positive", validate: false

    add_check_constraint :school_fundings,
                         "status IN ('pending', 'succeeded', 'failed', 'canceled')",
                         name: "school_fundings_status_known", validate: false

    # Succeeded means the money landed, which means Stripe told us so, which means
    # there is a Topup id. Anything else is a row claiming money exists with nothing
    # behind it — the exact class of bug the awards work was written to avoid.
    add_check_constraint :school_fundings,
                         "status <> 'succeeded' OR (stripe_topup_id IS NOT NULL AND succeeded_at IS NOT NULL)",
                         name: "school_fundings_succeeded_is_evidenced", validate: false
  end

end
