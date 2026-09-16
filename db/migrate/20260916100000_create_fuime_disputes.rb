# frozen_string_literal: true

# Fuime: one row per Stripe dispute against a merchant-of-record sale.
#
# The ledger already reversed the money when `charge.dispute.created` arrived —
# that is Fuime::PaymentWebhookHandler and it is not changing. What the ledger
# cannot hold is the part a person has to act on: the reason code, the date
# evidence is due, and whether it was ultimately won or lost. Under MoR the
# dispute is against FUIME, so if nobody responds by that date it is lost by
# default and Fuime pays it.
class CreateFuimeDisputes < ActiveRecord::Migration[7.2]
  def change
    create_table :fuime_disputes do |t|
      t.references :event, null: false, foreign_key: true
      t.references :fuime_sale, foreign_key: { to_table: :fuime_sales }

      # Stripe's dispute id (`dp_…`/`du_…`). Unique: a re-delivered webhook must
      # update this row rather than open a second case for the same chargeback.
      t.string :stripe_dispute_id, null: false
      t.string :stripe_payment_intent_id, null: false
      t.string :stripe_charge_id

      t.integer :amount_cents, null: false
      t.string :currency, null: false, default: "usd"

      # Stripe's own vocabulary, stored verbatim rather than mapped to ours: the
      # reason code is what the card network said and what an evidence response
      # has to answer, so translating it would lose the only thing it is for.
      t.string :reason
      t.string :status, null: false

      t.datetime :evidence_due_at
      t.datetime :opened_at, null: false
      t.datetime :closed_at

      # Set when a won dispute's ledger reversal has been backed out, so the
      # reinstatement happens exactly once however many times Stripe re-delivers
      # `charge.dispute.closed`.
      t.datetime :reinstated_at

      t.timestamps
    end

    add_index :fuime_disputes, :stripe_dispute_id, unique: true
    add_index :fuime_disputes, :stripe_payment_intent_id
    # The queue's own ordering: what is still open, soonest deadline first.
    add_index :fuime_disputes, [:status, :evidence_due_at]
  end
end
