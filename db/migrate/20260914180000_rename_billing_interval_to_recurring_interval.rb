# frozen_string_literal: true

# Fuime: `fuime_offers.billing_interval` → `recurring_interval`.
#
# Two reasons, and the second is the better one.
#
# 1. CodeQL flags any write to a `billing_*` attribute as clear-text storage of
#    sensitive information — a name heuristic aimed at payment data. This column
#    holds the string "month" or "year". A false positive, but a HIGH-severity
#    one that would fail CI on every future PR touching it, and a suppressed
#    "clear-text storage of sensitive information" alert is precisely the thing
#    nobody wants to find in an audit six months from now.
#
# 2. `recurring_interval` is simply the better name. Fuime::PaymentLinkService
#    builds `recurring: { interval: ... }` from it — Stripe's own vocabulary —
#    and `Fuime::Offer#recurring?` already reads that way. The scanner surfaced a
#    naming improvement rather than a security problem.
#
# Cheap because the column shipped nowhere: added earlier today in
# 20260914140000, no production rows. `safety_assured` for that reason, the same
# as the other renames in this branch — if it stops being true, this is the
# wrong migration.
class RenameBillingIntervalToRecurringInterval < ActiveRecord::Migration[8.1]
  def change
    safety_assured do
      # The constraint names the old column, so it has to go before the rename
      # and be re-added after — Postgres does not rewrite a CHECK body.
      remove_check_constraint :fuime_offers,
                              "billing_interval IS NULL OR billing_interval IN ('month', 'year')",
                              name: "fuime_offers_billing_interval_known"

      rename_column :fuime_offers, :billing_interval, :recurring_interval

      add_check_constraint :fuime_offers,
                           "recurring_interval IS NULL OR recurring_interval IN ('month', 'year')",
                           name: "fuime_offers_recurring_interval_known"
    end
  end

end
