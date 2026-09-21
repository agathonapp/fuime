# frozen_string_literal: true

module Fuime
  module Oncall
    module Checks
      # Fuime: are the webhooks Fuime sends OUT to founders' integrations landing?
      #
      # Not to be confused with the webhooks Stripe sends IN — that direction is
      # Checks::MoneyIn and the missed-payment sweep. This one is about a founder
      # who wired Fuime into their own Discord bot or fulfilment script and has
      # been quietly receiving nothing.
      #
      # `Fuime::WebhookDelivery` gives up after five attempts over roughly 24
      # hours and marks the row `failed`. Nobody was reading that column. From
      # the founder's side the failure is invisible in the worst way: orders keep
      # succeeding on Fuime and stop arriving in their system, so they conclude
      # Fuime dropped the sale.
      #
      # ── Per-endpoint, not per-delivery ────────────────────────────────────
      #
      # One endpoint failing 40 times is one problem. Keying on the endpoint
      # means it pages once, and an unrelated second endpoint failing later still
      # gets its own incident instead of being swallowed by the first one's
      # deduplication.
      class WebhookDeliveries < Check
        WINDOW = 6.hours
        # One failure is a flaky host. Five inside six hours, after the delivery
        # machinery has already retried each of them five times, is an endpoint
        # that is not coming back on its own.
        FAILURE_THRESHOLD = 5

        def call
          counts = ::Fuime::WebhookDelivery
                   .where(status: "failed")
                   .where(updated_at: WINDOW.ago..)
                   .group(:fuime_webhook_endpoint_id)
                   .count

          counts.filter_map do |endpoint_id, failures|
            next if failures < FAILURE_THRESHOLD

            endpoint = ::Fuime::WebhookEndpoint.find_by(id: endpoint_id)

            finding(
              key: "webhooks.endpoint_failing.#{endpoint_id}",
              title: "#{failures} webhook deliveries failed to #{endpoint&.event&.name || "endpoint ##{endpoint_id}"}",
              # Sev-3: it is somebody's integration, not Fuime's money or the
              # law, and it is recoverable by replaying. It belongs in the
              # morning digest, not in the night.
              severity: :sev3,
              endpoint_id:,
              venture: endpoint&.event&.name,
              failures_in_window: failures,
              window_hours: WINDOW.in_hours.to_i
            )
          end
        end

      end
    end
  end
end
