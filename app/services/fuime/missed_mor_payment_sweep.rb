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
# Skips invoice-backed intents. Those are Stripe Billing, and both kinds of
# Billing invoice are already covered elsewhere: Fuime's own family plan is not a
# venture sale at all, and an operator's subscription renewal is posted from
# `invoice.paid` by PaymentWebhookHandler — where the subscription's metadata
# actually is. Stripe does not copy that metadata onto the invoice's
# PaymentIntent, so an intent swept up here would arrive with no venture to
# attribute it to and be dropped anyway.
#
# ⚠️ This means a DROPPED `invoice.paid` is not recovered by this sweep. A
# subscription-aware backfill has to list invoices, not PaymentIntents, and does
# not exist yet.
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

      each_intent do |intent|
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

    # Stripe pages at `limit`. A busy day can exceed one page; walking only
    # `list.data` would silently leave later sales unrecovered.
    def each_intent(&block)
      result = list
      if result.respond_to?(:auto_paging_each)
        result.auto_paging_each(&block)
      else
        Array(result.try(:data)).each(&block)
      end
    end

    def postable?(intent)
      return false unless intent.status.to_s == "succeeded"
      # See the class header: invoice-backed intents belong to Stripe Billing and
      # are posted from `invoice.paid`, not from here.
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
