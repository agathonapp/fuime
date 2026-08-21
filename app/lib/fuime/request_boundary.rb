# frozen_string_literal: true

module Fuime
  # Request-boundary allowlists: CORS Origin matching and production Host names.
  #
  # Hosts confirmed from render.yaml (`APP_ORIGIN=https://app.fuime.com`,
  # marketing site on fuime.com), `site/server.js`, `LIVE_URL_HOST`, and
  # Render's injected `RENDER_EXTERNAL_HOSTNAME`. Leftover HCB origins
  # (hackclub.com, bank.engineering, hcb-engr.hackclub.dev) are not listed.
  module RequestBoundary
    # Browser origins that may call the Rails API. Scheme is required: an
    # Origin header is a full origin, not a bare hostname.
    FUIME_ORIGINS = %w[
      https://app.fuime.com
      https://fuime.com
    ].freeze

    # Hostnames Rails will accept in production. `LIVE_URL_HOST` and
    # `RENDER_EXTERNAL_HOSTNAME` are merged in at boot so a dashboard change
    # cannot lock out the process that is actually serving.
    FUIME_HOSTS = %w[
      app.fuime.com
      fuime.com
    ].freeze

    LOCAL_HOSTS = %w[localhost 127.0.0.1].freeze

    class << self
      # rack-cors `origins` callback. Must return true/false — `Array#each`
      # returns the array (always truthy) and was how every Origin was allowed.
      def allowed_cors_origin?(source)
        return false if source.blank?

        parsed = URI.parse(source)
        return false unless parsed.is_a?(URI::HTTP) || parsed.is_a?(URI::HTTPS)
        return false if parsed.host.blank?

        return true if FUIME_ORIGINS.any? { |origin| origin == source }

        Rails.env.local? && LOCAL_HOSTS.any? { |host| host == parsed.host }
      rescue URI::InvalidURIError
        false
      end

      def production_hosts
        [
          *FUIME_HOSTS,
          host_from(Credentials.fetch(:LIVE_URL_HOST, fallback: nil)),
          host_from(ENV["RENDER_EXTERNAL_HOSTNAME"])
        ].compact.uniq
      end

      private

      # LIVE_URL_HOST is a hostname (`app.fuime.com`). Tolerate a full URL
      # if someone pastes one into the dashboard, and drop a blank string.
      def host_from(value)
        raw = value.to_s.strip
        return if raw.blank?

        raw = "https://#{raw}" unless raw.include?("://")
        URI.parse(raw).host.presence
      rescue URI::InvalidURIError
        nil
      end

    end
  end
end
