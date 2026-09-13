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
    refuse_if_duplicates_exist!

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

  # Fail before the index does, and say what to do about it.
  #
  # A duplicate is exactly the bug this index exists to prevent, so production
  # may already contain one — the double-post window has been open since the MoR
  # cutover. `add_index ... concurrently` on duplicate rows fails AND leaves an
  # INVALID index behind, which turns a known data problem into a broken deploy
  # and a second thing to clean up.
  #
  # Checking first costs one indexed-by-nothing scan of a small table and turns
  # that into a readable message naming the affected keys. The remedy is a
  # judgement call about real money — which of the two rows is the real sale, and
  # whether an operator was already paid for the duplicate — so it deliberately
  # is not automated here.
  def refuse_if_duplicates_exist!
    dupes = select_rows(<<~SQL)
      SELECT donation_transaction_id, COUNT(*)
      FROM raw_pending_donation_transactions
      WHERE donation_transaction_id LIKE 'fuime\\_%'
      GROUP BY donation_transaction_id
      HAVING COUNT(*) > 1
      ORDER BY COUNT(*) DESC
      LIMIT 25
    SQL

    return if dupes.empty?

    raise <<~MESSAGE
      Refusing to add the unique ledger index: #{dupes.size} Fuime ledger key(s) are already duplicated.

      #{dupes.map { |key, count| "  #{key} x#{count}" }.join("\n")}

      Each duplicate is one sale (or one fee) posted to a venture's ledger twice — the
      race this index closes. Before re-running: reconcile each key against Stripe,
      decide which row is the real posting, check whether a payout batch already paid
      the inflated amount, and remove the extra RawPendingDonationTransaction along
      with its CanonicalPendingTransaction and mapping.

      Do not delete rows to make this migration pass without doing that reconciliation.
    MESSAGE
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
