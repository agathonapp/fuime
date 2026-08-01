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

      # A missing secret must never mean "accept anything" — this endpoint
      # writes to business ledgers, so an unverified event is an attacker-
      # controlled ledger line. Refuse rather than degrade.
      if fuime_webhook_secret.blank?
        unless allow_unsigned_webhooks?
          Rails.logger.error(
            "[Fuime] Rejecting Stripe webhook: FUIME_STRIPE_WEBHOOK_SECRET is not set"
          )
          render json: { error: "Webhook signature verification is not configured" },
                 status: :service_unavailable
          return
        end

        # Local development with `stripe listen` and no secret configured.
        event = Stripe::Event.construct_from(JSON.parse(payload, symbolize_names: true))
        return process_event(event)
      end

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
        Rails.logger.warn("[Fuime] Rejected Stripe webhook with an invalid signature")
        render json: { error: "Invalid signature" }, status: :bad_request
        return
      end

      process_event(event)
    end

    private

    # Stripe retries any non-2xx, so a handler crash returning 500 is safe —
    # but a crash that leaves a partial ledger write is not. The handler wraps
    # its writes in a transaction; here we just make failures visible.
    def process_event(event)
      Fuime::PaymentWebhookHandler.new(event: event).handle
      render json: { received: true }, status: :ok
    rescue => e
      Rails.error.report(e, handled: false, context: { stripe_event_type: event&.type })
      Rails.logger.error("[Fuime] Webhook handler failed for #{event&.type}: #{e.class}: #{e.message}")
      render json: { error: "Handler error" }, status: :internal_server_error
    end

    def fuime_webhook_secret
      ENV.fetch("FUIME_STRIPE_WEBHOOK_SECRET", nil).presence
    end

    # Only ever in local development, and never when a real Stripe mode is live.
    def allow_unsigned_webhooks?
      Rails.env.development? && !StripeService.live?
    end
  end
end
