# frozen_string_literal: true

# Fuime: Handle Stripe webhook events for incoming payments
# Maps payments to businesses via event_id in metadata
module Fuime
  class PaymentWebhookHandler
    def initialize(event:)
      @stripe_event = event
    end

    def handle
      case @stripe_event.type
      when "checkout.session.completed"
        handle_checkout_completed
      when "payment_intent.succeeded"
        handle_payment_succeeded
      else
        Rails.logger.info "[Fuime] Ignoring webhook event: #{@stripe_event.type}"
      end
    end

    private

    def handle_checkout_completed
      session = @stripe_event.data.object
      metadata = session.metadata

      return unless metadata&.fuime_event_id.present?

      event = Event.find_by(id: metadata.fuime_event_id)
      return unless event

      amount_cents = session.amount_total
      fee_cents = metadata.fuime_fee_cents&.to_i || 0

      Rails.logger.info "[Fuime] Payment received for #{event.name}: $#{amount_cents / 100.0} (fee: $#{fee_cents / 100.0})"

      # TODO: Create canonical pending transaction through HCB's ledger pipeline
      # For hackathon demo, we'll just log it
      # In production, this would:
      # 1. Create a RawStripeTransaction
      # 2. Let the existing pipeline map it to the event's ledger
      # 3. Split out the platform fee

      true
    end

    def handle_payment_succeeded
      payment_intent = @stripe_event.data.object
      metadata = payment_intent.metadata

      return unless metadata&.fuime_event_id.present?

      event = Event.find_by(id: metadata.fuime_event_id)
      return unless event

      amount_cents = payment_intent.amount_received
      fee_cents = metadata.fuime_fee_cents&.to_i || 0

      Rails.logger.info "[Fuime] PaymentIntent succeeded for #{event.name}: $#{amount_cents / 100.0} (fee: $#{fee_cents / 100.0})"

      true
    end
  end
end
