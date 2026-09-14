# frozen_string_literal: true

# Fuime: an offer can now bill monthly or yearly instead of once.
#
# `MOR_RISK_ACCEPTANCE.md` §8 recorded the absence deliberately — recurring was
# not attempted the night before a real-money launch. The driver then is the
# driver now: the archetypal founder vibecodes a tool and wants $9.99/month for
# it, and under one-time-only they can sell access once and never again.
#
# ── Why a string enum and not a boolean ──────────────────────────────────────
#
# Because "recurring?" is not the question anyone downstream actually asks.
# Stripe needs `recurring: { interval: }` on the price, the storefront needs to
# render "/month" or "/year", and the ledger memo needs to say which renewal this
# was. A boolean would push a second column or a hardcoded "month" into all
# three. NULL means one-time, which keeps every existing row correct with no
# backfill and makes the common case the default.
#
# ── Why only month and year ──────────────────────────────────────────────────
#
# Stripe supports day and week too. They are omitted because a teenager billing
# a customer weekly is a support burden and a refund argument, not a product —
# and the constraint can be widened later without a data change, whereas
# narrowing it after somebody sells a weekly plan cannot.
class AddBillingIntervalToFuimeOffers < ActiveRecord::Migration[8.1]
  def change
    add_column :fuime_offers, :billing_interval, :string

    # Mirrors the model validation. The constraint is what makes it true of rows
    # the model never sees — console, importer, fixture — which is the same
    # reasoning the price columns already follow.
    #
    # `validate: false` and a separate validation migration, per the house rule
    # Strong Migrations enforces: validating a constraint takes a lock that scans
    # the whole table, which is fine on an empty column and not fine on a table
    # anybody is selling through. Split so the lock is its own deploy.
    add_check_constraint :fuime_offers,
                         "billing_interval IS NULL OR billing_interval IN ('month', 'year')",
                         name: "fuime_offers_billing_interval_known",
                         validate: false
  end

end
