# frozen_string_literal: true

# Fuime: recover MoR sales whose webhook never arrived.
#
# Stripe retries on non-2xx, but a missed delivery is still a real failure mode:
# `stripe listen` was not running, the endpoint was pointed at the marketing
# site, or only `checkout.session.completed` was registered before this handler
# started posting that event. The first sale that does not hit the ledger is
# how a founder churns the group chat (TEEN_GROWTH G10).
#
# Lists recent succeeded PaymentIntents on the PLATFORM account (MoR charges;
# no `stripe_account:`), and feeds each one through PaymentWebhookHandler as if
# `payment_intent.succeeded` had just been delivered. The handler is idempotent
# on the intent id, so a sale that already landed is a no-op.
#
# Skips invoice-backed intents — those are Stripe Billing (family plan), not
# a storefront sale.
#
# Does not talk to connected accounts. Production money-in is merchant-of-record
# (`render.yaml`); Connect recovery is a different job.
module Fuime
  class MissedMorPaymentSweep
    DEFAULT_SINCE = 24.hours
    DEFAULT_LIMIT = 100

    def self.sweep!(since: DEFAULT_SINCE.ago, limit: DEFAULT_LIMIT)
      new(since:, limit:).sweep!
    end

    def initialize(since:, limit: DEFAULT_LIMIT)
      @since = since
      @limit = limit
    end

    def sweep!
      posted = 0
      skipped = 0

      list.data.each do |intent|
        unless postable?(intent)
          skipped += 1
          next
        end

        result = Fuime::PaymentWebhookHandler.new(event: synthetic_event(intent)).handle
        if result
          posted += 1
          Rails.logger.info("[Fuime] backfilled missed MoR payment #{intent.id}")
        else
          skipped += 1
        end
      end

      Rails.logger.info("[Fuime] MissedMorPaymentSweep posted=#{posted} skipped=#{skipped}")
      { posted:, skipped: }
    end

    private

    def list
      Stripe::PaymentIntent.list(
        { created: { gte: @since.to_i }, limit: @limit },
        { api_key: StripeService.secret_key }
      )
    end

    def postable?(intent)
      return false unless intent.status.to_s == "succeeded"
      return false if intent.try(:invoice).present?

      metadata = intent.metadata
      event_id = metadata && (metadata["fuime_event_id"] || metadata[:fuime_event_id])
      event_id.present?
    end

    def synthetic_event(intent)
      Stripe::Event.construct_from(
        id: "evt_fuime_backfill_#{intent.id}",
        type: "payment_intent.succeeded",
        livemode: intent.try(:livemode),
        data: { object: intent }
      )
    end
  end
end
