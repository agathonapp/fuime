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
# The marketing site owns new signups (SADD + the at/source/ip hash). Rails
# reads that roster and, as of the G1 admit path, writes only invite stamps
# (invited_at / invited_by / cohort_code) onto an address that is already in
# the set. The rake import task is the other writer. Neither path invents a
# signup the site did not capture.
#
# An absent URL is a normal state, not an error (Milestone 2: every external
# service must be safely unset). `configured?` is false, the page says so, and
# nothing raises.
module Fuime
  class WaitlistRoster
    class ReadFailed < StandardError; end
    class WriteFailed < StandardError; end

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

    Signup = Struct.new(:email, :signed_up_at, :source, :ip,
                        :invited_at, :invited_by, :cohort_code,
                        keyword_init: true)

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
            ip: meta["ip"].to_s,
            invited_at: parse_time(meta["invited_at"]),
            invited_by: meta["invited_by"].to_s.presence,
            cohort_code: meta["cohort_code"].to_s.presence
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

    # Oldest uninvited first — FIFO, which is what "invite next N" means on a
    # waitlist. Undated imports sort last so a reconstructed backfill cannot
    # jump the queue of people we actually have a signup time for.
    def self.uninvited(signups)
      signups.reject(&:invited_at).sort_by do |signup|
        [signup.signed_up_at ? 0 : 1, signup.signed_up_at || Time.at(0)]
      end
    end

    # Best-effort lookup of a prior admit stamp. Used when a founder logs in
    # through the ordinary code flow instead of the invite link, so the cohort
    # (if any) still lands on their application. Nil on every failure — a
    # missing store must not block applying.
    def self.invite_stamp(email)
      return nil unless configured?

      new.invite_stamp(email)
    rescue ReadFailed, Redis::BaseError, SocketError, IOError => e
      Rails.error.report(e, handled: true)
      nil
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

    def member?(email)
      return false unless configured?

      redis.sismember(LIST_KEY, normalize_email(email))
    rescue Redis::BaseError, SocketError, IOError => e
      raise ReadFailed, e.message
    end

    def invite_stamp(email)
      return nil unless configured?

      normalized = normalize_email(email)
      return nil if normalized.blank?
      return nil unless redis.sismember(LIST_KEY, normalized)

      meta = redis.hgetall("#{META_PREFIX}#{normalized}") || {}
      return nil if meta["invited_at"].blank?

      Signup.new(
        email: normalized,
        signed_up_at: parse_time(meta["at"]),
        source: meta["source"].presence || "unknown",
        ip: meta["ip"].to_s,
        invited_at: parse_time(meta["invited_at"]),
        invited_by: meta["invited_by"].to_s.presence,
        cohort_code: meta["cohort_code"].to_s.presence
      )
    rescue Redis::BaseError, SocketError, IOError => e
      raise ReadFailed, e.message
    end

    # Stamp an address that is already on the list. Refuses to SADD — inventing
    # a signup from the admin console would mix ops actions into the capture
    # roster the site owns.
    #
    # A blank cohort_code leaves any existing stamp alone, so Resend (which
    # does not re-submit the cohort) cannot wipe the event promised in the
    # first invite. Pass a code to set or replace it.
    def mark_invited(email, invited_by:, cohort_code: nil)
      raise WriteFailed, "waitlist store is not configured" unless configured?

      normalized = normalize_email(email)
      raise WriteFailed, "email is blank" if normalized.blank?
      raise WriteFailed, "#{normalized} is not on the waitlist" unless redis.sismember(LIST_KEY, normalized)

      fields = {
        "invited_at" => Time.current.utc.iso8601,
        "invited_by" => invited_by.to_s
      }
      fields["cohort_code"] = cohort_code.to_s if cohort_code.present?
      redis.hset("#{META_PREFIX}#{normalized}", fields)
      Rails.cache.delete(NAV_CACHE_KEY)
      true
    rescue Redis::BaseError, SocketError, IOError => e
      raise WriteFailed, e.message
    end

    private

    def redis
      @redis ||= Redis.new(**self.class.connection_options(self.class.url))
    end

    def normalize_email(email)
      email.to_s.strip.downcase
    end

    def parse_time(value)
      return nil if value.blank?

      Time.parse(value).utc
    rescue ArgumentError
      nil
    end

  end
end
