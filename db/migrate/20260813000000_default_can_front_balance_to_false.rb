# frozen_string_literal: true

# Fuime: stop new ventures being created with balance fronting switched on.
#
# `events.can_front_balance` arrives from upstream defaulting to TRUE. Fronting
# means the platform lets an organization spend money that has arrived but not
# settled, with the platform carrying the gap out of its own reserves. HCB can do
# that: it is a 501(c)(3) and the money is legally its own to begin with.
#
# Fuime has no reserves, and under the umbrella merchant-of-record model the
# number being fronted against is a PAYABLE — what Fuime owes an operator for
# sales Stripe has not released yet. Fronting it would advance cash to a minor's
# business against Fuime's own unpaid invoice, recoverable only by netting
# against future sales that may never arrive. Stripe settles at T+2 and a
# chargeback can land for 120 days after that.
#
# ── Why only the default, and not the existing rows ─────────────────────────
#
# `Event#can_front_balance?` is overridden to return false whenever
# Fuime::Features.sponsor_banking? is off, which is every environment today. So
# no existing row's `true` has any effect right now, and a data migration
# rewriting thousands of rows would show up in the paper-trail audit log as a
# mass mutation with no user behind it — indistinguishable, six months later,
# from a bug.
#
# The default is what actually matters, and the reason is the flag rather than
# today: on the day someone sets FEATURE_SPONSOR_BANKING=true, every event
# carrying upstream's `true` would silently switch fronting ON at once. Turning
# custody on should enable the *mechanism*, not retroactively extend credit to
# every venture that ever signed up. Changing the default means the flag arrives
# with fronting off for everyone, and enabling it becomes a per-venture decision
# somebody makes on purpose.
#
# The column is preserved rather than dropped, per CLAUDE.md Rule 2. Reversible:
# `from:`/`to:` are both given.
#
# See docs/fuime/MOR_MIGRATION_PLAN.md §1 C2.
class DefaultCanFrontBalanceToFalse < ActiveRecord::Migration[8.1]
  def change
    change_column_default :events, :can_front_balance, from: true, to: false
  end

end
