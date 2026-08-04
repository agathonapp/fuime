# frozen_string_literal: true

# update as needed, we specify explicitly in code to avoid inter-branch API version conflicts
Stripe.api_version = "2024-06-20"

# Fuime: the global key follows STRIPE_MODE, not Rails.env.
#
# ── The bug this replaces ───────────────────────────────────────────────────
#
# This file used to compute `Rails.env.production? ? :live : :test`, ignoring
# STRIPE_MODE entirely. Fuime runs TEST MODE BY DEFAULT EVEN IN PRODUCTION
# (render.yaml sets STRIPE_MODE=test, because the money-transmission structure is not
# legally settled), so that produced a process in which every screen said "test mode"
# while the global `Stripe.api_key` was the LIVE one.
#
# The consequence was not theoretical: any Stripe call that did not pass `api_key:`
# explicitly would have operated on live money — creating a real Stripe account for a
# minor's business, or issuing a real card, while the UI insisted nothing was real.
# Every Fuime service passes the key explicitly precisely because of this trap (see the
# long note in Fuime::ConnectOnboardingService), but relying on every future caller to
# remember a workaround is not a control. StripeService.mode is the single source of
# truth and this now defers to it.
#
# ── Why `after_initialize` and not a plain assignment ───────────────────────
#
# `StripeService` lives in app/services and is Zeitwerk-managed, so it is NOT available
# while initializers run — referencing it here raises `uninitialized constant
# StripeService`. The alternatives were both worse: duplicating the STRIPE_MODE logic
# inline recreates the two-sources-of-truth problem this change exists to remove, and
# `require_relative`-ing a reloadable app/services file (the pattern application.rb uses
# for app/lib/credentials.rb) puts a Zeitwerk-managed constant outside Zeitwerk's
# control. Deferring one assignment costs nothing: the Stripe gem reads `api_key` per
# request, and nothing in this app makes a Stripe call during boot.
Rails.application.config.after_initialize do
  api_key = Credentials.fetch(:STRIPE, StripeService.mode, :SECRET_KEY)

  if api_key.blank? && Rails.env.test?
    api_key = "sk_fake_#{SecureRandom.alphanumeric(32)}"
    warn("⚠️ Using fake Stripe API key: #{api_key.inspect}")
  end

  Stripe.api_key = api_key
end
