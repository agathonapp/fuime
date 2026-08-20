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

  # Asset precompile runs at IMAGE BUILD time, where runtime env vars and
  # secrets are deliberately absent — Rails signals this with
  # SECRET_KEY_BASE_DUMMY. Nothing is served and no uploads can be lost during
  # a build, so failing here only breaks the deploy that would have delivered
  # the fix. These checks belong to boot, not to compilation.
  next if ENV["SECRET_KEY_BASE_DUMMY"].present?

  errors = []
  warnings = []

  # --- 1. Uploaded files must be durable -------------------------------------
  # Active Storage on :local writes to the container filesystem. On Render that
  # is ephemeral: every deploy permanently destroys every uploaded receipt —
  # the exact records Fuime tells families to keep for tax filing.
  #
  # Pre-launch this is a loud WARNING, not a hard failure: no real user is
  # uploading receipts yet, and refusing to boot blocks every other fix from
  # shipping. It escalates to a hard error the moment there is something real
  # to lose — a live Stripe mode, or receipts already in the database.
  #
  # BEFORE LAUNCH: set ACTIVE_STORAGE_SERVICE=amazon and the S3__* credentials.
  storage_service = Rails.application.config.active_storage.service.to_s
  if storage_service == "local"
    stored_receipts =
      begin
        ActiveStorage::Blob.count
      rescue
        0 # table may not exist yet during an initial migrate
      end

    # Fuime: merchant-of-record is a third trigger, added because the first two
    # both miss the launch configuration.
    #
    # Under MoR Fuime is the legal seller, which means Fuime — not the family — owes
    # the buyer a receipt and owes the IRS the records behind its own revenue. Those
    # obligations start with the first sale and do not wait for STRIPE_MODE=live
    # (test-mode sales are still sales somebody made), nor for a blob to already
    # exist, which is a trigger that can only fire after something has been put at
    # risk. Waiting for either is waiting to have something to lose.
    fatal = ENV["STRIPE_MODE"].to_s == "live" ||
            stored_receipts.positive? ||
            Fuime::Features.merchant_of_record?

    message = <<~MSG.strip
      Active Storage is using the :local service in #{Rails.env}.
      On an ephemeral filesystem (Render, Heroku, most containers) every deploy
      DESTROYS all uploaded receipts and documents, with no recovery.
      #{stored_receipts.positive? ? "There are already #{stored_receipts} stored file(s) at risk." : "No files are stored yet."}
      Set ACTIVE_STORAGE_SERVICE=amazon and provide S3__* credentials before launch.
    MSG

    fatal ? errors << message : warnings << message
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
  # Without the secret, Fuime::WebhooksController refuses every Stripe webhook
  # (503), so payments are taken and never reach a ledger.
  #
  # ── Why the payment secret is now an ERROR under merchant-of-record ────────
  #
  # This was a warning on the reasoning that a missing secret degrades the product.
  # Under MoR it does not degrade anything — it breaks the one thing that makes the
  # model lawful. Customer money lands in FUIME's balance and the webhook is the
  # only thing that turns it into a payable the operator is owed. No webhook, no
  # payable: Fuime holds a stranger's money with no record that it owes anybody,
  # which is the shape of check 5 and check 6 arrived at by accident instead of by
  # configuration. That belongs with the conditions that refuse to boot.
  #
  # Still a warning under Connect, where the money never touches Fuime and a lost
  # webhook is a stale mirror of a balance the family can see in Stripe.
  if ENV["FUIME_STRIPE_WEBHOOK_SECRET"].blank?
    message = <<~MSG.strip
      FUIME_STRIPE_WEBHOOK_SECRET is not set. Stripe payment webhooks will be
      refused, so payments will NOT appear on any business ledger. Set it from the
      Stripe dashboard endpoint's signing secret.
    MSG

    if Fuime::Features.merchant_of_record?
      errors << "#{message}\n\nUnder FEATURE_MERCHANT_OF_RECORD this is not a degraded ledger — it is money in Fuime's balance with no record of who it is owed to."
    else
      warnings << message
    end
  end

  # The Connect endpoint's own secret, which was never checked at all.
  #
  # A separate secret because Stripe scopes webhook endpoints separately (see
  # Fuime::WebhooksController#connect). Losing these loses `account.updated`, so a
  # venture finishes Stripe onboarding and Fuime never learns it can sell —
  # `accepts_payments?` stays false with nothing for the family to point at.
  #
  # A warning rather than an error in both models: no money is mis-held, and under
  # MoR there are no connected accounts to hear about, so requiring it would refuse
  # to boot over an endpoint that has nothing to deliver.
  if ENV["FUIME_STRIPE_CONNECT_WEBHOOK_SECRET"].blank?
    warnings << <<~MSG.strip
      FUIME_STRIPE_CONNECT_WEBHOOK_SECRET is not set. Connected-account webhooks
      will be refused, so onboarding completions (account.updated) will be missed
      and a venture that finished Stripe setup may still show as unable to sell.
    MSG
  end

  # --- 3b. The session signing key must not be the one in the repository -----
  #
  # `config/master.key` is COMMITTED (it arrived upstream in 8b96a8b45, "Use
  # default credentials for all non prod environments", and is tracked despite
  # being listed in .gitignore). It decrypts config/credentials.yml.enc, which
  # holds exactly one value: `secret_key_base`.
  #
  # That value signs and encrypts every session and flash cookie. Rails resolves it
  # from ENV["SECRET_KEY_BASE"] first and falls back to credentials — so a
  # production deploy that never set the env var is signing admin sessions with a
  # key that anyone holding a clone of this repository already has. Forging one is
  # then arithmetic, not an attack.
  #
  # Compared rather than merely checked for presence: setting SECRET_KEY_BASE to
  # the committed value (by copying it out of the credentials file, which is the
  # obvious thing to do when a boot check demands the variable) would satisfy a
  # presence check and fix nothing.
  #
  # An error, not a warning. Every other control in this file assumes sessions are
  # trustworthy; if they are not, none of them mean anything.
  begin
    committed_key_base = Rails.application.credentials.secret_key_base.presence
    live_key_base = ENV["SECRET_KEY_BASE"].presence

    if committed_key_base && live_key_base == committed_key_base
      errors << <<~MSG.strip
        SECRET_KEY_BASE is set to the value stored in config/credentials.yml.enc.
        That file is decryptable by anyone with this repository, because
        config/master.key is committed — so this key is public and every session
        and flash cookie in #{Rails.env} is forgeable, including an admin's.

        Generate a fresh one (`rails secret`), set it in the deploy environment,
        and treat the committed value as burned.
      MSG
    elsif committed_key_base && live_key_base.nil?
      errors << <<~MSG.strip
        SECRET_KEY_BASE is not set, so Rails is falling back to the
        secret_key_base in config/credentials.yml.enc. That file is decryptable by
        anyone with this repository, because config/master.key is committed — so
        the key signing every session and flash cookie in #{Rails.env} is public,
        and forging an admin session is arithmetic.

        Generate a fresh one (`rails secret`) and set SECRET_KEY_BASE in the
        deploy environment.
      MSG
    end
  rescue => e
    # A credentials file that cannot be read is not this check's problem to
    # diagnose, and must not be the reason a deploy fails to boot.
    warnings << "Could not verify SECRET_KEY_BASE against the committed credentials (#{e.class}). Confirm by hand that SECRET_KEY_BASE is set in the deploy environment."
  end

  # --- 4. Don't let a fork reach Hack Club production ------------------------
  # CLAUDE.md Rule 4. A stray hcb.hackclub.com host means Fuime emails and links
  # point at someone else's production service.
  #
  # These settings hold a bare host ("fuime.example.com"), but tolerate someone
  # supplying a full URL. Match on the parsed host and only on an exact domain
  # or a real subdomain of it — a substring check both misses nothing and flags
  # too much ("fuime.com/?ref=hackclub.com", "nothackclub.com").
  banned_domains = ["hackclub.com"]

  extract_host = lambda do |value|
    raw = value.to_s.strip
    next nil if raw.empty?

    host =
      begin
        # A bare host has no scheme; give the parser one so it populates #host.
        candidate = raw.match?(/\A[a-zA-Z][a-zA-Z0-9+.-]*:\/\//) ? raw : "//#{raw}"
        URI.parse(candidate).host
      rescue URI::InvalidURIError
        nil
      end

    host&.downcase&.delete_suffix(".")
  end

  hcb_host = [
    ENV["LIVE_URL_HOST"],
    Rails.application.config.action_mailer.default_url_options[:host]
  ].compact.find do |value|
    host = extract_host.call(value)
    next false if host.nil?

    banned_domains.any? { |domain| host == domain || host.end_with?(".#{domain}") }
  end

  if hcb_host
    errors << <<~MSG.strip
      A Hack Club production host is configured (#{hcb_host}).
      Fuime must never point at hackclub.com infrastructure. Set LIVE_URL_HOST
      to a Fuime domain.
    MSG
  end

  # --- 5. Custody cannot be switched on by an env var alone ------------------
  # FEATURE_SPONSOR_BANKING gates every code path that only makes sense if Fuime
  # holds customer funds: stored balances presented as spendable, card issuing,
  # ACH/wire/check origination, balance fronting.
  #
  # Turning it on without a sponsor bank behind it is not a degraded product. It
  # is Fuime holding other people's money with no licence and no partner bank —
  # unlicensed money transmission (18 U.S.C. § 1960, criminal; CLAUDE.md L1), the
  # single failure this fork has been architected around since Phase 0.
  #
  # So the flag alone is not enough to enable it. FUIME_SPONSOR_BANK_PARTNER must
  # also name the institution actually holding the funds. That pairing is the
  # point: an env var can be set by anyone with access to a deploy dashboard, and
  # the second one cannot be answered truthfully unless the arrangement is real.
  # Somebody has to write down a bank's name, which is a question that surfaces
  # the missing partnership rather than hiding it behind a boolean.
  #
  # Same policy as check 2: an ambiguous half-configured money state refuses to
  # boot rather than serving traffic while nobody is sure which way it resolved.
  if Fuime::Features.sponsor_banking?
    partner = ENV["FUIME_SPONSOR_BANK_PARTNER"].to_s.strip

    if partner.empty?
      errors << <<~MSG.strip
        FEATURE_SPONSOR_BANKING is enabled but FUIME_SPONSOR_BANK_PARTNER names no
        institution. This flag turns on stored balances, card issuing, and outbound
        transfer origination — every path that implies Fuime holds customer funds.
        Fuime has no banking licence, so those funds must sit with a sponsor bank,
        and this refuses to boot until someone states which one.

        If you are trying to run the merchant-of-record model (the current
        architecture), you want this flag OFF — money reaching Fuime is Fuime's own
        revenue and what an operator is owed is a payable, not a deposit.
        See docs/fuime/MOR_MIGRATION_PLAN.md.
      MSG
    else
      warnings << <<~MSG.strip
        FEATURE_SPONSOR_BANKING is ON, with #{partner} named as the sponsor bank.
        Fuime is configured to hold customer funds. Confirm the partner-bank
        agreement, the money-transmission analysis, and the FDIC pass-through
        disclosure language are all in place before serving traffic.
      MSG
    end
  end

  # --- 6. Fuime cannot declare itself the seller by setting an env var ---------
  # FEATURE_MERCHANT_OF_RECORD turns on the umbrella model: customer payments land
  # in Fuime's own Stripe balance and operators are paid afterwards as vendors.
  #
  # That is lawful only because the money is Fuime's OWN revenue from a sale Fuime
  # made — which is true only if Fuime is genuinely the seller: Fuime's terms of
  # sale, Fuime's name on the buyer's receipt, Fuime bearing the refund and
  # chargeback obligation. If those documents do not exist, the identical code path
  # is Fuime accepting a stranger's payment and holding it, which is the unlicensed
  # money transmission of check 5 arrived at from the opposite direction (L1).
  #
  # The code cannot tell the difference. Nothing observable at runtime distinguishes
  # "Fuime is the merchant of record" from "Fuime is a conduit that hasn't papered
  # it" — the distinguishing facts live in contracts. So this refuses to guess, and
  # requires FUIME_MOR_COUNSEL_MEMO to cite the memo that says the structure holds.
  #
  # Same device as FUIME_SPONSOR_BANK_PARTNER, for the same reason: an env var can
  # be flipped by anyone with a deploy dashboard, and this second one cannot be
  # answered truthfully unless somebody actually got the advice. It surfaces the
  # missing memo instead of hiding it behind a boolean.
  #
  # MOR_MIGRATION_PLAN §7 Q1 (does the structure hold), Q2 (does it break the
  # independent-contractor characterisation) and Q4 (does Stripe permit it) are the
  # questions that memo has to have answered.
  if Fuime::Features.merchant_of_record?
    memo = ENV["FUIME_MOR_COUNSEL_MEMO"].to_s.strip

    if memo.empty?
      errors << <<~MSG.strip
        FEATURE_MERCHANT_OF_RECORD is enabled but FUIME_MOR_COUNSEL_MEMO cites no
        memo. This flag makes customer money land in Fuime's own Stripe balance.
        That is Fuime's revenue — and therefore lawful without a licence — only if
        Fuime is really the seller of record: Fuime's terms of sale, Fuime's name on
        the receipt, Fuime carrying refunds and chargebacks. Absent that, the same
        code is unlicensed money transmission (18 U.S.C. § 1960; CLAUDE.md L1).

        Set FUIME_MOR_COUNSEL_MEMO to a reference for the advice that says the
        structure holds — see docs/fuime/MOR_MIGRATION_PLAN.md §7 Q1, Q2 and Q4 for
        the questions it must answer.
      MSG
    else
      warnings << <<~MSG.strip
        FEATURE_MERCHANT_OF_RECORD is ON, citing #{memo}. Fuime is configured as the
        legal seller: buyer-facing terms, receipts and the refund/chargeback
        obligation must all name Fuime, and operators must be papered as vendors.
      MSG
    end
  end

  # Structural flags are logged every boot, set or not. They change what Fuime
  # legally is, so "which mode is this box in?" should never require reading the
  # deploy config to answer.
  Fuime::Features.to_h.each do |flag, on|
    warnings << "Structural flag #{flag}=#{on ? 'ON' : 'off'}."
  end

  # --- Report ----------------------------------------------------------------
  warnings.each { |w| Rails.logger.warn("[Fuime safety] #{w}") }

  if errors.any?
    rule = "=" * 72
    numbered = errors.map.with_index(1) { |e, i| "#{i}. #{e}" }.join("\n\n")
    message = "\n\n#{rule}\n" \
              "FUIME SAFETY CHECK FAILED — refusing to boot\n" \
              "#{rule}\n\n" \
              "#{numbered}\n\n" \
              "#{rule}\n" \
              "Set FUIME_SKIP_SAFETY_CHECK=true to bypass (recovery work only).\n" \
              "#{rule}\n\n"

    Rails.logger.fatal(message)
    raise message
  end
end
