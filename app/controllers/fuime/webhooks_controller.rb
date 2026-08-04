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

    # Fuime: connected-account events (onboarding lifecycle).
    #
    # A SEPARATE endpoint with a SEPARATE secret, because Stripe scopes webhook
    # endpoints: one is registered for "your account" and one for "connected
    # accounts", and each has its own signing secret. Verifying a connected-account
    # event against the platform endpoint's secret fails, so these cannot share
    # `#stripe` above no matter how similar the code looks.
    #
    # Signature verification itself is identical — same construct_event, different
    # secret.
    def connect
      payload = request.body.read
      sig_header = request.headers["Stripe-Signature"]

      if connect_webhook_secret.blank?
        unless allow_unsigned_webhooks?
          Rails.logger.error(
            "[Fuime] Rejecting Stripe Connect webhook: FUIME_STRIPE_CONNECT_WEBHOOK_SECRET is not set"
          )
          render json: { error: "Webhook signature verification is not configured" },
                 status: :service_unavailable
          return
        end

        event = Stripe::Event.construct_from(JSON.parse(payload, symbolize_names: true))
        return process_connect_event(event)
      end

      begin
        event = Stripe::Webhook.construct_event(payload, sig_header, connect_webhook_secret)
      rescue JSON::ParserError
        render json: { error: "Invalid payload" }, status: :bad_request
        return
      rescue Stripe::SignatureVerificationError
        Rails.logger.warn("[Fuime] Rejected Stripe Connect webhook with an invalid signature")
        render json: { error: "Invalid signature" }, status: :bad_request
        return
      end

      process_connect_event(event)
    end

    private

    # Application fees are objects on the PLATFORM account, not on the connected
    # account they were collected from, so Stripe delivers their events here rather
    # than to #connect — even though the payment they relate to is a direct charge
    # whose ledger lines were written by Fuime::ConnectPaymentRecorder.
    #
    # Routed narrowly by type rather than by handing the whole platform stream to
    # ConnectPaymentRecorder: it also handles `payment_intent.succeeded`, and pooled
    # payments arriving here are already Fuime::PaymentWebhookHandler's job. Running
    # both over the same event would post one payment through two code paths.
    PLATFORM_EVENTS_FOR_CONNECT_LEDGER = %w[application_fee.refunded].freeze

    # Stripe retries any non-2xx, so a handler crash returning 500 is safe —
    # but a crash that leaves a partial ledger write is not. The handler wraps
    # its writes in a transaction; here we just make failures visible.
    def process_event(event)
      if PLATFORM_EVENTS_FOR_CONNECT_LEDGER.include?(event.type)
        Fuime::ConnectPaymentRecorder.new(event: event).handle
      else
        Fuime::PaymentWebhookHandler.new(event: event).handle
      end

      render json: { received: true }, status: :ok
    rescue => e
      Rails.error.report(e, handled: false, context: { stripe_event_type: event&.type })
      Rails.logger.error("[Fuime] Webhook handler failed for #{event&.type}: #{e.class}: #{e.message}")
      render json: { error: "Handler error" }, status: :internal_server_error
    end

    # Same failure philosophy as #process_event: a handler crash returns 500 so
    # Stripe retries. Losing an `account.updated` silently is how a venture ends
    # up permanently unable to take payments with nothing to point at.
    def process_connect_event(event)
      Fuime::ConnectWebhookHandler.new(event: event).handle
      render json: { received: true }, status: :ok
    rescue => e
      Rails.error.report(e, handled: false, context: { stripe_event_type: event&.type, stripe_account: event&.account })
      Rails.logger.error("[Fuime] Connect webhook handler failed for #{event&.type}: #{e.class}: #{e.message}")
      render json: { error: "Handler error" }, status: :internal_server_error
    end

    def fuime_webhook_secret
      ENV.fetch("FUIME_STRIPE_WEBHOOK_SECRET", nil).presence
    end

    def connect_webhook_secret
      ENV.fetch("FUIME_STRIPE_CONNECT_WEBHOOK_SECRET", nil).presence
    end

    # Only ever in local development, and never when a real Stripe mode is live.
    def allow_unsigned_webhooks?
      Rails.env.development? && !StripeService.live?
    end

  end
end
