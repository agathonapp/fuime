# frozen_string_literal: true

# Fuime: Handle Stripe webhooks for payment links
module Fuime
  class WebhooksController < ApplicationController
    skip_before_action :signed_in_user
    skip_before_action :verify_authenticity_token
    skip_after_action :verify_authorized

    def stripe
      payload = request.body.read
      sig_header = request.headers["Stripe-Signature"]

      begin
        event = Stripe::Webhook.construct_event(
          payload,
          sig_header,
          fuime_webhook_secret
        )
      rescue JSON::ParserError
        render json: { error: "Invalid payload" }, status: :bad_request
        return
      rescue Stripe::SignatureVerificationError
        # In development, allow unsigned events
        if Rails.env.development?
          event = Stripe::Event.construct_from(JSON.parse(payload, symbolize_names: true))
        else
          render json: { error: "Invalid signature" }, status: :bad_request
          return
        end
      end

      # Handle the event
      handler = Fuime::PaymentWebhookHandler.new(event: event)
      handler.handle

      render json: { received: true }, status: :ok
    end

    private

    def fuime_webhook_secret
      ENV.fetch("FUIME_STRIPE_WEBHOOK_SECRET", nil)
    end
  end
end
