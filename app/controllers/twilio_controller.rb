# frozen_string_literal: true

class TwilioController < ActionController::Base
  # CSRF is skipped only because Twilio cannot send a Rails authenticity
  # token. Requests are authenticated by X-Twilio-Signature instead.
  protect_from_forgery except: :webhook
  before_action :verify_twilio_signature

  def webhook
    Twilio::ProcessWebhookJob.perform_later(webhook_params: webhook_params.to_h)

    respond_to do |format|
      format.xml { render xml: "<Response></Response>" }
    end
  end

  private

  def verify_twilio_signature
    auth_token = Credentials.fetch(:TWILIO, :AUTH_TOKEN)

    if auth_token.blank?
      unless allow_unsigned_twilio_webhooks?
        Rails.logger.error("[Fuime] Rejecting Twilio webhook: TWILIO__AUTH_TOKEN is not set")
        head :forbidden
      end
      return
    end

    validator = ::Twilio::Security::RequestValidator.new(auth_token)
    signature = request.headers["X-Twilio-Signature"].to_s

    unless validator.validate(request.url, request.POST, signature)
      Rails.logger.warn("[Fuime] Rejected Twilio webhook with an invalid signature")
      head :forbidden
    end
  end

  # Local `stripe listen`-style development only. Production and test fail
  # closed when the validator cannot be configured.
  def allow_unsigned_twilio_webhooks?
    Rails.env.development?
  end

  def webhook_params
    params.permit(:From, :To, :Body, :NumMedia, *media_params)
  end

  def media_params
    num_media = params["NumMedia"].to_i
    (0...num_media).flat_map { |i| ["MediaUrl#{i}", "MediaContentType#{i}"] }
  end

end
