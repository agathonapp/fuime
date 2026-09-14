# frozen_string_literal: true

# Fuime: who bought.
#
# The gap behind every analytics question Fuime could not answer — MRR, churn,
# LTV, cohorts, repeat purchase all need a customer before they need a query
# (PADDLE_GAP_ANALYSIS §3.5, §3.7). And the founder-facing half is simpler than
# that: a teenager mowing a lawn needs to know whose lawn it is.
#
# ── The data was already arriving and being dropped ──────────────────────────
#
# Stripe puts the buyer's email and name in `session.customer_details`, which
# Fuime::PaymentWebhookHandler already reads — for `.address` only. So this is
# mostly plumbing rather than new collection, the same shape as the jurisdiction
# fix earlier today.
#
# ── Scoped to the venture, on purpose ────────────────────────────────────────
#
# A row is a customer OF A VENTURE, keyed on (event_id, email), not a global
# Fuime identity. One person buying from two ventures is two rows.
#
# That costs a little denormalisation and buys the property that matters: venture
# A cannot learn that its customer also buys from venture B. A global customer
# table would make cross-venture profiling a JOIN away, on a platform whose
# operators are minors and whose buyers never agreed to be tracked across
# unrelated businesses (L7).
#
# ⚠️ DISCLOSURE, NOT CODE: Fuime is the merchant of record, so Fuime collects
# this data and shares it with the operator who fulfils. The terms and privacy
# policy have to say so. See the note in Fuime::Customer.
class CreateFuimeCustomers < ActiveRecord::Migration[8.1]
  def change
    create_table :fuime_customers do |t|
      t.references :event, null: false, foreign_key: true
      t.string :email, null: false
      t.string :name
      # Stripe's own customer id, when the sale produced one. This is what a
      # billing-portal session is opened against, so it is the difference
      # between a buyer being able to cancel a subscription themselves and
      # having to email support — see the FTC click-to-cancel note in
      # app/views/fuime/payment_pages/show.html.erb.
      t.string :stripe_customer_id
      t.datetime :first_purchased_at, null: false
      t.datetime :last_purchased_at, null: false

      t.timestamps
    end

    # Email is the identity, and it is the thing a repeat purchase matches on.
    add_index :fuime_customers, [:event_id, :email], unique: true
    add_index :fuime_customers, :stripe_customer_id,
              where: "stripe_customer_id IS NOT NULL"

    # The fuime_sales column and its index are a separate migration
    # (20260914170001), because indexing an existing table is what Strong
    # Migrations wants done concurrently and that needs its own
    # disable_ddl_transaction!.
  end

end
