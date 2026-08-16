# frozen_string_literal: true

# Fuime: manual vetting state for an operator under the umbrella model.
#
# Under merchant-of-record, Fuime LLC is the legal seller of everything an
# operator sells. Fuime's name is on the receipt, and Fuime carries the refund,
# warranty and chargeback obligation to the buyer. That means Fuime inherits its
# operators' liability by design — it is not a gap in the model, it *is* the
# model, and the compensating control is that a human approves every operator
# before they can sell. See docs/fuime/MOR_MIGRATION_PLAN.md §8.
#
# ── Why this is not the application's AASM ──────────────────────────────────
#
# Event::Application already has an approval state machine, and reusing it was
# the obvious first move. It is the wrong shape: an application is answered once
# and then it is history. Vetting is a *standing* status that has to be
# revocable — an operator who starts selling something they did not apply with
# has to be stoppable on a Tuesday, without a fiction about their application
# from March being retroactively rejected.
#
# So the application decides whether a venture is created; this decides whether
# it may sell today. They answer different questions and drift apart on purpose.
#
# ── Why the default is unvetted rather than approved ────────────────────────
#
# Every existing row lands in `unvetted`, including ventures already created
# through the old flow. That is deliberate and it is the whole point of the
# column default: the safe answer has to be what you get when nobody has said
# anything, because the venture nobody has reviewed is exactly the one this
# control exists for. Backfilling existing rows to `approved` would mean the
# first thing this control ever does is exempt everyone it was built to check.
#
# Nothing breaks in the meantime — Fuime::OperatorEligibility only bites when
# FEATURE_MERCHANT_OF_RECORD is on, and it is off everywhere.
class AddOperatorVettingToEvents < ActiveRecord::Migration[8.1]
  # Required by the concurrent index below, which cannot run inside a
  # transaction. Adopted from CreateSchoolAwards, which does the same.
  disable_ddl_transaction!

  def change
    # Deliberately four `add_column` calls rather than one `change_table` block:
    # strong_migrations cannot inspect what happens inside the block, so it
    # refuses the whole thing unless it is wrapped in `safety_assured`. Waiving
    # the check to save three lines would waive it for every future edit to the
    # block too, which is the wrong trade on the events table.
    #
    # Integer rather than string for the status: a closed set the admin queue
    # sorts by, and a Rails enum over integers keeps an invalid value
    # unrepresentable rather than merely unvalidated. Safe to add with a default
    # on PG 11+, which no longer rewrites the table to do it.
    add_column :events, :operator_vetting_status, :integer, null: false, default: 0

    # Who decided, and when. Not recoverable from paper_trail: versions record
    # that the column changed, but an operator suspended by a background job and
    # one suspended by a named reviewer are different facts, and a liability
    # model whose control is "a human approves everyone" has to name the human.
    add_column :events, :operator_vetted_at, :datetime
    add_column :events, :operator_vetted_by_id, :bigint

    # Free text, because the first hundred approvals are the training data for
    # the automated risk model meant to replace them, and *why* a borderline
    # operator was approved is the part that cannot be reconstructed later from
    # the decision alone.
    add_column :events, :operator_vetting_notes, :text

    # The admin queue's only query: everyone waiting to be reviewed.
    add_index :events, :operator_vetting_status, algorithm: :concurrently

    # `validate: false` because validating the constraint takes a lock that
    # blocks writes on both events and users while every existing row is checked.
    # Every existing row has a NULL here — the column was created two lines ago —
    # so there is nothing to find, but the lock is taken regardless. The
    # validation runs as its own migration, matching
    # 20260806120100_validate_payout_request_destination_constraints.
    add_foreign_key :events, :users, column: :operator_vetted_by_id, validate: false
  end

end
