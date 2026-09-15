# frozen_string_literal: true

# Fuime: Sandbox Mode became a REAL Stripe test-mode checkout rather than a
# mocked one, so a rehearsal now has a Stripe object behind it.
#
# The unique index is the idempotency: a founder who refreshes the success page,
# opens it in two tabs, or comes back to the URL tomorrow gets one test sale, not
# four. Same rule the real money-in path enforces via Fuime::VentureLedger's
# keys, for the same reason — the difference is only that getting this wrong
# miscounts rehearsals rather than money.
#
# Nullable because rows written by the earlier mocked implementation have no
# session, and a partial index lets those coexist with the constraint.
class AddStripeSessionToFuimeTestSales < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    add_column :fuime_test_sales, :stripe_checkout_session_id, :string

    add_index :fuime_test_sales, :stripe_checkout_session_id,
              unique: true,
              where: "stripe_checkout_session_id IS NOT NULL",
              algorithm: :concurrently
  end

end
