# frozen_string_literal: true

Rails.application.configure do
  auth_token = Credentials.fetch(:TWILIO, :AUTH_TOKEN)

  # Reject unsigned Twilio webhooks before they reach the controller.
  # Only mount the middleware when a token exists: RequestValidator raises
  # if the token is nil, and a missing token must fail closed in production
  # (see TwilioController#verify_twilio_signature).
  if auth_token.present?
    config.middleware.use Rack::TwilioWebhookAuthentication, auth_token, "/twilio/webhook"
  end
end
