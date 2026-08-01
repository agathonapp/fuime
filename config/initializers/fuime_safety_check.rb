# frozen_string_literal: true

# Fuime: boot-time safety rails.
#
# Fuime serves minors and handles money. Several classes of misconfiguration are
# not "degraded service" but active harm — losing a family's tax receipts,
# silently moving real money, or telling a teen their account is parent-signed
# when it isn't. This initializer surfaces those at boot.
#
# Policy:
#   RAISE on conditions that cause data loss or unauthorised money movement.
#   WARN  on conditions that degrade the product but are safe.
#
# Set FUIME_SKIP_SAFETY_CHECK=true to bypass (intended for one-off rake/console
# recovery work, never for serving traffic).
Rails.application.config.after_initialize do
  next if ENV["FUIME_SKIP_SAFETY_CHECK"] == "true"
  next unless Rails.env.production? || Rails.env.staging?

  errors = []
  warnings = []

  # --- 1. Uploaded files must be durable -------------------------------------
  # Active Storage on :local writes to the container filesystem. On Render that
  # is ephemeral: every deploy permanently destroys every uploaded receipt —
  # the exact records Fuime tells families to keep for tax filing. Silent and
  # unrecoverable, so this is a hard failure.
  storage_service = Rails.application.config.active_storage.service.to_s
  if storage_service == "local"
    errors << <<~MSG.strip
      Active Storage is using the :local service in #{Rails.env}.
      On an ephemeral filesystem (Render, Heroku, most containers) every deploy
      DESTROYS all uploaded receipts and documents, with no recovery.
      Set ACTIVE_STORAGE_SERVICE=amazon and provide S3__* credentials.
    MSG
  end

  # --- 2. Live money movement requires an explicit, credentialed decision -----
  # StripeService.mode defaults to :test. Reaching :live means someone set
  # STRIPE_MODE=live on purpose; make sure the keys actually exist so we fail
  # here rather than mid-payment.
  if StripeService.live?
    if StripeService.secret_key.blank?
      errors << <<~MSG.strip
        STRIPE_MODE=live but no live secret key is configured
        (STRIPE__LIVE__SECRET_KEY). Refusing to boot in live mode without
        credentials.
      MSG
    end

    warnings << <<~MSG.strip
      STRIPE_MODE=live — Fuime is configured to move REAL money.
      Confirm the money-transmission structure is legally settled before
      accepting payments (docs/fuime/PRODUCTION_READINESS.md §1.5).
    MSG
  else
    # Test mode in production is the intended interim posture, but it must never
    # be accidental — an operator should see it in the logs every boot.
    warnings << "Stripe is in TEST mode in #{Rails.env}. No real money will move."

    # A live key present while in test mode means someone half-finished a
    # cutover. Refuse: the risk of picking up the wrong key is too high.
    if Credentials.fetch(:STRIPE, :LIVE, :SECRET_KEY).present?
      errors << <<~MSG.strip
        A live Stripe secret key is present but STRIPE_MODE is not "live".
        This is an ambiguous half-configured state. Either set STRIPE_MODE=live
        deliberately, or remove the live credentials.
      MSG
    end
  end

  # --- 3. Webhooks must be signature-verified --------------------------------
  # Without the secret, Fuime::WebhooksController rejects every Stripe webhook
  # in production (400), so payments are taken and never reach a ledger.
  if ENV["FUIME_STRIPE_WEBHOOK_SECRET"].blank?
    warnings << <<~MSG.strip
      FUIME_STRIPE_WEBHOOK_SECRET is not set. Stripe payment webhooks will be
      rejected with a signature error, so payments will NOT appear on any
      business ledger. Set it from the Stripe dashboard endpoint's signing secret.
    MSG
  end

  # --- 4. Don't let a fork reach Hack Club production ------------------------
  # CLAUDE.md Rule 4. A stray hcb.hackclub.com host means Fuime emails and links
  # point at someone else's production service.
  hcb_host = [
    ENV["LIVE_URL_HOST"],
    Rails.application.config.action_mailer.default_url_options[:host]
  ].compact.find { |h| h.to_s.include?("hackclub.com") }

  if hcb_host
    errors << <<~MSG.strip
      A Hack Club production host is configured (#{hcb_host}).
      Fuime must never point at hackclub.com infrastructure. Set LIVE_URL_HOST
      to a Fuime domain.
    MSG
  end

  # --- Report ----------------------------------------------------------------
  warnings.each { |w| Rails.logger.warn("[Fuime safety] #{w}") }

  if errors.any?
    message = "\n\n" + ("=" * 72) + "\n" \
              "FUIME SAFETY CHECK FAILED — refusing to boot\n" +
              ("=" * 72) + "\n\n" +
              errors.map.with_index(1) { |e, i| "#{i}. #{e}" }.join("\n\n") +
              "\n\n" + ("=" * 72) + "\n" \
              "Set FUIME_SKIP_SAFETY_CHECK=true to bypass (recovery work only).\n" +
              ("=" * 72) + "\n\n"

    Rails.logger.fatal(message)
    raise message
  end
end
