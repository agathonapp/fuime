# frozen_string_literal: true

WebAuthn.configure do |config|
  # The one hostname the browser will be on.
  #
  # A WebAuthn credential is bound to a single RP ID at registration time, so
  # there is no such thing as a key that works on two domains. CanonicalHost
  # (wired up in config/application.rb) 301s every other hostname to this one,
  # which means one allowed origin is not a limitation — it's the whole design.
  host =
    if Rails.env.staging?
      # The Heroku review app's own hostname.
      "#{ENV['HEROKU_APP_NAME']}.herokuapp.com"
    elsif Rails.env.production?
      # LIVE_URL_HOST isn't always set. Render always injects its own hostname,
      # and that's also the host CanonicalHost leaves alone until a custom
      # domain exists, so the two agree.
      Credentials.fetch(:LIVE_URL_HOST, fallback: ENV["RENDER_EXTERNAL_HOSTNAME"])
    else
      # Same fallback as config/environments/test.rb. Without it, an
      # unset TEST_URL_HOST leaves allowed_origins empty, rp_id nil,
      # and every FakeClient / browser ceremony raises URI::InvalidURIError.
      Credentials.fetch(:TEST_URL_HOST, fallback: "localhost:3000")
    end

  scheme = Rails.env.local? ? "http" : "https"
  origins = host.present? ? ["#{scheme}://#{host}"] : []

  # WebAuthn checks the browser's origin against this list, so a wrong or empty
  # value makes every security key fail to register and to sign in.
  config.allowed_origins = origins

  # Set the RP ID explicitly rather than letting the gem infer it.
  #
  # webauthn-ruby only infers an RP ID when EXACTLY ONE origin is allowed:
  # `AuthenticatorResponse#rp_id_from_origin` returns nil for a list of two or
  # more. We used to list the custom domain AND the Render hostname, in the hope
  # that keys registered on the Render URL would survive the move to fuime.com.
  # They can't — the RP ID is baked into the credential — and listing both made
  # the inferred RP ID nil, so `valid_rp_id?` returned false and EVERY
  # registration and sign-in failed with WebAuthn::RpIdVerificationError.
  #
  # The suite never caught it because the test environment only ever has one
  # origin, which is exactly the case where inference works.
  #
  # An RP ID is a bare domain: no scheme, no port. TEST_URL_HOST carries a port
  # in development ("localhost:3000"), so parse the host out of the origin
  # instead of interpolating the raw value.
  config.rp_id = URI.parse(origins.first).host if origins.any?

  # Shown by the browser/OS in the passkey prompt — this is user-facing.
  config.rp_name = "Fuime"
end
