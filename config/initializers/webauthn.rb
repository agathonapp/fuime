# frozen_string_literal: true

WebAuthn.configure do |config|
  if Rails.env.staging?
    # Use the Heroku review app's origin
    heroku_app_name = ENV["HEROKU_APP_NAME"]
    config.allowed_origins = ["https://#{heroku_app_name}.herokuapp.com"]
  elsif Rails.env.production?
    # WebAuthn checks the browser's origin against this list, so a wrong or
    # empty value makes every security key fail to register and to sign in.
    # LIVE_URL_HOST isn't always set, which produced a bare "https://" — fall
    # back to the hostname Render always injects. Both are listed so keys
    # registered on the Render URL keep working after a custom domain is added.
    hosts = [Credentials.fetch(:LIVE_URL_HOST), ENV["RENDER_EXTERNAL_HOSTNAME"]].compact_blank.uniq
    config.allowed_origins = hosts.map { |h| "https://#{h}" }
  else
    config.allowed_origins = ["http://#{Credentials.fetch(:TEST_URL_HOST)}"]
  end

  # Shown by the browser/OS in the passkey prompt — this is user-facing.
  config.rp_name = "Fuime"
end
