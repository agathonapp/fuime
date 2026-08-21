# frozen_string_literal: true

require "rails_helper"

# Fuime: CORS origin matching and production Host names.
#
# The CORS initializer used `domains.each`, which returns the array and is
# always truthy, so every Origin was allowed. These examples pin the matcher
# to named Fuime origins and to localhost only in local environments.
RSpec.describe Fuime::RequestBoundary do
  describe ".allowed_cors_origin?" do
    it "allows the Rails app origin" do
      expect(described_class.allowed_cors_origin?("https://app.fuime.com")).to be true
    end

    it "allows the marketing-site origin" do
      expect(described_class.allowed_cors_origin?("https://fuime.com")).to be true
    end

    it "rejects leftover HCB origins" do
      %w[
        https://hackclub.com
        https://bank.engineering
        https://hcb-engr.hackclub.dev
      ].each do |origin|
        expect(described_class.allowed_cors_origin?(origin)).to be(false), origin
      end
    end

    it "rejects an unrelated origin" do
      expect(described_class.allowed_cors_origin?("https://example.com")).to be false
    end

    it "rejects a blank origin" do
      expect(described_class.allowed_cors_origin?(nil)).to be false
      expect(described_class.allowed_cors_origin?("")).to be false
    end

    it "rejects a malformed origin rather than raising" do
      expect(described_class.allowed_cors_origin?("not a uri")).to be false
    end

    it "allows localhost in the test environment" do
      expect(described_class.allowed_cors_origin?("http://localhost:3000")).to be true
      expect(described_class.allowed_cors_origin?("http://127.0.0.1:3000")).to be true
    end

    it "does not treat a Fuime hostname on http as allowed" do
      expect(described_class.allowed_cors_origin?("http://app.fuime.com")).to be false
    end
  end

  describe ".production_hosts" do
    def with_env(key, value)
      had = ENV.key?(key)
      old = ENV[key]
      value.nil? ? ENV.delete(key) : ENV[key] = value
      yield
    ensure
      had ? ENV[key] = old : ENV.delete(key)
    end

    it "always includes the canonical Fuime hosts" do
      with_env("LIVE_URL_HOST", nil) do
        with_env("RENDER_EXTERNAL_HOSTNAME", nil) do
          expect(described_class.production_hosts).to include("app.fuime.com", "fuime.com")
        end
      end
    end

    it "merges LIVE_URL_HOST and RENDER_EXTERNAL_HOSTNAME when set" do
      with_env("LIVE_URL_HOST", "app.fuime.com") do
        with_env("RENDER_EXTERNAL_HOSTNAME", "fuime-web.onrender.com") do
          expect(described_class.production_hosts).to include(
            "app.fuime.com",
            "fuime.com",
            "fuime-web.onrender.com"
          )
        end
      end
    end

    it "accepts a full URL in LIVE_URL_HOST and keeps only the host" do
      with_env("LIVE_URL_HOST", "https://app.fuime.com") do
        with_env("RENDER_EXTERNAL_HOSTNAME", nil) do
          expect(described_class.production_hosts).to include("app.fuime.com")
          expect(described_class.production_hosts).not_to include("https://app.fuime.com")
        end
      end
    end
  end
end
