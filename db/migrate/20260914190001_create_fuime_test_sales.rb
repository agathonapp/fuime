# frozen_string_literal: true

# Fuime: a test purchase a founder made against their own storefront.
#
# ── Why this is a table and not a flag on a canonical transaction ────────────
#
# This is the load-bearing decision in Sandbox Mode, so it is written down here
# rather than discovered later.
#
# A venture's balance is `canonical_transactions.sum(:amount_cents)` —
# Event#settled_incoming_balance_cents, unfiltered. Every figure a family sees
# and every figure a payout is computed from descends from that sum:
# #balance_available_v2_cents, Fuime::PayablesLedger, the payout batch, the
# fee accrual, the exports. Putting test money into the canonical pipeline and
# then filtering it out would mean finding and correcting each of those call
# sites, in the one part of this codebase CLAUDE.md Rule 3 forbids touching —
# and the cost of missing one is a teenager being shown, or paid, a number that
# is not real.
#
# So test money never becomes canonical at all. It cannot corrupt a balance
# because it is not in the sum, and that property holds without anybody
# remembering to maintain it. The trade is that the founder's test purchase is
# rendered beside their ledger rather than inside it, clearly marked — which is
# what they should see anyway.
#
# ⚠️ This table must never be summed into anything a founder is owed. It is the
# same warning Fuime::Sale carries, and for a stronger reason: those rows are
# real money recorded for reporting, these are not money at all.
class CreateFuimeTestSales < ActiveRecord::Migration[8.1]
  def change
    create_table :fuime_test_sales do |t|
      t.references :event, null: false, foreign_key: true

      # Who pressed Buy. Always an operator of the venture — the checkout path
      # refuses anyone else — and kept so a guardian reading the page can see
      # which of their teenagers was testing.
      t.references :user, null: false, foreign_key: true

      # No foreign key, matching Fuime::Sale: what was tested should survive the
      # offer being renamed, unpublished or archived afterwards, which is a
      # normal thing to do right after testing it.
      t.bigint :fuime_offer_id

      t.integer :amount_cents, null: false
      t.string :description
      t.datetime :occurred_at, null: false

      t.timestamps
    end

    # The only read this table has: this venture's test purchases, newest first.
    add_index :fuime_test_sales, [:event_id, :occurred_at]
    add_index :fuime_test_sales, :fuime_offer_id, where: "fuime_offer_id IS NOT NULL"
  end

end
