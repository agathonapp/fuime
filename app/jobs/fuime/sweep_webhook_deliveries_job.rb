# frozen_string_literal: true

module Fuime
  # Fuime: pick up deliveries whose scheduled retry never ran.
  #
  # Fuime::DeliverWebhookJob reschedules itself, so in the ordinary case this
  # finds nothing. It exists for the case that mechanism cannot cover: a worker
  # restarted between the failure and the enqueue, and the delivery is now due
  # with nothing holding it. Without this, one unlucky restart silently strands a
  # founder's sale notification forever.
  class SweepWebhookDeliveriesJob < ApplicationJob
    queue_as :low

    BATCH = 100

    def perform
      ::Fuime::WebhookDelivery.due.limit(BATCH).find_each do |delivery|
        ::Fuime::DeliverWebhookJob.perform_later(delivery.id)
      end
    end

  end
end
