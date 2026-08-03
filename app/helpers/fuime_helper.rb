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
end
