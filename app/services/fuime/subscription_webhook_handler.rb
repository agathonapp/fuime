# frozen_string_literal: true

# Fuime: mirrors Stripe Billing subscription state onto Fuime::Subscription.
# Webhook-shaped like the Connect recorders: new(event: <Stripe::Event>).handle.
module Fuime
  class SubscriptionWebhookHandler
    HANDLED_TYPES = %w[
      customer.subscription.created
      customer.subscription.updated
      customer.subscription.deleted
    ].freeze

    def initialize(event:)
      @stripe_event = event
    end

    def handle
      return nil unless HANDLED_TYPES.include?(@stripe_event.type)

      subscription = @stripe_event.data.object

      # ── The operator-sale guard ──────────────────────────────────────────
      #
      # This class mirrors FUIME's OWN subscription — the family software plan —
      # and it finds the row by `fuime_event_id`. Once an operator can sell a
      # monthly product, their customer's subscription lands on this same
      # platform account carrying that same key, because the ledger needs it to
      # attribute the renewal.
      #
      # Without this check, a buyer cancelling a teenager's $9.99 tool would be
      # applied to that venture's Fuime plan row: `sync_from_stripe!` would write
      # the buyer's `canceled` status and the buyer's `current_period_end` over
      # the venture's own billing state. One customer's churn would cancel the
      # founder's Fuime subscription, and nothing would report it.
      #
      # Stamped rather than inferred: see Fuime::PaymentLinkService::OPERATOR_SALE_KIND.
      if operator_sale?(subscription)
        Rails.logger.info(
          "[Fuime] #{@stripe_event.type} #{subscription.id} is an operator's own sale, " \
          "not a Fuime plan; ignoring here"
        )
        return nil
      end

      event_id = subscription.metadata.try(:[], "fuime_event_id") ||
                 subscription.metadata.try(:[], :fuime_event_id)

      guardian_id = subscription.metadata.try(:[], "fuime_guardian_user_id") ||
                    subscription.metadata.try(:[], :fuime_guardian_user_id)

      record = if event_id.present?
                 Fuime::Subscription.find_by(event_id:)
               elsif guardian_id.present?
                 Fuime::Subscription.family.find_by(billed_to_id: guardian_id)
               else
                 Fuime::Subscription.find_by(stripe_subscription_id: subscription.id)
               end

      if record.nil?
        # Same posture as the Connect recorders: log, never raise — Stripe
        # legitimately replays events for subscriptions a database restore or a
        # test-mode purge no longer knows about, and a raise makes it retry
        # forever.
        Rails.logger.warn("[Fuime] #{@stripe_event.type} for unknown subscription #{subscription.id}")
        return nil
      end

      record.sync_from_stripe!(subscription)
    end

    private

    def operator_sale?(subscription)
      kind = subscription.metadata.try(:[], "fuime_subscription_kind") ||
             subscription.metadata.try(:[], :fuime_subscription_kind)

      kind.to_s == ::Fuime::PaymentLinkService::OPERATOR_SALE_KIND
    end

  end
end
