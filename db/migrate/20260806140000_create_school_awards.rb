# frozen_string_literal: true

# Fuime: a school putting its own money into a student's venture.
#
# Alpha School pays $100 per A. Structurally that is the mirror image of
# PayoutRequest — money moving between the school and the student — but it is a
# different operation in every way that matters, which is why it is its own table.
#
# ── Why this is not a payment, and needs no Stripe call ──────────────────────
#
# The school and every student venture beneath it share one Stripe account
# (Event#payment_account). So moving $100 from the school to a student does not move
# money at Stripe at all: it changes which subledger the money is attributed to. The
# total across the tree is unchanged, no funds leave anyone's control, and Fuime is
# not in the flow of funds — because nothing flows. Two ledger lines, one negative
# on the school and one positive on the venture, posted together or not at all.
#
# ── The rule that makes it safe ──────────────────────────────────────────────
#
# The school must actually HAVE the money in its own subledger, and Fuime refuses
# the award otherwise. This is not bookkeeping fastidiousness. Fuime::PayoutService
# caps a student's withdrawal at `min(stripe_available, venture_ledger_balance)`, so
# crediting a venture $100 that no real money backs would let that student withdraw
# $100 of *other students'* sales revenue — and the ledger would only reveal it
# afterwards. Conservation across the tree is what keeps the pool backing the sum of
# its parts.
#
# ── Why there are no grades in this table ────────────────────────────────────
#
# Deliberate, and the most important design decision here. "$100 per A" is grade
# data, and grades are education records under FERPA (20 U.S.C. § 1232g). Alpha
# School is the covered entity; a vendor holding them is a "school official" only
# under 34 CFR 99.31(a)(1)(i)(B), which requires a written agreement, direct
# institutional control, and the exception named in the school's annual
# notification — and it makes Fuime a target for data it has no use for.
#
# Fuime does not need to know it was an A in Algebra II. It needs "the school awarded
# this student $100 on this date, school reference ABC-123". So `reference` is an
# opaque school-side identifier and there is deliberately no subject, grade, GPA,
# term, or course column. The school keeps the grades; Fuime keeps the money.
#
# Same principle as never storing ID images (CLAUDE.md L4, only the consent record)
# and never storing bank details on a payout request (only what the student typed).
# A spec fails the suite if a grade-shaped column is ever added here.
class CreateSchoolAwards < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def change
    create_table :school_awards do |t|
      # The student venture receiving the money.
      t.references :event, null: false, foreign_key: true

      # The school funding it. Stored rather than re-derived from the tree at read
      # time, because `Event#payment_account` resolves against today's structure and
      # a venture can be moved between cohorts — the record of who actually paid
      # must not change when an org chart does.
      t.references :school_event, null: false, foreign_key: { to_table: :events }

      # The student. Not derivable from the venture: a venture can have two
      # co-founders, and the $600/year 1099-MISC threshold is per PERSON, not per
      # business, so the award has to name who earned it.
      t.references :awarded_to, null: false, foreign_key: { to_table: :users }

      # The guide or business-office member who granted it.
      t.references :awarded_by, null: false, foreign_key: { to_table: :users }

      t.integer :amount_cents, null: false

      # The school's own identifier for whatever justified this — a gradebook entry
      # id, a term reference, a spreadsheet row. Opaque to Fuime BY DESIGN; see the
      # header. Never a subject or a grade.
      t.string :reference

      # When the school says the award was earned, which can precede the day someone
      # got round to entering it.
      t.date :awarded_on, null: false

      # Reversal, for an award granted in error. Not a destroy: the money did move,
      # and a ledger that erased the first half would misstate what a student's
      # balance did and when. Voiding posts reversing lines instead.
      t.datetime :voided_at
      t.references :voided_by, foreign_key: { to_table: :users }
      t.text :void_reason

      t.timestamps
    end

    # The 1099 question — "how much has this school paid this person this year?" —
    # is the one query this table exists to answer besides the ledger itself.
    add_index :school_awards, [:awarded_to_id, :awarded_on],
              algorithm: :concurrently

    # Awards are money. A negative or zero award is a bug in whatever called it, not
    # a correction — reversals go through `voided_at`.
    add_check_constraint :school_awards, "amount_cents > 0",
                         name: "school_awards_amount_positive", validate: false

    # A void needs both its timestamp and its author, or the audit trail says money
    # was taken back by nobody.
    add_check_constraint :school_awards,
                         "(voided_at IS NULL) = (voided_by_id IS NULL)",
                         name: "school_awards_void_is_attributed", validate: false
  end
end
