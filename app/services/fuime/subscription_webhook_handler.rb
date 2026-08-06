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

  end
end
