# frozen_string_literal: true

module Fuime
  # Fuime: send one queued webhook, and reschedule itself if it failed.
  #
  # Self-rescheduling rather than swept by a cron: the backoff ladder is
  # per-delivery (Fuime::WebhookDelivery::BACKOFF), so the delivery itself knows
  # when it is next due and a sweeper would only re-derive that. There IS a
  # sweeper too — Fuime::SweepWebhookDeliveriesJob — but it exists for the case
  # this cannot cover: a job lost to a worker restart.
  class DeliverWebhookJob < ApplicationJob
    queue_as :low

    def perform(delivery_id)
      delivery = ::Fuime::WebhookDelivery.find_by(id: delivery_id)
      return if delivery.blank?
      # Already settled by the sweeper or an earlier run of this job. At-least-
      # once delivery means duplicates reach a receiver; it does not mean Fuime
      # should manufacture them.
      return unless delivery.status == "pending"
      return unless delivery.endpoint&.enabled?

      ::Fuime::WebhookDeliverer.new(delivery).call

      delivery.reload
      return unless delivery.status == "pending" && delivery.next_attempt_at.present?

      self.class.set(wait_until: delivery.next_attempt_at).perform_later(delivery.id)
    end

  end
end
