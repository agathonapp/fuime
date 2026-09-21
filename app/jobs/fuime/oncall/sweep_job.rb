# frozen_string_literal: true

module Fuime
  module Oncall
    # Fuime: run the checks, page anybody who needs paging, and tell the outside
    # world this worker is still alive.
    #
    # ── The heartbeat is the half of this job that cannot be replaced ──────
    #
    # Everything above it — the checks, the incidents, the pager — runs INSIDE
    # the thing being monitored. That arrangement can detect an app that is
    # broken; it can never detect an app that is gone. A dead worker does not
    # run the check that would say the worker is dead, and the resulting silence
    # is indistinguishable from a quiet, healthy night.
    #
    # So the last thing this job does is reach OUT: one request to a ping URL at
    # an external monitor (healthchecks.io, Better Stack, Cronitor — any of them,
    # it is a bare POST). The monitor knows how often the ping should arrive and
    # pages when it stops. That covers exactly the case nothing in this codebase
    # can cover for itself:
    #
    #   worker dead     → pings stop        → external monitor pages
    #   Redis dead      → pings stop        → external monitor pages
    #   whole app dead  → pings stop AND    → external monitor pages twice
    #                     /healthz stops
    #   app up, broken  → pings continue    → the checks above page
    #
    # If FUIME_HEARTBEAT_URL is unset the job still does its real work and logs a
    # warning. It does not raise: a missing monitor must not take down the
    # monitoring.
    class SweepJob < ApplicationJob
      queue_as :low

      HEARTBEAT_TIMEOUT_SECONDS = 5

      def perform
        result = ::Fuime::Oncall::Sweep.run!
        heartbeat!(result)
        result
      end

      private

      def heartbeat!(result)
        url = ENV["FUIME_HEARTBEAT_URL"].presence
        if url.blank?
          Rails.logger.warn(
            "[Fuime::Oncall] FUIME_HEARTBEAT_URL is not set, so nothing outside this app " \
            "would notice if this worker stopped. See docs/fuime/ONCALL.md."
          )
          return
        end

        uri = URI.parse(url)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == "https"
        http.open_timeout = HEARTBEAT_TIMEOUT_SECONDS
        http.read_timeout = HEARTBEAT_TIMEOUT_SECONDS

        request = Net::HTTP::Post.new(uri.request_uri)
        request["Content-Type"] = "text/plain"
        # healthchecks.io shows the body on the check's timeline, which makes the
        # external dashboard a usable second opinion rather than a green dot.
        request.body = "raised=#{result.raised.size} resolved=#{result.resolved.size} errored=#{result.errored.size}"

        http.request(request)
      rescue => e
        # A monitor that is unreachable is a problem for tomorrow, not a reason
        # to fail the sweep that just ran correctly.
        Rails.logger.error("[Fuime::Oncall] heartbeat to the external monitor failed: #{e.class}: #{e.message}")
      end

    end
  end
end
