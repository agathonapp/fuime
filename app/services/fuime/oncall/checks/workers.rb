# frozen_string_literal: true

module Fuime
  module Oncall
    module Checks
      # Fuime: is anything actually processing background work?
      #
      # ── Read this before trusting it ───────────────────────────────────────
      #
      # When this check runs inside Sidekiq it CANNOT report that Sidekiq is
      # down, because a dead worker does not run the check that would say so.
      # That is not a flaw to be fixed in code; it is the reason
      # `Check.infrastructure` includes this class and `/up` runs it from the WEB
      # process, and the reason the outbound heartbeat in
      # Fuime::Oncall::SweepJob exists at all. Three independent observers:
      #
      #   web  → this check, via /up, sees "no worker processes"
      #   ext  → healthchecks.io sees the heartbeat stop
      #   self → this check, running normally, sees queues backing up
      #
      # Any one of them alone has a blind spot that the other two cover.
      #
      # ── Why queue latency and not queue depth ──────────────────────────────
      #
      # Depth is meaningless on its own: 5,000 jobs draining at 2,000/s is
      # healthy and 3 jobs that have sat for an hour is not. Latency is the age
      # of the oldest job in the queue, which is the thing a founder actually
      # experiences as "my sale has not shown up".
      class Workers < Check
        # `critical` carries payment webhooks and is expected to be near-empty.
        # `low` carries the digest and sweeps, where a few minutes is normal.
        LATENCY_THRESHOLDS = { "critical" => 2.minutes, "default" => 10.minutes, "low" => 30.minutes }.freeze
        DEFAULT_LATENCY_THRESHOLD = 15.minutes

        def call
          findings = []
          processes = ::Sidekiq::ProcessSet.new

          if processes.size.zero?
            # Everything below this is unmeasurable when there is no worker, so
            # return immediately rather than emitting a cascade of derived
            # findings that all describe the same outage.
            return [finding(
              key: "workers.none_running",
              title: "No Sidekiq worker processes are running",
              severity: :sev1,
              impact: "No payment webhooks, payouts, emails or scheduled checks are being processed. " \
                      "Sales will not appear on any venture's ledger."
            )]
          end

          # rubocop:disable Rails/FindEach -- Sidekiq::Queue.all returns an Array,
          # not a relation. `find_each` does not exist on it and the autocorrect
          # would replace a working check with a NoMethodError at 3am.
          ::Sidekiq::Queue.all.each do |queue|
            threshold = LATENCY_THRESHOLDS.fetch(queue.name, DEFAULT_LATENCY_THRESHOLD)
            next if queue.latency < threshold.to_i

            findings << finding(
              # Per-queue key: `critical` backing up and `low` backing up are
              # different problems with different causes, and collapsing them
              # into one incident hides whichever arrives second.
              key: "workers.queue_backlog.#{queue.name}",
              title: "Sidekiq queue '#{queue.name}' is #{distance(queue.latency)} behind",
              severity: queue.name == "critical" ? :sev1 : :sev2,
              queue: queue.name,
              latency_seconds: queue.latency.round,
              depth: queue.size,
              threshold_seconds: threshold.to_i,
              worker_processes: processes.size
            )
          end
          # rubocop:enable Rails/FindEach

          findings
        end

        private

        def distance(seconds)
          ActiveSupport::Duration.build(seconds.round).inspect
        end

      end
    end
  end
end
