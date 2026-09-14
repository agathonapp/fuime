# frozen_string_literal: true

# Fuime: `fuime_sale_jurisdictions` becomes `fuime_sales`, and learns which
# offer was bought.
#
# ── Why rename a table one day old ───────────────────────────────────────────
#
# It was created for the nexus problem (MOR_RISK_ACCEPTANCE.md §7), so it was
# named after the column that mattered that morning. But what it actually holds
# is one row per merchant-of-record sale — payment intent, venture, amount, when
# — and jurisdiction is a property OF a sale rather than the point of it.
#
# The name matters because of what has to be built on top. Nothing in this app
# can answer "what does this founder sell most of" or "what did revenue do last
# month": `Fuime::Offer` has no sales association and the ledger aggregates by
# memo prefix, not by offer. This table is the obvious spine for that, and a
# table called `sale_jurisdictions` is one nobody will think to join to.
#
# Cheap now, expensive later: the table shipped nowhere, holds no production
# rows, and has exactly one writer. Rule 5 forbids editing the original
# migration, so this is a new one.
#
# ── Why the offer is a column and not a join through metadata ───────────────
#
# `Fuime::PaymentLinkService` already stamps `fuime_offer_id` on every sale that
# has an offer. Reading it back out of Stripe metadata for a report means a
# network call per row, and for a subscription the offer may have been archived
# or renamed since. Nullable because the free-amount path has no offer — a
# customer told a price in person is still a sale.
class RenameFuimeSaleJurisdictionsToSales < ActiveRecord::Migration[8.1]
  def change
    # ── Why `safety_assured` on a rename ──────────────────────────────────────
    #
    # Strong Migrations blocks `rename_table` for a real reason: during a deploy,
    # instances running the OLD code keep querying the OLD name and start
    # erroring the moment the rename lands. Its prescribed dance — create, dual
    # write, backfill, move reads, drop — exists for a table with live traffic.
    #
    # None of that applies here, and the specifics are worth stating rather than
    # waving through:
    #
    #   * The table was created earlier the SAME DAY (20260914120000) and has
    #     never been deployed. There is no old code anywhere that reads it.
    #   * It has exactly ONE writer (Fuime::PaymentWebhookHandler) and no reader
    #     in the app at all yet — the nexus report it was built for does not
    #     exist.
    #   * It holds no production rows.
    #
    # If any of those three stops being true, this is the wrong migration and the
    # dance is the right one.
    # The index is inside the same block for the same reason, and one more:
    # `add_index ... algorithm: :concurrently` (what Strong Migrations asks for)
    # requires `disable_ddl_transaction!`, which would take the rename above out
    # of its transaction too. On a table with no rows the index build is
    # instant and the lock is meaningless, so the transaction is worth more than
    # the concurrency.
    safety_assured do
      rename_table :fuime_sale_jurisdictions, :fuime_sales

      # No foreign key: an offer is never destroyed (Fuime::Offer archives
      # rather than deletes), but a sale must survive one being removed by any
      # route. What the sale was is a fact about money that changed hands.
      add_column :fuime_sales, :fuime_offer_id, :bigint
      add_index :fuime_sales, :fuime_offer_id
    end
  end

end
