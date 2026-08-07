# frozen_string_literal: true

require "rails_helper"

# Fuime: the read side of the marketing site's waitlist. The site writes the
# keys; this only ever reads them.
#
# Runs against a REAL Redis rather than a stub. Both CI and docker-compose
# provide one, and the whole point of this class is the shape of what Redis
# gives back — a stubbed client would be asserting my own assumptions about
# HGETALL's return type, which is exactly the class of bug that a fake hides.
# DB 15 keeps it clear of the dev cache and the Sidekiq queue.
RSpec.describe Fuime::WaitlistRoster do
  def redis_url
    uri = URI.parse(ENV["REDIS_URL"].presence || "redis://localhost:6379")
    uri.path = "/15"
    uri.to_s
  end

  let(:redis) { Redis.new(url: redis_url) }

  def store(email, at: nil, source: nil, ip: nil)
    redis.sadd(described_class::LIST_KEY, email)
    meta = {}
    meta["at"] = at if at
    meta["source"] = source if source
    meta["ip"] = ip if ip
    redis.hset("#{described_class::META_PREFIX}#{email}", meta) if meta.any?
  end

  before do
    ENV["WAITLIST_REDIS_URL"] = redis_url
    ENV.delete("WAITLIST_GOAL")
    redis.flushdb
    Rails.cache.delete(described_class::NAV_CACHE_KEY)
  end

  after do
    redis.flushdb
    ENV.delete("WAITLIST_REDIS_URL")
    ENV.delete("WAITLIST_GOAL")
  end

  describe "without a configured url" do
    before { ENV.delete("WAITLIST_REDIS_URL") }

    it "is not configured, and reads as empty rather than raising" do
      # Deliberately does NOT fall back to REDIS_URL, which is always set on
      # fuime-web: falling back would make a forgotten variable look like an
      # empty waitlist instead of a missing one.
      expect(ENV["REDIS_URL"]).to be_present
      expect(described_class).not_to be_configured
      expect(described_class.new.fetch).to eq(total: 0, signups: [])
      expect(described_class.cached_total).to be_nil
    end
  end

  describe "#fetch" do
    it "joins the roster set with the meta hashes, newest first" do
      store("b@example.com", at: "2026-08-06T09:00:00Z", source: "pricing-foot", ip: "2.2.2.2")
      store("a@example.com", at: "2026-08-05T10:00:00Z", source: "home-hero", ip: "1.1.1.1")

      result = described_class.new.fetch

      expect(result[:total]).to eq 2
      expect(result[:signups].map(&:email)).to eq ["b@example.com", "a@example.com"]
      expect(result[:signups].first.source).to eq "pricing-foot"
      expect(result[:signups].first.ip).to eq "2.2.2.2"
    end

    it "still lists an address whose meta hash never landed" do
      store("orphan@example.com")

      orphan = described_class.new.fetch[:signups].first

      expect(orphan.email).to eq "orphan@example.com"
      expect(orphan.signed_up_at).to be_nil
      expect(orphan.source).to eq "unknown"
    end

    it "sorts undated rows last rather than letting them poison the order" do
      store("dated@example.com", at: "2026-08-05T10:00:00Z", source: "home-hero")
      store("undated@example.com", source: "imported")

      expect(described_class.new.fetch[:signups].map(&:email))
        .to eq ["dated@example.com", "undated@example.com"]
    end

    it "ignores an unparseable timestamp instead of raising" do
      store("bad@example.com", at: "not a date", source: "home-hero")

      expect(described_class.new.fetch[:signups].first.signed_up_at).to be_nil
    end

    it "reads a roster larger than one pipeline chunk" do
      600.times { |i| redis.sadd(described_class::LIST_KEY, "f#{i}@example.com") }

      result = described_class.new.fetch

      expect(result[:total]).to eq 600
      expect(result[:signups].size).to eq 600
    end

    it "raises ReadFailed — not a bare connection error — when Redis is unreachable" do
      ENV["WAITLIST_REDIS_URL"] = "redis://127.0.0.1:6390/0" # nothing listening

      expect { described_class.new.fetch }.to raise_error(described_class::ReadFailed)
    end
  end

  describe ".cached_total" do
    it "returns the roster size" do
      store("a@example.com")

      expect(described_class.cached_total).to eq 1
    end

    it "degrades to nil instead of taking the admin nav down with it" do
      ENV["WAITLIST_REDIS_URL"] = "redis://127.0.0.1:6390/0"

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
