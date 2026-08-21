# frozen_string_literal: true

require "rails_helper"

# Fuime: CORS and CSP at the request boundary.
#
# These assert the headers the browser sees, not that a matcher method exists.
# No payloads: an Origin that is not Fuime simply must not be reflected.
RSpec.describe "Request-boundary headers", type: :request do
  describe "CORS" do
    it "reflects a Fuime origin on /api/current_user and permits credentials" do
      get "/api/current_user", headers: { "Origin" => "https://app.fuime.com" }

      expect(response.headers["Access-Control-Allow-Origin"]).to eq("https://app.fuime.com")
      expect(response.headers["Access-Control-Allow-Credentials"]).to eq("true")
    end

    it "does not reflect a leftover HCB origin" do
      get "/api/current_user", headers: { "Origin" => "https://hackclub.com" }

      expect(response.headers["Access-Control-Allow-Origin"]).to be_blank
    end

    it "does not reflect an unrelated origin" do
      get "/api/current_user", headers: { "Origin" => "https://example.com" }

      expect(response.headers["Access-Control-Allow-Origin"]).to be_blank
    end

    it "does not apply CORS to non-API paths" do
      get "/up", headers: { "Origin" => "https://app.fuime.com" }

      expect(response.headers["Access-Control-Allow-Origin"]).to be_blank
    end
  end

  describe "Content-Security-Policy" do
    it "sends a report-only policy and does not enforce" do
      # /api/current_user is JSON (no asset pipeline). /up is Rails::HealthController
      # (ActionController::Metal) and does not run the CSP callback.
      get "/api/current_user"

      report_only = response.headers["Content-Security-Policy-Report-Only"]
      expect(report_only).to include("default-src 'self'")
      expect(report_only).to include("object-src 'none'")
      expect(report_only).to include("frame-ancestors 'self'")
      expect(response.headers["Content-Security-Policy"]).to be_blank
    end
  end
end
