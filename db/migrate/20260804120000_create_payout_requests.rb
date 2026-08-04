# frozen_string_literal: true

# Fuime: a teen asking to move money out of the venture, and the guardian saying yes.
#
# ── Why this table exists at all ─────────────────────────────────────────────
#
# It would be simpler to leave the connected account on Stripe's automatic payout
# schedule and let money land in the family's bank on its own. This table is the
# deliberate rejection of that, for a legal reason rather than a product one.
#
# The guardian owns the connected account and the funds in it (CLAUDE.md L2 —
# the guardian is the legal party, the Stripe Representative, and the principal
# obligor). A minor moving money out of an account they do not own, without the
# owner's involvement, contradicts the structure the whole company rests on. So
# the approval gate is not a parental-controls feature bolted on for comfort; it
# is the ownership structure made operational. Every payout has a recorded adult
# decision behind it, which is also the artefact that answers "who authorised
# this?" years later.
#
# It is additionally the thing that makes the product legible to a parent, which
# is the acquisition channel (L7 — paid acquisition targets parents). But that is
# a side effect, not the reason.
#
# ── Why the amount is stored rather than "pay out everything" ────────────────
#
# A teen requests a specific number. Stripe's available balance moves underneath
# them — a refund lands, a chargeback opens, an earlier payout clears — so the
# amount asked for and the amount payable can differ by the time a parent looks.
# Storing the request means approval can compare the two and refuse honestly,
# instead of silently sending a different number than the one the parent saw.
class CreatePayoutRequests < ActiveRecord::Migration[8.0]
  def change
    create_table :payout_requests do |t|
      t.references :event, null: false, foreign_key: true

      # The teen who asked. Not `user` — this record has two humans on it and
      # naming them by role is the difference between an audit trail and a
      # guessing game.
      t.references :requested_by, null: false, foreign_key: { to_table: :users }

      # The guardian who approved. Null until then, and null forever on a
      # rejected or still-pending request.
      t.references :approved_by, foreign_key: { to_table: :users }

      # Requested amount, in cents, always positive. What actually left the
      # account is whatever Stripe reports against `stripe_payout_id`; these can
      # legitimately differ only by refusal, never by silent adjustment.
      t.integer :amount_cents, null: false

      t.string :aasm_state, null: false, default: "pending"

      # Guardian-supplied and shown to the teen. A rejection with no reason is
      # the kind of thing that makes a teenager distrust the tool rather than
      # talk to their parent, so the flow asks for one.
      t.text :rejection_reason

      t.datetime :approved_at
      t.datetime :rejected_at
      t.datetime :paid_at

      # po_… . Set when Stripe accepts the payout. Nullable because it does not
      # exist until approval, and unique (partially, below) because two rows
      # sharing one Stripe payout would mean the same money was counted twice.
      t.text :stripe_payout_id

      # Stripe's own words for why a payout bounced — usually a bank detail
      # problem the family has to fix. Stored rather than mapped to a Fuime
      # string, because guessing at a translation of a payment-network failure is
      # how a family gets told the wrong thing to go and do.
      t.string :failure_code
      t.text :failure_message

      t.timestamps
    end

    # The queue a guardian sees. Partial on the pending state because that is the
    # only status anybody polls for, and it stays small while the table grows.
    add_index :payout_requests,
              %i[event_id created_at],
              where: "aasm_state = 'pending'",
              name: "index_pending_payout_requests_on_event"

    add_index :payout_requests,
              :stripe_payout_id,
              unique: true,
              where: "stripe_payout_id IS NOT NULL"
  end
end
