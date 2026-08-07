# frozen_string_literal: true

# Fuime: the read side of the marketing-site waitlist.
#
# The WRITE side lives in the other deploy — site/api/waitlist.js on the Render
# static service — and is not Rails' business. It stores every signup in Upstash
# under two keys:
#
#   SADD  fuime:waitlist               <email>
#   HSET  fuime:waitlist:meta:<email>  at / source / ip
#
# The set is the roster, so a count of it is unique addresses rather than form
# submissions. The hashes carry the detail. This joins them for /admin/waitlist.
#
# Read-only by construction: the only commands issued are SCARD, SMEMBERS and
# HGETALL. Give Rails a READ-ONLY Upstash token — it has no reason to hold one
# that can delete the list.
#
# Absent credentials are a normal state, not an error (Milestone 2: every
# external service must be safely unset). `configured?` is false, the page says
# so, and nothing raises.
module Fuime
  class WaitlistRoster
    class ReadFailed < StandardError; end

    LIST_KEY = "fuime:waitlist"
    META_PREFIX = "fuime:waitlist:meta:"

    # HGETALL for 1,000 addresses is 1,000 commands. Upstash accepts them in one
    # pipeline, but an unbounded request body against any REST API is a bad
    # habit, so they go in chunks.
    CHUNK = 250

    # The number Alpha School put on the table. Overridable so it isn't a lie
    # once it's met.
    def self.goal
      Credentials.fetch(:WAITLIST_GOAL).presence&.to_i || 1_000
    end

    Signup = Struct.new(:email, :signed_up_at, :source, :ip, keyword_init: true)

    # For the admin nav, which renders on every admin page. Two properties
    # matter more than freshness: it must not make an HTTP call per page load,
    # and it must never be the reason the admin console 500s. So: cached, and
    # every failure degrades to nil (the nav then shows no number rather than a
    # confident zero, which would read as "no signups").
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

    def self.configured?
      base_url.present? && token.present?
    end

    def self.base_url
      Credentials.fetch(:UPSTASH_REDIS_REST_URL).presence
    end

    def self.token
      Credentials.fetch(:UPSTASH_REDIS_REST_TOKEN).presence
    end

    delegate :configured?, to: :class

    # => { total:, signups: [Signup, ...] }, newest first.
    def fetch
      return { total: 0, signups: [] } unless configured?

      card, members = pipeline([["SCARD", LIST_KEY], ["SMEMBERS", LIST_KEY]])
      emails = members["result"].is_a?(Array) ? members["result"] : []

      signups = emails.each_slice(CHUNK).flat_map do |slice|
        results = pipeline(slice.map { |email| ["HGETALL", "#{META_PREFIX}#{email}"] })

        slice.each_with_index.map do |email, i|
          meta = hash_result(results[i]&.dig("result"))

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

      { total: card["result"].to_i.nonzero? || emails.size, signups: }
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

    private

    def pipeline(commands)
      response = connection.post("/pipeline", commands.to_json)

      unless response.success?
        raise ReadFailed, "Upstash returned #{response.status}"
      end

      body = JSON.parse(response.body)
      raise ReadFailed, "unexpected Upstash response" unless body.is_a?(Array)

      body
    rescue Faraday::Error => e
      raise ReadFailed, e.message
    rescue JSON::ParserError
      raise ReadFailed, "unparseable Upstash response"
    end

    def connection
      @connection ||= Faraday.new(url: self.class.base_url) do |f|
        f.headers["Authorization"] = "Bearer #{self.class.token}"
        f.headers["Content-Type"] = "application/json"
        f.options.timeout = 10
        f.options.open_timeout = 5
      end
    end

    # HGETALL comes back as a flat [k, v, k, v] array over the REST API, but a
    # plain object is a shape Upstash has also served. Accept either.
    def hash_result(result)
      case result
      when Array then Hash[*result] rescue {}
      when Hash  then result
      else {}
      end
    end

    def parse_time(value)
      return nil if value.blank?

      Time.parse(value).utc
    rescue ArgumentError
      nil
    end

  end
end
