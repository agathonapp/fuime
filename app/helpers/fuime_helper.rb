# frozen_string_literal: true

# Fuime-specific view helpers.
module FuimeHelper
  # Standing status line for marketing and app chrome. Stripe mode is not named
  # here; the seller of record is Ninth Street Labs, LLC (Fuime is the brand).
  def fuime_status_line
    "Private beta · live payments. " \
      "#{Rails.configuration.constants.legal_entity_name} (Fuime) is the seller of record."
  end

  # Ownership sentence shared by the app footer and the storefront disclosure.
  # Guardians are the legal payee, not the owner of a Stripe connected account.
  def fuime_footer_ownership
    "#{Rails.configuration.constants.legal_entity_name}, doing business as Fuime, " \
      "is the seller of record on purchases. Guardians are the legal payee on " \
      "operator payouts and must approve the destination before the first payout; " \
      "young founders run the venture day to day."
  end

  # Whether to show the leftover Stripe-not-live banner.
  #
  # Hidden once Stripe is live, and suppressed in development and test so a view
  # spec does not have to dance around it. The banner copy itself is the status
  # line, not a claim about simulated payments.
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
  # rubocop:disable Rails/HelperInstanceVariable -- a per-request memo, not state
  def payables_for(event)
    @payables_by_event ||= {}
    @payables_by_event[event.id] ||= Fuime::PayablesLedger.new(event:)
  end
  # rubocop:enable Rails/HelperInstanceVariable
end
