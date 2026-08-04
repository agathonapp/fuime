# frozen_string_literal: true

# Be sure to restart your server when you modify this file.

# Configure parameters to be partially matched (e.g. passw matches password) and filtered from the log file.
# Use this to limit dissemination of sensitive information.
# See the ActiveSupport::ParameterFilter documentation for supported notations and behaviors.
Rails.application.config.filter_parameters += [
  :passw, :email, :secret, :token, :_key, :crypt, :salt, :certificate, :otp, :ssn, :cvv, :cvc,
  # Anchored: filter keys match as substrings, so a bare :tin would also redact
  # `routing_number` and `destination_*`, and a bare :ein would redact `being`.
  /\A(us_?)?f?tin\z/i, /\Aein\z/i,

  # ── Fuime: guardian identity collection ────────────────────────────────────
  #
  # The `:cards_enabled` profile sets `requirement_collection = application`, which
  # means a guardian's identity details POST through Fuime on their way to Stripe
  # (Fuime::RequirementCollectionService). Those params must never reach a log line.
  #
  # `:ssn` above already covers `ssn_last_4` by substring, but NOT `id_number` — which
  # is Stripe's field for the FULL Social Security number, the most sensitive value the
  # application handles. That gap is the reason this block exists.
  #
  # Anchored where a substring match would be too greedy: bare `:address` would redact
  # `email_address` and `ip_address` (the latter is load-bearing for the consent record
  # and for debugging), and bare `:dob` would catch unrelated keys.
  :id_number, :document_front, :document_back,
  /\Adob\z/i, /\Adate_of_birth\z/i, /\Abirthday\z/i,
  /\Aid_document\z/i,
  /\Aline[12]\z/i, /\Apostal_code\z/i,
  /\A(first|last|full|legal)_name\z/i
]
