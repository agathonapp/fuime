# frozen_string_literal: true

# Fuime: the read side of the marketing-site waitlist.
#
# The WRITE side lives in the other deploy — site/api/waitlist.js on the
# fuime-site service — and is not Rails' business. It stores every signup under
# two keys:
#
#   SADD  fuime:waitlist               <email>
#   HSET  fuime:waitlist:meta:<email>  at / source / ip
#
# The set is the roster, so a count of it is unique addresses rather than form
# submissions. The hashes carry the detail. This joins them for /admin/waitlist.
#
# Storage is a Render Key Value instance, reached over the normal Redis
# protocol on the private network. It is deliberately NOT the same instance as
# `fuime-redis`: that one is the Sidekiq queue, ActionCable and the Rails cache,
# it runs `maxmemoryPolicy: noeviction`, and a cache large enough to fill memory
# would start failing writes — including waitlist writes. Durable business data
# should not share a memory budget with a cache forever, so WAITLIST_REDIS_URL
# is its own variable: splitting the roster onto a dedicated instance later is
# one new service and one changed value, not a code change.
#
# Read-only by construction: the only commands issued are SCARD, SMEMBERS and
# HGETALL. The rake import task is the one thing in Fuime that writes here.
#
# An absent URL is a normal state, not an error (Milestone 2: every external
# service must be safely unset). `configured?` is false, the page says so, and
# nothing raises.
module Fuime
  class WaitlistRoster
    class ReadFailed < StandardError; end

    LIST_KEY = "fuime:waitlist"
    META_PREFIX = "fuime:waitlist:meta:"

    # HGETALL for 1,000 addresses is 1,000 round trips unless they are
    # pipelined. Pipelined in chunks rather than all at once so the reply buffer
    # stays bounded no matter how long the list gets.
    CHUNK = 250

    CONNECT_TIMEOUT = 2
    READ_TIMEOUT = 5

    # The number Alpha School put on the table. Overridable so it isn't a lie
    # once it's met.
    def self.goal
      Credentials.fetch(:WAITLIST_GOAL).presence&.to_i || 1_000
    end

    Signup = Struct.new(:email, :signed_up_at, :source, :ip, keyword_init: true)

    # WAITLIST_REDIS_URL only, with deliberately NO fallback to REDIS_URL.
    # The fallback is tempting for dev convenience and is a trap in production:
    # REDIS_URL is always set on fuime-web, so a service that simply forgot this
    # variable would quietly read the Sidekiq/cache instance, find no roster
    # there, and render a confident zero. Silently reporting an empty waitlist
    # is the precise failure this page exists to end. Unset must mean "I have
    # nothing to read", loudly, so set it explicitly in development too.
    def self.url
      Credentials.fetch(:WAITLIST_REDIS_URL).presence
    end

    def self.configured?
      url.present?
    end

    # For the admin nav and the admin_tools card, both of which render on pages
    # that have nothing to do with the waitlist. Two properties matter more than
    # freshness: no round trip per page load, and never the reason the admin
    # console 500s. So: cached, and every failure degrades to nil — the badge
    # then shows nothing rather than a confident zero.
    NAV_CACHE_KEY = "fuime:waitlist:total"
    NAV_CACHE_TTL = 5.minutes

    def self.cached_total
      return nil unless configured?

      Rails.cache.fetch(NAV_CACHE_KEY, expires_in: NAV_CACHE_TTL) do
        new.fetch[:total]
      end
    rescue => e
      Rails.error.report(e, handled: true)
      nil
    end

    delegate :configured?, to: :class

    # => { total:, signups: [Signup, ...] }, newest first.
    def fetch
      return { total: 0, signups: [] } unless configured?

      total = redis.scard(LIST_KEY)
      emails = redis.smembers(LIST_KEY)

      signups = emails.each_slice(CHUNK).flat_map do |slice|
        metas = redis.pipelined do |pipe|
          slice.each { |email| pipe.hgetall("#{META_PREFIX}#{email}") }
        end

        slice.each_with_index.map do |email, i|
          meta = metas[i] || {}

          Signup.new(
            email:,
            # A row with no meta hash is a signup whose HSET failed after the
            # SADD landed. Still a real address, so still listed.
            signed_up_at: parse_time(meta["at"]),
            source: meta["source"].presence || "unknown",
            ip: meta["ip"].to_s
          )
        end
      end

      # Newest first; undated rows sort last rather than poisoning the order.
      signups.sort! do |a, b|
        [b.signed_up_at ? 1 : 0, b.signed_up_at || Time.at(0)] <=>
          [a.signed_up_at ? 1 : 0, a.signed_up_at || Time.at(0)]
      end

      { total: total.to_i.nonzero? || emails.size, signups: }
    rescue Redis::BaseError, SocketError, IOError => e
      raise ReadFailed, e.message
    end

    # Signups per UTC day over the trailing window, oldest first, with empty
    # days present as zeroes so the shape reads as momentum, not as a list.
    def self.by_day(signups, days: 30, today: Date.current)
      counts = signups.filter_map { |s| s.signed_up_at&.utc&.to_date }.tally
      ((today - (days - 1))..today).map { |day| [day, counts.fetch(day, 0)] }
    end

    def self.by_source(signups)
      signups.group_by(&:source).transform_values(&:size).sort_by { |_, n| -n }
    end

    # Render terminates TLS on its external Key Value hostname with a
    # certificate the default store does not chain to, the same reason the
    # production cache_store passes this. Internal `redis://` URLs ignore it.
    def self.connection_options(url)
      {
        url:,
        connect_timeout: CONNECT_TIMEOUT,
        read_timeout: READ_TIMEOUT,
        write_timeout: READ_TIMEOUT,
        ssl_params: { verify_mode: OpenSSL::SSL::VERIFY_NONE }
      }
    end

    private

    def redis
      @redis ||= Redis.new(**self.class.connection_options(self.class.url))
    end

    def parse_time(value)
      return nil if value.blank?

      Time.parse(value).utc
    rescue ArgumentError
      nil
    end

  end
end
