# frozen_string_literal: true

module Fuime
  # Fuime: something happened to a venture; tell whoever asked to be told.
  #
  # The single entry point for emitting an outbound webhook. Callers say WHAT
  # happened and hand over the object; this decides who hears about it, builds
  # the envelope, and queues delivery.
  #
  # ── Why it never raises ──────────────────────────────────────────────────
  #
  # Every caller is on a money path — the webhook handler that posts a sale to
  # the ledger, and the payout run. A founder's own server being unreachable, or
  # their endpoint row being malformed, must never be able to stop a sale from
  # landing or a payout from being recorded. So this swallows and reports, the
  # same posture as Fuime::Sale.record!.
  class WebhookEmitter
    # The event vocabulary, kept small and named for things a founder recognises
    # rather than for Stripe's internals. Paddle publishes ~60; most of theirs
    # describe entities Fuime does not have. Adding one is cheap; removing one
    # after somebody has built on it is not, so this starts narrow.
    SALE_COMPLETED = "sale.completed"
    SALE_REFUNDED = "sale.refunded"
    PAYOUT_PAID = "payout.paid"

    EVENT_TYPES = [SALE_COMPLETED, SALE_REFUNDED, PAYOUT_PAID].freeze

    def self.emit(event:, event_type:, data:, idempotency_key: nil)
      new(event:, event_type:, data:, idempotency_key:).emit
    end

    def initialize(event:, event_type:, data:, idempotency_key: nil)
      @event = event
      @event_type = event_type
      @data = data
      @idempotency_key = idempotency_key
    end

    def emit
      return [] unless EVENT_TYPES.include?(@event_type)
      return [] if @event.blank?

      endpoints = ::Fuime::WebhookEndpoint.enabled.where(event: @event).to_a
      return [] if endpoints.empty?

      # One id for the occurrence, shared across every endpoint that hears about
      # it — so a founder with two endpoints sees one event twice, not two
      # events, and can correlate them.
      event_id = @idempotency_key.presence || "evt_#{SecureRandom.hex(12)}"
      payload = envelope(event_id)

      endpoints.filter_map do |endpoint|
        queue(endpoint, event_id, payload)
      end
    rescue => e
      Rails.error.report(e, handled: true,
                            context: { event_id: @event&.id, event_type: @event_type })
      []
    end

    private

    def envelope(event_id)
      {
        id: event_id,
        type: @event_type,
        occurred_at: Time.current.iso8601,
        # Named so a founder receiving events for several of their businesses can
        # tell them apart without a lookup.
        venture: { id: @event.id, slug: @event.slug, name: @event.name },
        data: @data
      }
    end

    def queue(endpoint, event_id, payload)
      delivery = ::Fuime::WebhookDelivery.create!(
        endpoint:, event_id:, event_type: @event_type, payload:,
        status: "pending", next_attempt_at: Time.current
      )
      ::Fuime::DeliverWebhookJob.perform_later(delivery.id)
      delivery
    rescue ActiveRecord::RecordNotUnique
      # This exact event was already queued for this endpoint — a replayed Stripe
      # webhook reaching the emitter twice. Correct to ignore.
      nil
    end

  end
end
