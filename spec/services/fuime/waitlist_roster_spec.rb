# frozen_string_literal: true

require "rails_helper"

# Fuime: the read side of the marketing site's waitlist. The site writes the
# keys; this only ever reads them.
RSpec.describe Fuime::WaitlistRoster do
  let(:url) { "https://kv.example.com" }

  def configure!
    ENV["UPSTASH_REDIS_REST_URL"] = url
    ENV["UPSTASH_REDIS_REST_TOKEN"] = "kv-token"
  end

  # One stub for both pipeline calls: the roster list, then the per-email
  # hashes. WebMock replays them in order.
  def stub_pipeline(*responses)
    stub_request(:post, "#{url}/pipeline")
      .to_return(*responses.map { |r| { status: 200, body: r.to_json } })
  end

  before do
    ENV.delete("UPSTASH_REDIS_REST_URL")
    ENV.delete("UPSTASH_REDIS_REST_TOKEN")
    ENV.delete("WAITLIST_GOAL")
    Rails.cache.delete(described_class::NAV_CACHE_KEY)
  end

  after do
    ENV.delete("UPSTASH_REDIS_REST_URL")
    ENV.delete("UPSTASH_REDIS_REST_TOKEN")
    ENV.delete("WAITLIST_GOAL")
  end

  describe "without credentials" do
    it "is not configured, and reads as empty rather than raising" do
      expect(described_class).not_to be_configured
      expect(described_class.new.fetch).to eq(total: 0, signups: [])
    end

    it "never reaches out for the nav count" do
      expect(described_class.cached_total).to be_nil
      expect(a_request(:post, "#{url}/pipeline")).not_to have_been_made
    end
  end

  describe "#fetch" do
    before { configure! }

    it "joins the roster set with the meta hashes, newest first" do
      stub_pipeline(
        [{ "result" => 3 }, { "result" => ["b@example.com", "a@example.com", "c@example.com"] }],
        [
          { "result" => ["at", "2026-08-06T09:00:00Z", "source", "pricing-foot", "ip", "2.2.2.2"] },
          { "result" => ["at", "2026-08-05T10:00:00Z", "source", "home-hero", "ip", "1.1.1.1"] },
          { "result" => [] }
        ]
      )

      result = described_class.new.fetch

      expect(result[:total]).to eq 3
      expect(result[:signups].map(&:email)).to eq ["b@example.com", "a@example.com", "c@example.com"]
      expect(result[:signups].first.source).to eq "pricing-foot"
    end

    it "still lists an address whose meta hash never landed" do
      stub_pipeline(
        [{ "result" => 1 }, { "result" => ["orphan@example.com"] }],
        [{ "result" => [] }]
      )

      orphan = described_class.new.fetch[:signups].first

      expect(orphan.email).to eq "orphan@example.com"
      expect(orphan.signed_up_at).to be_nil
      expect(orphan.source).to eq "unknown"
    end

    it "accepts an object-shaped HGETALL as well as a flat array" do
      stub_pipeline(
        [{ "result" => 1 }, { "result" => ["x@example.com"] }],
        [{ "result" => { "at" => "2026-08-06T09:00:00Z", "source" => "home-foot", "ip" => "" } }]
      )

      expect(described_class.new.fetch[:signups].first.source).to eq "home-foot"
    end

    it "raises ReadFailed — not a bare HTTP error — when Upstash is unhappy" do
      stub_request(:post, "#{url}/pipeline").to_return(status: 500, body: "boom")

      expect { described_class.new.fetch }.to raise_error(described_class::ReadFailed, /500/)
    end

    it "raises ReadFailed when the connection dies" do
      stub_request(:post, "#{url}/pipeline").to_timeout

      expect { described_class.new.fetch }.to raise_error(described_class::ReadFailed)
    end

    it "pages HGETALL rather than sending one unbounded request" do
      emails = (1..600).map { |i| "f#{i}@example.com" }
      stub_pipeline(
        [{ "result" => emails.size }, { "result" => emails }],
        emails.first(250).map { { "result" => [] } },
        emails[250, 250].map { { "result" => [] } },
        emails[500..].map { { "result" => [] } }
      )

      expect(described_class.new.fetch[:signups].size).to eq 600
      # 1 roster call + 3 chunks of 250.
      expect(a_request(:post, "#{url}/pipeline")).to have_been_made.times(4)
    end
  end

  describe ".cached_total" do
    before { configure! }

    it "degrades to nil instead of taking the admin nav down with it" do
      stub_request(:post, "#{url}/pipeline").to_return(status: 500, body: "boom")

      expect(described_class.cached_total).to be_nil
    end
  end

  describe "derived views" do
    let(:signups) do
      [
        described_class::Signup.new(email: "a@x.com", signed_up_at: Time.utc(2026, 8, 6), source: "home-hero"),
        described_class::Signup.new(email: "b@x.com", signed_up_at: Time.utc(2026, 8, 6), source: "home-hero"),
        described_class::Signup.new(email: "c@x.com", signed_up_at: Time.utc(2026, 8, 4), source: "pricing-foot"),
        described_class::Signup.new(email: "d@x.com", signed_up_at: nil, source: "unknown")
      ]
    end

    it "counts by source, biggest first" do
      expect(described_class.by_source(signups)).to eq [["home-hero", 2], ["pricing-foot", 1], ["unknown", 1]]
    end

    it "fills empty days with zeroes so the shape reads as momentum" do
      days = described_class.by_day(signups, days: 4, today: Date.new(2026, 8, 6))

      expect(days).to eq [
        [Date.new(2026, 8, 3), 0],
        [Date.new(2026, 8, 4), 1],
        [Date.new(2026, 8, 5), 0],
        [Date.new(2026, 8, 6), 2]
      ]
    end
  end

  describe ".goal" do
    it "defaults to the 1,000 on the table" do
      expect(described_class.goal).to eq 1_000
    end

    it "is overridable so it does not stay a lie once met" do
      ENV["WAITLIST_GOAL"] = "2500"
      expect(described_class.goal).to eq 2_500
    end
  end

end
