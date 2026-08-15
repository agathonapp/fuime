# frozen_string_literal: true

# Fuime: the weekly run that pays every operator at once, and the thing that makes
# "Fuime pays you on a schedule" a mechanism rather than a promise in a paragraph.
#
# ── Why a batch is a record and not a query ─────────────────────────────────
#
# You could compute "who is owed what this Friday" on demand and never store it.
# Three things break if you do, and all three are the kind that surface months
# later in a dispute:
#
#   * The policy dials move. Hold period, reserve rate and the per-operator cap
#     are env-tunable (Fuime::PayoutPolicy) precisely so they can be adjusted as
#     loss experience accumulates. A recomputed batch would then re-answer a
#     question that was already answered under different rules, and an operator
#     asking "why was I paid $63 on 22 August" would get today's arithmetic
#     instead of August's. So the dials are COPIED ONTO THE ROW at generation.
#     The batch is the receipt for a decision, and a receipt does not float.
#   * Approval needs something to point at. The brief's control is manual review
#     of every payout; a human approving a query result approves nothing that can
#     be shown to have been what they saw.
#   * Money moves once. A batch that exists as a row can be `paid` exactly once;
#     a batch that exists as a query can be run twice on a bad afternoon.
#
# ── Why the batch, not the operator, holds the schedule ─────────────────────
#
# `Fuime::PayablesLedger::PAYOUT_WEEKDAY` already tells an operator when the next
# payout is. That is a display fact. This table is the record of the run actually
# happening, and the two are deliberately separate: the promise renders even when
# no batch has been generated yet, which is the state every operator is in during
# their first week.
#
# ── What this migration does NOT create ─────────────────────────────────────
#
# A payment rail. Under merchant-of-record the money is Fuime's own revenue and
# paying an operator is ordinary accounts payable, which can run on any
# originator — and WHICH one is an open product decision blocked on diligence
# (MOR_MIGRATION_PLAN §4.3: Mercury's ToS on programmatic ACH to hundreds of third
# parties, Slash as the API-native alternative, Plaid for account verification
# behind either). Nothing here presumes an answer.
#
# So a batch's terminal transition is `mark_paid!`, asserted by a human who has
# sent the money by whatever means Fuime actually has — exactly the shape the
# school path already uses (`PayoutService#settle!`), and for the same reason: the
# ledger follows what happened, never what was authorised. When the rail lands it
# becomes a `LegalEntity::PayoutMethod::BankAccount` behind that same transition,
# and this table does not change.
class CreateFuimePayoutBatches < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def change
    create_table :fuime_payout_batches do |t|
      t.string :aasm_state, null: false, default: "draft"

      # ── The period ────────────────────────────────────────────────────────
      #
      # `period_end` is the cutoff for what a batch may consider, and `payout_on`
      # is the Friday it is meant to go out. Two dates rather than one because
      # they are allowed to differ: a batch generated on Wednesday for Friday
      # holds a period ending Wednesday, and a run that slips to Monday still
      # settles the period it was generated for.
      t.date :period_start, null: false
      t.date :period_end, null: false
      t.date :payout_on, null: false

      # ── The policy, frozen ────────────────────────────────────────────────
      #
      # See the header. These are copies of Fuime::PayoutPolicy at generation
      # time, and nothing reads the env once a batch exists.
      #
      # `hold_days`: how long money must have been settled before it is eligible.
      # The dispute window is 120 days and paying weekly leaves Fuime unsecured
      # for the difference (MOR_MIGRATION_PLAN §8.4 item 1); a full 120-day hold
      # would make the product a savings account nobody asked for, so the hold is
      # short and the reserve carries the tail.
      t.integer :hold_days, null: false

      # `reserve_basis_points` of trailing volume is withheld as a rolling
      # reserve, and `reserve_window_days` is the trailing window it is computed
      # over. A rolling reserve rather than a per-payout withholding with its own
      # release schedule: as sales age out of the window the target falls on its
      # own, so the reserve releases without a release job, a release table, or a
      # class of stuck money that needs somebody to notice it.
      t.integer :reserve_basis_points, null: false
      t.integer :reserve_window_days, null: false

      # Concentration limits (§8.4 item 3). `maximum_cents` caps one operator in
      # one run — a single anomalous week cannot drain the account before a human
      # sees it. `minimum_cents` is the floor below which a payable rolls forward
      # rather than generating a line, because paying out $1.40 costs more in
      # transfer fees and attention than it delivers.
      t.integer :maximum_cents, null: false
      t.integer :minimum_cents, null: false

      # ── Decisions ─────────────────────────────────────────────────────────
      t.references :approved_by, index: { algorithm: :concurrently }
      t.datetime :approved_at
      t.datetime :paid_at
      # Who asserted the money actually went out. Separate from `approved_by` for
      # the same reason PayoutRequest separates `settled_by`: approving a run and
      # having completed it are different claims.
      t.references :paid_by, index: { algorithm: :concurrently }
      t.datetime :cancelled_at
      t.text :cancellation_reason
      t.text :notes

      t.timestamps
    end

    add_foreign_key :fuime_payout_batches, :users, column: :approved_by_id, validate: false
    add_foreign_key :fuime_payout_batches, :users, column: :paid_by_id, validate: false

    # One batch per period, so a double-click on "generate" cannot produce two
    # runs that each think they own the same week's payables. The uniqueness is in
    # the database rather than in a `find_or_create_by` because two workers racing
    # is the exact case a Ruby-side check does not cover.
    #
    # Scoped to live batches: a cancelled run has to be re-generatable for the same
    # period, which is the ordinary recovery path when a batch is generated against
    # a policy somebody then corrects.
    add_index :fuime_payout_batches, :period_end,
              unique: true,
              where: "aasm_state <> 'cancelled'",
              name: "index_live_fuime_payout_batches_on_period_end",
              algorithm: :concurrently

    add_index :fuime_payout_batches, :aasm_state, algorithm: :concurrently

    add_check_constraint :fuime_payout_batches,
                         "aasm_state IN ('draft', 'approved', 'paid', 'cancelled')",
                         name: "fuime_payout_batches_state_known",
                         validate: false

    add_check_constraint :fuime_payout_batches,
                         "period_end >= period_start",
                         name: "fuime_payout_batches_period_ordered",
                         validate: false

    # ── The lines ─────────────────────────────────────────────────────────────
    #
    # A batch line IS a PayoutRequest. Reused rather than given its own table
    # because the fields a batch line needs — amount, approval, destination,
    # failure code and message, the AASM lifecycle — are the fields PayoutRequest
    # already has and already has specs for (MOR_MIGRATION_PLAN §3.5). A parallel
    # table would duplicate the lifecycle and split "where has my money got to?"
    # across two places.
    add_reference :payout_requests, :payout_batch,
                  index: { algorithm: :concurrently }
    add_foreign_key :payout_requests, :fuime_payout_batches,
                    column: :payout_batch_id, validate: false

    # What was withheld as reserve on this line, as a positive number.
    #
    # Stored rather than recomputed for the same reason the dials are: the trailing
    # window moves every day, so tomorrow's answer to "why was $8.40 held back"
    # differs from today's, and the operator was shown today's.
    add_column :payout_requests, :reserve_held_cents, :integer, null: false, default: 0

    # What the operator was owed and eligible for before the reserve and the cap
    # were applied. The top of the explanation; `amount_cents` is the bottom of it.
    add_column :payout_requests, :eligible_cents, :integer

    # ── Nobody asks for a batch line ──────────────────────────────────────────
    #
    # `requested_by_id` was NOT NULL because on both pre-existing paths a person
    # asks: a teen taps "request payout" and an adult decides. That is the whole
    # shape of a request.
    #
    # A batch line has no such person, and inventing one would be a lie in the
    # audit trail — either naming a teenager who did not click anything, or naming
    # a Fuime admin as the beneficiary's requester. The honest record is that the
    # SCHEDULE generated it, which is what a null here means and what
    # PayoutRequest#scheduled? reads.
    #
    # This is also the compliance-relevant half of the whole model: an operator who
    # cannot choose when they are paid does not have a balance on demand
    # (CLAUDE.md L1/L5, and see Fuime::PayablesLedger's header). The column being
    # null is that fact, in the schema.
    change_column_null :payout_requests, :requested_by_id, true

    # A third destination, and the first one where Fuime is the payer.
    #
    #   account_owner_bank  — Stripe pays the guardian's own bank from the
    #                         guardian's own connected account. Fuime instructs;
    #                         Fuime never holds.
    #   personal_transfer   — the school pays its student directly. Fuime records.
    #   fuime_vendor_payment— Fuime pays a vendor out of Fuime's own money.
    #
    # The third only exists under merchant-of-record, and only makes sense there:
    # it presupposes that the customer's payment landed in Fuime's account as
    # Fuime's own revenue from Fuime's own sale. Under Connect that same movement
    # would be Fuime forwarding a stranger's funds, which is the thing L1 forbids —
    # so `PayoutRequest#destination_must_suit_the_account` refuses this value when
    # the flag is off, and this constraint is not the place that check lives.
    remove_check_constraint :payout_requests,
                            name: "payout_requests_destination_known"

    add_check_constraint :payout_requests,
                         "destination IN ('account_owner_bank', 'personal_transfer', 'fuime_vendor_payment')",
                         name: "payout_requests_destination_known",
                         validate: false

    # Reserve is a withholding, never a charge.
    add_check_constraint :payout_requests,
                         "reserve_held_cents >= 0",
                         name: "payout_requests_reserve_not_negative",
                         validate: false

    # One line per operator per batch. Same reasoning as the period index: the
    # generator is idempotent in Ruby, and this is what makes it idempotent under
    # a race.
    add_index :payout_requests, [:payout_batch_id, :event_id],
              unique: true,
              where: "payout_batch_id IS NOT NULL",
              name: "index_payout_requests_on_batch_and_event",
              algorithm: :concurrently
  end

end
