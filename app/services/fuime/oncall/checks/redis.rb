# frozen_string_literal: true

module Fuime
  module Oncall
    module Checks
      # Fuime: is Redis answering?
      #
      # Sev-1 because of what depends on it rather than what it is. Sidekiq's
      # entire queue lives in Redis: if it is gone, no webhook is processed, no
      # payout batch is generated, no mail is delivered, and — worst — every
      # scheduled check in this very subsystem stops running while the app keeps
      # serving pages and looking healthy.
      #
      # This is therefore one of the few checks that must also be reachable from
      # the WEB process, which is why it is in Check.infrastructure and on `/up`.
      class Redis < Check
        def call
          started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          Sidekiq.redis { |conn| conn.call("PING") }
          elapsed_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round

          return [] if elapsed_ms <= 1_000

          [finding(
            key: "redis.slow",
            title: "Redis PING took #{elapsed_ms}ms",
            severity: :sev2,
            round_trip_ms: elapsed_ms
          )]
        end

      end
    end
  end
end
