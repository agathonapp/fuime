# frozen_string_literal: true

# Fuime-specific view helpers.
module FuimeHelper
  # An inline SVG QR code for `url`, for pages served by the admin bundle,
  # which does not register the <qr-code> element the app bundle uses
  # (fuime/offers/_share_link). Same library the raffle and donation pages
  # already use. The output is RQRCode's own markup, not user content.
  def fuime_qr_svg(url, size: 4)
    svg = RQRCode::QRCode.new(url).as_svg(
      module_size: size, standalone: true, use_path: true, viewbox: true,
      color: "1f2d3d", fill: "ffffff"
    )
    svg.html_safe # rubocop:disable Rails/OutputSafety
  end

  # Standing status line for marketing and app chrome. Stripe mode is not named
  # here; the seller of record is Ninth Street Labs, LLC (Fuime is the brand).
  def fuime_status_line
    "Private beta · live payments. " \
      "#{Rails.configuration.constants.legal_entity_name} (Fuime) is the seller of record."
  end

  # Ownership sentence shared by the app footer and the storefront disclosure.
  # Guardians are the legal payee, not the owner of a Stripe connected account.
  # Legal merchant name on sold-by / receipt / checkout copy. Fuime is the brand
  # and may appear next to this; it is not a second seller.
  def fuime_legal_seller
    Rails.configuration.constants.legal_entity_name
  end

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

  # Is the person reading this page about to make a TEST purchase?
  #
  # True only for an operator of this venture while Sandbox Mode is on — the
  # exact condition Fuime::CheckoutsController#sandbox_checkout? uses to divert
  # a Buy click, asked here so the banner and the behaviour cannot disagree. A
  # customer reading the same page gets no banner because for them nothing is
  # different: their Buy is real either way.
  def sandbox_rehearsal?(event)
    return false if event.blank? || !event.sandbox_mode?
    return false if current_user.blank?
    # Must match Fuime::CheckoutsController#sandbox_checkout? condition for
    # condition. This one is load-bearing rather than cosmetic: this predicate
    # also opens the Buy button on a venture that cannot take real money
    # (`@accepts_payments ||=`), so if it said yes where the checkout said no,
    # the founder's click would fall through to the LIVE Stripe path — a real
    # charge, on a page that just told them it was a test.
    return false unless ::StripeService.sandbox_available?

    EventPolicy.new(current_user, event).manage_sandbox?
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

  # A "per what?" example that suits the business, for the offer wizard.
  #
  # The field's placeholder was hard-coded "per lawn", so a dog walker, a tutor
  # and an illustrator were each shown a lawn-care example on the screen where
  # they name their own unit. Unlike the price box next to it — where any number
  # would read as a rate Fuime suggested — a unit is a grammar hint, and one that
  # matches the trade is strictly more useful than one that does not.
  #
  # Falls back to "per hour", which fits more teen work than any other single
  # answer and suggests nothing about price.
  UNIT_LABEL_PLACEHOLDERS = {
    "crafts"   => "per piece",
    "services" => "per visit",
    "digital"  => "per download",
    "food"     => "per order"
  }.freeze

  def unit_label_placeholder_for(event)
    UNIT_LABEL_PLACEHOLDERS.fetch(event&.business_category, "per hour")
  end

  # FUIME: the Stripe dashboard link for a Fuime ledger line.
  #
  # Every money line Fuime posts is keyed on the Stripe object it came from —
  # `fuime_<pi_…>` for a sale, `fuime_fee_<pi_…>` for Fuime's cut,
  # `fuime_stripefee_<pi_…>` for Stripe's, `fuime_payout_<po_…>` for money going
  # out (see Fuime::VentureLedger's key builders). A PENDING row carries that key
  # on RawPendingDonationTransaction#donation_transaction_id; a SETTLED row
  # carries it bracketed on the end of its memo (VentureLedger.settled_memo).
  # Either string can be passed here.
  #
  # This exists because the admin ledger pages inherited HCB's "Actions" columns,
  # which were built around mapping a bank feed to an org. Fuime has no bank feed
  # — the one genuinely useful action left on a ledger row is "show me this at
  # Stripe", and under merchant-of-record that is Fuime's own platform account,
  # so a plain dashboard URL reaches it.
  #
  # Honours StripeService.mode, so a test-mode fork links at /test/… instead of
  # sending an admin to a live-mode page that does not exist.
  #
  # Returns nil for a line with no Stripe object behind it (Playground Mode
  # sample money, school-funded lines), so callers render nothing rather than a
  # dead link.
  FUIME_STRIPE_DASHBOARD_PATHS = {
    "pi" => "payments",
    "ch" => "payments",
    "po" => "payouts"
  }.freeze

  def fuime_stripe_dashboard_url(ledger_key)
    match = ledger_key.to_s.match(/(?:\A|[^A-Za-z0-9])(pi|ch|po)_([A-Za-z0-9]+)/)
    return if match.nil?

    resource = FUIME_STRIPE_DASHBOARD_PATHS[match[1]]
    return if resource.nil?

    base = "https://dashboard.stripe.com"
    base += "/test" unless ::StripeService.live?

    "#{base}/#{resource}/#{match[1]}_#{match[2]}"
  end
end
