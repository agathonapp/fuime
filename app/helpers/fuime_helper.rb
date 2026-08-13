# frozen_string_literal: true

# Fuime-specific view helpers.
module FuimeHelper
  # Whether to show the app-wide "test mode — no real money moves" banner.
  #
  # Fuime runs Stripe in test mode in production, deliberately: the
  # money-transmission structure is not legally settled
  # (docs/fuime/PRODUCTION_READINESS.md §1.5). That is a defensible posture, but
  # only if it is stated. A storefront takes a card number and a card page issues
  # a card that looks real — a visitor has no way to know neither does anything
  # unless the app says so.
  #
  # This lives in a helper rather than inline in the banner partial so the rule
  # is testable: the banner is suppressed in development and test, so a view
  # spec could never exercise it.
  def show_test_mode_banner?
    return false if StripeService.live?

    # `local?` is development or test. Test mode is the obvious default in both,
    # and the banner would be noise in one and unassertable in the other.
    !Rails.env.local?
  end

  # What Fuime owes an operator, for any operator-facing view.
  #
  # The single door to Fuime::PayablesLedger from a template. It exists so that
  # every page showing "what you're owed" shows the SAME figure: before this, the
  # venture dashboard read `Event#balance_available_v2_cents` and the payouts page
  # read the payables total, and the two genuinely disagreed — see the
  # `revenue_waived` branch in FeeEngine::Create for the 4%-charged-twice bug that
  # made them differ, and docs/fuime/MOR_MIGRATION_PLAN.md §3.4 for why the framing
  # matters legally rather than cosmetically.
  #
  # Memoised per event per request: the presenter runs several aggregate queries
  # and the dashboard renders it more than once (the figure, and the hidden sizing
  # element the balance-graph controller measures against).
  def payables_for(event)
    @payables_by_event ||= {}
    @payables_by_event[event.id] ||= Fuime::PayablesLedger.new(event:)
  end
end
