# frozen_string_literal: true

require "net/http"
require "resolv"

module Fuime
  # Fuime: sign a payload and post it to a founder's server.
  #
  # ── The signature ────────────────────────────────────────────────────────
  #
  # `Fuime-Signature: t=<unix>,v1=<hex hmac>` over `"#{t}.#{body}"`, SHA-256.
  #
  # Deliberately the same SHAPE as Stripe's, which Fuime's own webhook receiver
  # already verifies (Fuime::WebhooksController). A founder who has integrated
  # any payment platform has written this check before, and the libraries that
  # do it are everywhere. Inventing a different envelope would buy nothing and
  # cost every integrator an afternoon.
  #
  # The timestamp is inside the signed string so a captured request cannot be
  # replayed later — a receiver rejects a stale `t` as Stripe's docs describe.
  class WebhookDeliverer
    class Blocked < StandardError; end

    TIMEOUT_SECONDS = 5
    # A founder's server is not Fuime's to trust: a compromised or hostile
    # endpoint that streams gigabytes would otherwise hold a worker open.
    MAX_RESPONSE_BYTES = 8_192

    def initialize(delivery)
      @delivery = delivery
      @endpoint = delivery.endpoint
    end

    def call
      body = @delivery.payload.to_json
      response = post(body)

      code = response.code.to_i
      if code.between?(200, 299)
        @delivery.record_success!(response_code: code)
      else
        # Anything non-2xx is a retry, including 4xx. A receiver that is
        # misconfigured today may be fixed within the ladder, and a sale is not
        # worth dropping over a 404 that someone is about to deploy a fix for.
        @delivery.record_failure!(error: "HTTP #{code}", response_code: code)
      end
      @delivery
    rescue Blocked => e
      # Not retried: a private address is not going to become public, and
      # retrying is how an SSRF probe gets five attempts instead of one.
      @delivery.update!(status: "failed", attempts: @delivery.attempts + 1,
                        last_error: e.message.truncate(1000), next_attempt_at: nil)
      @endpoint.disable!(reason: "resolved to a private address")
      @delivery
    rescue => e
      @delivery.record_failure!(error: "#{e.class}: #{e.message}")
      @delivery
    end

    private

    def post(body)
      uri = URI.parse(@endpoint.url)
      address = resolve_public_address!(uri.host)

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.open_timeout = TIMEOUT_SECONDS
      http.read_timeout = TIMEOUT_SECONDS
      # Pin the connection to the address we checked. Without this, the name is
      # resolved a second time inside Net::HTTP and a DNS-rebinding answer can
      # differ from the one just validated — the check would be decorative.
      http.ipaddr = address

      request = Net::HTTP::Post.new(uri.request_uri)
      request["Content-Type"] = "application/json"
      request["User-Agent"] = "Fuime-Webhooks/1"
      request["Fuime-Signature"] = signature_for(body)
      # Named in a header as well as the body so a receiver can dedupe without
      # parsing, which is what a queue in front of the handler wants.
      request["Fuime-Event-Id"] = @delivery.event_id
      request.body = body

      http.request(request) { |res| return truncate(res) }
    end

    def truncate(response)
      response.body.to_s.byteslice(0, MAX_RESPONSE_BYTES)
      response
    end

    def signature_for(body)
      timestamp = Time.current.to_i
      digest = OpenSSL::HMAC.hexdigest("SHA256", @endpoint.secret, "#{timestamp}.#{body}")
      "t=#{timestamp},v1=#{digest}"
    end

    # ── Why the address is re-checked here ───────────────────────────────────
    #
    # WebhookEndpoint validates the URL on save, but that check can only see
    # literal IPs: a hostname's DNS can be repointed at 169.254.169.254 (cloud
    # instance metadata) or a private range AFTER the endpoint is saved. This is
    # the check that is actually load-bearing, because it happens at the moment
    # of the request and pins the socket to what it resolved.
    def resolve_public_address!(host)
      address = Resolv.getaddress(host)
      ip = IPAddr.new(address)

      if ip.loopback? || ip.private? || ip.link_local?
        raise Blocked, "#{host} resolves to a private address (#{address}); refusing to send"
      end

      address
    rescue Resolv::ResolvError => e
      raise Blocked, "could not resolve #{host}: #{e.message}"
    end

  end
end
