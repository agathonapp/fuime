# frozen_string_literal: true

require "rails_helper"

RSpec.describe Rack::Attack, type: :request do
  # Rack::Attack is only enabled in production, and the test cache is a
  # null_store, which would silently never increment a counter.
  around do |example|
    enabled = Rack::Attack.enabled
    store = Rack::Attack.cache.store
    Rack::Attack.enabled = true
    Rack::Attack.cache.store = ActiveSupport::Cache::MemoryStore.new

    begin
      example.run
    ensure
      Rack::Attack.enabled = enabled
      Rack::Attack.cache.store = store
    end
  end

  def discriminator(throttle, path, session_token: nil)
    env = Rack::MockRequest.env_for(path, "REMOTE_ADDR" => "203.0.113.7")
    env["HTTP_COOKIE"] = "session_token=#{session_token}" if session_token
    Rack::Attack.throttles.fetch(throttle).block.call(Rack::Attack::Request.new(env))
  end

  # Fuime: the outage of 2026-08-21. Stripe's webhooks were 403'd for two days
  # because app.fuime.com sits behind Cloudflare and `req.ip` resolved to a
  # Cloudflare edge address, which is in no allowlist. Every live payment was
  # refused at the door before the signature check, so the ledger stayed empty
  # while Stripe held the money.
  #
  # Asserted against the real blocklist block, with the header shape Cloudflare
  # actually sends: the true client in CF-Connecting-IP, and Cloudflare's own
  # address last in X-Forwarded-For, which is the entry Rack's `#ip` picks.
  describe "Stripe webhooks behind Cloudflare" do
    # Methods rather than constants: a constant defined inside a describe block
    # leaks into the enclosing namespace for the whole suite
    # (Lint/ConstantDefinitionInBlock), and `let` is not visible inside the `def`
    # below.
    def stripe_ip = "3.18.12.63" # first line of config/stripe_ips_webhooks.txt
    def cloudflare_ip = "172.67.164.168"

    def blocked?(path, connecting_ip:, forwarded_for: nil)
      env = Rack::MockRequest.env_for(
        path,
        "REMOTE_ADDR" => cloudflare_ip,
        method: "POST"
      )
      env["HTTP_CF_CONNECTING_IP"] = connecting_ip if connecting_ip
      env["HTTP_X_FORWARDED_FOR"] = forwarded_for if forwarded_for
      !!Rack::Attack.blocklists
                    .fetch("block Fuime Stripe webhooks from non-Stripe IPs")
                    .block.call(Rack::Attack::Request.new(env))
    end

    it "lets a real Stripe webhook through when Cloudflare is the peer" do
      expect(
        blocked?("/fuime/webhooks/stripe",
                 connecting_ip: stripe_ip,
                 forwarded_for: "#{stripe_ip}, #{cloudflare_ip}")
      ).to be false
    end

    it "covers the connect path the same way" do
      expect(
        blocked?("/fuime/webhooks/stripe/connect", connecting_ip: stripe_ip)
      ).to be false
    end

    # The regression itself: without CF-Connecting-IP, Rack's #ip returns the
    # LAST untrusted forwarded entry — Cloudflare — and the request is refused.
    # This is what production was doing to every payment.
    it "blocks when only Cloudflare's address is visible" do
      expect(
        blocked?("/fuime/webhooks/stripe",
                 connecting_ip: nil,
                 forwarded_for: "#{stripe_ip}, #{cloudflare_ip}")
      ).to be true
    end

    it "still blocks a genuine non-Stripe sender" do
      expect(
        blocked?("/fuime/webhooks/stripe", connecting_ip: "203.0.113.7")
      ).to be true
    end

    it "ignores paths that are not the webhook endpoints" do
      expect(blocked?("/some/other/path", connecting_ip: "203.0.113.7")).to be false
    end
  end

  describe "transparency/ledger/ip" do
    it "throttles anonymous reads of any organization's transactions" do
      [
        "/an-organization/transactions",
        "/an-organization/transactions_list",
        "/an-organization/ledger",
        "/some-other-org/transactions_list",
        # The format suffix reaches the same action at the same cost.
        "/an-organization/transactions_list.json",
        "/an-organization/transactions.csv"
      ].each do |path|
        expect(discriminator("transparency/ledger/ip", path)).to eq("203.0.113.7"), "expected #{path} to be throttled"
      end
    end

    it "ignores requests that carry a session_token cookie" do
      expect(discriminator("transparency/ledger/ip", "/an-organization/transactions_list", session_token: "abc123")).to be_nil
    end

    it "ignores paths outside the ledger surface" do
      [
        "/an-organization",
        "/an-organization/team",
        "/an-organization/transactions_list/extra",
        "/admin/ledger",
        "/admin/ledger_items",
        "/storage/representations/redirect/abc/def"
      ].each do |path|
        expect(discriminator("transparency/ledger/ip", path)).to be_nil, "expected #{path} not to be throttled"
      end
    end

    it "responds with 429 once an anonymous client passes the limit" do
      limit = Rack::Attack.throttles.fetch("transparency/ledger/ip").limit

      # Counters bucket by `Time.now.to_i / period`, so a minute boundary
      # mid-loop would reset the count and lose the throttle.
      freeze_time do
        limit.times { get "/an-organization/transactions_list" }
        expect(response.body).not_to eq("Retry later\n")

        get "/an-organization/transactions_list"
        expect(response).to have_http_status(:too_many_requests)
        expect(response.body).to eq("Retry later\n")
      end
    end
  end

  describe "ledger/ip" do
    # A forged `session_token` escapes the throttle above, since the cookie can't
    # be verified at this layer. This is what stops that meaning unlimited access.
    it "applies whether or not a session_token cookie is present" do
      expect(discriminator("ledger/ip", "/an-organization/transactions_list")).to eq("203.0.113.7")
      expect(discriminator("ledger/ip", "/an-organization/transactions_list", session_token: "forged")).to eq("203.0.113.7")
    end

    it "responds with 429 to a client sending an unverified session_token" do
      limit = Rack::Attack.throttles.fetch("ledger/ip").limit
      forged = { "HTTP_COOKIE" => "session_token=forged" }

      freeze_time do
        limit.times { get "/an-organization/transactions_list", headers: forged }
        expect(response.body).not_to eq("Retry later\n")

        get "/an-organization/transactions_list", headers: forged
        expect(response).to have_http_status(:too_many_requests)
      end
    end
  end
end
