# frozen_string_literal: true

# Fuime: make the ledger key actually unique, in the database.
#
# Every Fuime ledger line is keyed by `donation_transaction_id`
# (`fuime_<intent>`, `fuime_fee_<intent>`, `fuime_rev_…`, …) and every writer
# guards itself with `VentureLedger.find_row(key)` before inserting. That check
# ran outside the transaction that inserts, on a column with no index at all, so
# it was a read-then-write with nothing underneath it.
#
# Stripe fires BOTH `checkout.session.completed` and `payment_intent.succeeded`
# for one Checkout sale, deliberately keyed to the same PaymentIntent
# (Fuime::PaymentWebhookHandler). The two deliveries arrive milliseconds apart
# and production Puma serves them on different threads, so both could pass the
# `find_row` nil check and both insert: one $35 sale posted twice, the 7% fee
# posted twice, `PayablesLedger#net_payable_cents` overstated, and the Friday
# batch paying an operator for a sale that happened once. Stripe's own retries
# are a second path into the same window.
#
# Partial, and only over Fuime's own key space. Upstream HCB writes this table
# too (`RawPendingDonationTransactionService::Donation::ImportSingle` stores a
# bare donation id and is already idempotent via `find_or_initialize_by`).
# Constraining only `fuime_%` keys gives Fuime the guarantee it needs without
# imposing a new invariant on inherited rows — CLAUDE.md Rule 3: we feed the
# ledger engine, we do not change it.
#
# The second index is the read side of the same column. `VentureLedger
# .sum_by_prefix`, `PayablesLedger` and `ConnectSettlementSweep` all scan it with
# `LIKE 'fuime_…%'`, which a default btree in a non-C collation cannot serve;
# `varchar_pattern_ops` can. Those are the queries behind the payouts page and
# the settlement job, so this is the difference between a prefix scan and a
# sequential scan of every raw row in the system.
class AddUniqueIndexOnFuimeLedgerKeys < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def up
    add_index :raw_pending_donation_transactions,
              :donation_transaction_id,
              unique: true,
              where: "donation_transaction_id LIKE 'fuime\\_%'",
              algorithm: :concurrently,
              name: "index_rpdt_on_fuime_donation_transaction_id"

    add_index :raw_pending_donation_transactions,
              :donation_transaction_id,
              opclass: :varchar_pattern_ops,
              algorithm: :concurrently,
              name: "index_rpdt_on_donation_transaction_id_pattern"
  end

  def down
    remove_index :raw_pending_donation_transactions,
                 name: "index_rpdt_on_fuime_donation_transaction_id",
                 algorithm: :concurrently

    remove_index :raw_pending_donation_transactions,
                 name: "index_rpdt_on_donation_transaction_id_pattern",
                 algorithm: :concurrently
  end

end
