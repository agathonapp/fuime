# frozen_string_literal: true

# Fuime: per-venture Sandbox Mode — a teenager testing their OWN storefront.
#
# ── Why this is not `demo_mode` ──────────────────────────────────────────────
#
# Upstream's `demo_mode` (Playground Mode) means "this whole venture is
# pretend": its money is excluded from stats, it cannot be disbursed from, it is
# hidden from Discover, and it may not hold a Column account number. That flag
# is correct for Fuime::Playground's pitch venture and wrong for a real one —
# flipping a live business into `demo_mode` would hide the money it has actually
# earned and block the payouts it is owed.
#
# `sandbox_mode` is the opposite shape. The venture stays completely real. What
# changes is that ITS OWN OPERATOR, and nobody else, can press Buy on their real
# storefront without reaching Stripe. A customer's click is untouched whether
# this is on or off, which is the property that makes the flag safe to leave on
# by accident — see Fuime::CheckoutsController#sandbox_checkout?.
#
# Nothing a sandbox purchase writes goes near the ledger. See
# CreateFuimeTestSales for why that is a separate table rather than a flagged
# canonical transaction.
class AddSandboxModeToEvents < ActiveRecord::Migration[8.1]
  def change
    add_column :events, :sandbox_mode, :boolean, default: false, null: false
  end

end
