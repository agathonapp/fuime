# frozen_string_literal: true

module Fuime
  module Oncall
    # Fuime: count unhandled exceptions, so a 500 spike can page somebody.
    #
    # ── Why this exists when AppSignal is in the Gemfile ──────────────────
    #
    # Because `APPSIGNAL_PUSH_API_KEY` is not set, and has not been since the
    # fork. The gem is installed and reporting into the void. That is the
    # standing note at the top of SETUP_NOTES — "the thing standing between a
    # 500 and anybody knowing" — and it has outlived several sessions because
    # setting it is somebody's afternoon with a vendor rather than a commit.
    #
    # This is not a replacement for AppSignal and must not be allowed to become
    # the excuse not to set it up: it has no backtraces, no grouping, no
    # history, and no way to tell you WHICH request broke. What it has is the
    # one property that matters tonight — it can wake somebody. When AppSignal
    # is configured, keep both: this one pages, that one is how you debug.
    #
    # ── A per-minute counter in Redis, and nothing more ────────────────────
    #
    # This runs inside `Rails.error.report`, which means it runs on the unhappy
    # path of every request in the app, including the requests that are already
    # failing. Three rules follow, and all three are load-bearing:
    #
    #   * It must never raise. An exception here would replace whatever error
    #     the user actually hit with a confusing one from the monitoring, and
    #     could turn a handled error into a 500.
    #   * It must be one Redis command. Anything that reads-then-writes is a
    #     round trip on a path that is, by definition, already going badly.
    #   * It must not persist anything. Buckets expire; there is no table, no
    #     migration, and nothing to clean up. The incident is the durable
    #     record, not the count.
    class ErrorCounter
      BUCKET_TTL = 30.minutes
      KEY_PREFIX = "fuime:oncall:errors"

      # Errors that mean "somebody sent a bad request", not "Fuime is broken".
      #
      # Excluded because including them would make the threshold meaningless:
      # a scanner walking the URL space generates hundreds of RoutingErrors an
      # hour on any public site, and a check that fires on bot traffic is a
      # check that gets muted before the night it would have mattered.
      IGNORED = %w[
        ActionController::RoutingError
        ActionController::InvalidAuthenticityToken
        ActionController::BadRequest
        ActionController::UnknownFormat
        ActionController::ParameterMissing
        ActiveRecord::RecordNotFound
        ActionDispatch::Http::MimeNegotiation::InvalidType
        Pundit::NotAuthorizedError
        Rack::Timeout::RequestTimeoutException
      ].freeze

      def self.bucket_key(time) = "#{KEY_PREFIX}:#{time.to_i / 60}"

      # Sum the buckets covering the last `window`, and say which classes they
      # were. Returns [count, {class => count}].
      def self.recent(window:, now: Time.current)
        minutes = (window / 60).to_i
        keys = (0...minutes).map { |ago| bucket_key(now - (ago * 60)) }
        class_key = "#{KEY_PREFIX}:classes"

        counts, classes = Sidekiq.redis do |conn|
          [keys.map { |k| conn.call("GET", k).to_i }, conn.call("HGETALL", class_key)]
        end

        [counts.sum, normalize_hash(classes).transform_values(&:to_i)]
      rescue => e
        # Same rule as `report`: the counter must never be the thing that breaks.
        # A nil count reads as "unknown", and Checks::Errors declines to conclude
        # anything from it rather than reporting all-clear.
        Rails.logger.error("[Fuime::Oncall] could not read error counts: #{e.class}: #{e.message}")
        [nil, {}]
      end

      # RedisClient (what Sidekiq 7 uses) already decodes HGETALL into a Hash;
      # the raw protocol shape is a flat [field, value, field, value] array, and
      # some adapters hand that back instead. Accepting both costs two lines and
      # removes a whole class of "works on my Redis" bug from a code path whose
      # failure is silent by construction.
      def self.normalize_hash(reply)
        return reply if reply.is_a?(Hash)

        Hash[Array(reply).each_slice(2).to_a]
      end

      # The Rails.error subscriber interface.
      def report(error, handled:, severity: nil, context: {}, source: nil)
        # `handled: true` is code that caught something and carried on — which
        # includes this subsystem's own `Rails.error.report` calls in Sweep and
        # Pager. Counting those would mean a failing check inflates the error
        # rate and raises a second, unrelated incident about it.
        return if handled
        return if IGNORED.include?(error.class.name)

        key = self.class.bucket_key(Time.current)
        Sidekiq.redis do |conn|
          conn.call("INCR", key)
          conn.call("EXPIRE", key, BUCKET_TTL.to_i)
          # A rolling tally of which classes, for the incident detail. Trimmed by
          # its own TTL rather than by bookkeeping, so it cannot grow without
          # bound if one error class disappears.
          conn.call("HINCRBY", "#{KEY_PREFIX}:classes", error.class.name, 1)
          conn.call("EXPIRE", "#{KEY_PREFIX}:classes", BUCKET_TTL.to_i)
        end
      rescue
        # Deliberately swallowed and deliberately silent. This runs on the
        # failure path of every request; logging here would double the noise of
        # whatever outage is already in progress, and raising would replace the
        # user's real error with one from the monitoring.
        nil
      end

    end
  end
end
