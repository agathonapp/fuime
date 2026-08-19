# frozen_string_literal: true

# Fuime: a group of founders one person vouched for, once, in advance.
#
# ── The problem this solves ─────────────────────────────────────────────────
#
# Three human gates stand between a teenager signing up and being able to sell:
# an admin approves the application, an admin activates it into a venture, and an
# admin records a vetting decision. That is correct for strangers arriving off
# the internet one at a time, and it is the compensating control for letting
# minors sell at all.
#
# It does not survive fifty founders in a room on a Friday. 150 clicks while an
# event runs is not a control — it is a queue somebody clears without reading,
# which is strictly worse than no control because it produces a signed record of
# a judgement nobody made.
#
# ── Why this is not a bypass ────────────────────────────────────────────────
#
# The decision still happens, and a named human still makes it. What changes is
# WHEN and at what granularity: instead of fifty judgements about strangers made
# under time pressure, it is ONE judgement made in advance by somebody with more
# information than the queue would ever have given them — "I am running this
# event, I know who is coming, and I vouch for anyone holding my code."
#
# That is a real and honest decision, so `rationale` is NOT NULL: the person
# creating a cohort has to write down why they are entitled to make it. Each
# admission then records what actually happened — "approved under cohort X,
# created by Y on Z" — rather than a fabricated per-person judgement.
# Event#record_vetting_decision!'s own header warns that prefilling that note
# with an opinion puts words in a reviewer's mouth on the one control the whole
# model rests on. Recording the truth of a bulk decision does not.
#
# ── Why a code must expire and must be capped ───────────────────────────────
#
# A code with no expiry is a permanent standing bypass of vetting, and the first
# person to paste it into a Discord has removed the control for everybody. A code
# with no cap is the same failure with a different shape. Both are therefore NOT
# NULL with no default that could be read as "unlimited" — the person creating
# the cohort has to say how many people and until when, which are two things
# somebody running an event already knows.
class CreateFuimeCohorts < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def change
    create_table :fuime_cohorts do |t|
      t.string :name, null: false

      # What a founder types. Stored uppercase and compared uppercase — see the
      # model. Unique so two events cannot collide on one word.
      t.string :code, null: false

      # The accountable human. Every vetting decision this cohort makes is
      # recorded against them, which is the entire basis on which those decisions
      # are honest — so this is required and is never a system account.
      t.references :created_by, null: false, index: { algorithm: :concurrently }

      # Why this person may vouch for everybody holding the code. Required; see
      # the header.
      t.text :rationale, null: false

      # No default: "until when" is not a thing to be inferred.
      t.datetime :expires_at, null: false

      # Nor is "how many". A cap is what turns a leaked code into a bounded
      # incident rather than an open door.
      t.integer :max_members, null: false

      # Advancing the three gates. Off would make this a plain grouping label,
      # which is a legitimate thing to want (a cohort you watch but do not
      # auto-admit), so it is a column rather than an assumption.
      t.boolean :auto_approve, null: false, default: true

      # Passed to Event::Application#activate_event!, which requires one. Kept
      # per-cohort because "founders at a supervised weekend event" and "strangers
      # from a form" are not the same risk and should not be stamped the same.
      t.string :risk_level, null: false, default: "slight"

      # Killing a code has to be one action, available immediately, without
      # deleting the record of who was admitted under it.
      t.datetime :archived_at

      t.timestamps
    end

    # Case-insensitive uniqueness. A founder typing "fw2026" must not be able to
    # create a second cohort alongside "FW2026" — and must not silently miss the
    # one they meant.
    add_index :fuime_cohorts, "UPPER(code)", unique: true,
              name: "index_fuime_cohorts_on_upper_code", algorithm: :concurrently

    add_foreign_key :fuime_cohorts, :users, column: :created_by_id, validate: false

    add_check_constraint :fuime_cohorts, "max_members > 0",
                         name: "fuime_cohorts_capped", validate: false

    # Which cohort admitted this application, and therefore which one to hold
    # responsible for the decisions made on it.
    add_reference :event_applications, :fuime_cohort, null: true,
                  index: { algorithm: :concurrently }
    add_foreign_key :event_applications, :fuime_cohorts, column: :fuime_cohort_id, validate: false

    # Carried onto the venture as well as the application.
    #
    # Not derivable in practice: `Event#application` exists, but the roster board
    # needs to group and count ventures directly, and a venture created any other
    # way (console, import, a second venture for the same founder) has no
    # application to read it from. Denormalised deliberately, written once at
    # activation.
    add_reference :events, :fuime_cohort, null: true, index: { algorithm: :concurrently }
    add_foreign_key :events, :fuime_cohorts, column: :fuime_cohort_id, validate: false
  end

end
