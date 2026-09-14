# frozen_string_literal: true

# Fuime: where the buyer was, for every merchant-of-record sale.
#
# ── Why this table has to exist, and why now ─────────────────────────────────
#
# Under MoR every operator's sales aggregate under ONE legal entity, so economic
# nexus accrues against Fuime rather than against fifty individual teenagers
# (MOR_RISK_ACCEPTANCE.md §7). Thresholds are commonly $100K or 200 transactions
# per state per year, and the obligation attaches from the transaction that
# crosses one — not from the day somebody notices.
#
# `Fuime::PaymentLinkService` has set `billing_address_collection: "required"` on
# every MoR checkout since the day digital goods were allowed, for exactly this
# reason. But nothing ever persisted the answer: the address lived only in
# Stripe's records, so the comment claiming the data "is already being captured"
# was true of Stripe and false of this database. Nothing in this app could
# compute a nexus threshold. This table is the missing half.
#
# ── Why a separate table rather than columns on the ledger ───────────────────
#
# Because Prime Directive 3 says the ledger engine is not ours to widen, and
# because this is buyer data with a different retention story than a transaction
# memo. Keyed on the PaymentIntent id — the same key the ledger is idempotent on
# (PaymentWebhookHandler) — so a row here joins to its ledger line without
# either side knowing about the other.
#
# ── Why these columns and not the rest of the address ────────────────────────
#
# Deliberate minimisation. Nexus counting needs jurisdiction and amount, nothing
# else. `country`, `state` and `postal_code` are what a threshold report and a
# later rate lookup need; `city` and the street lines are not, so they are not
# taken. Storing a buyer's street address to count state totals would be
# collecting personal data for a purpose that does not require it.
#
# `occurred_at` rather than relying on `created_at`: thresholds are measured on
# the calendar year the SALE happened in, and a row written by
# Fuime::MissedMorPaymentSweep is created days after the sale it records.
class CreateFuimeSaleJurisdictions < ActiveRecord::Migration[8.1]
  def change
    create_table :fuime_sale_jurisdictions do |t|
      t.string :stripe_payment_intent_id, null: false
      t.references :event, null: false, foreign_key: true
      t.integer :amount_cents, null: false
      # Nullable on purpose. A wallet payment can complete without Stripe
      # returning a full address, and a sale with an unknown jurisdiction is a
      # real thing that a nexus report must be able to SEE rather than a reason
      # to drop the row. An absent country is a gap to investigate; a missing
      # row is invisible.
      t.string :country
      t.string :state
      t.string :postal_code
      t.datetime :occurred_at, null: false

      t.timestamps
    end

    # Unique because the same sale arrives twice by design — Stripe fires both
    # checkout.session.completed and payment_intent.succeeded for one card
    # payment, and the sweep may replay either. The ledger dedupes on this same
    # id; so does this.
    add_index :fuime_sale_jurisdictions, :stripe_payment_intent_id, unique: true
    # The shape every nexus question asks: "how much, and how many, in this
    # state, in this year."
    add_index :fuime_sale_jurisdictions, [:country, :state, :occurred_at]
  end

end
