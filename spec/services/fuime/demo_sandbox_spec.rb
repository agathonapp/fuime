# frozen_string_literal: true

require "rails_helper"

# Fuime: the demo sandbox is the founder's "test everything" world.
# These examples prove seed is idempotent, reset is scoped, and live Stripe
# can never mint demo users or login codes.
RSpec.describe Fuime::DemoSandbox do
  def redis_url
    uri = URI.parse(ENV["REDIS_URL"].presence || "redis://localhost:6379")
    uri.path = "/15"
    uri.to_s
  end

  let(:redis) { Redis.new(url: redis_url) }

  before do
    ENV["WAITLIST_REDIS_URL"] = redis_url
    redis.flushdb
    Rails.cache.delete(Fuime::WaitlistRoster::NAV_CACHE_KEY)
  end

  after do
    redis.flushdb
    ENV.delete("WAITLIST_REDIS_URL")
  end

  describe ".enabled?" do
    it "is on in test when Stripe is not live" do
      expect(described_class.enabled?).to be(true)
    end

    it "is off when Stripe is live" do
      allow(StripeService).to receive(:live?).and_return(true)

      expect(described_class.enabled?).to be(false)
    end
  end

  describe "#seed! / #reset!" do
    it "seeds a recognizable cast and is safe to run twice" do
      described_class.new.seed!
      first_ids = User.where("email LIKE ?", "demo+%@fuime.test").pluck(:id).sort

      described_class.new.seed!
      second_ids = User.where("email LIKE ?", "demo+%@fuime.test").pluck(:id).sort

      expect(second_ids).to eq(first_ids)
      expect(User.find_by(email: "demo+admin@fuime.test")).to be_superadmin
      expect(User.find_by(email: "demo+admin@fuime.test").creation_method).to eq("demo")
      expect(described_class.new.smoke_checks).to all(satisfy { |(_name, ok)| ok })
    end

    it "reset removes only the demo cast" do
      stranger = create(:user, email: "real-founder@example.com", verified: true)
      described_class.new.seed!

      described_class.new.reset!

      expect(User.where("email LIKE ?", "demo+%@fuime.test")).to be_empty
      expect(Event.unscoped.where(slug: described_class::SLUGS.values)).to be_empty
      expect(Fuime::Cohort.find_by(code: described_class::COHORT_CODE)).to be_nil
      expect(User.find_by(email: stranger.email)).to eq(stranger)
    end

    it "refuses to seed when Stripe is live" do
      allow(StripeService).to receive(:live?).and_return(true)

      expect { described_class.new.seed! }.to raise_error(described_class::Error, /live/)
    end
  end

  describe "#mint_login_code!" do
    it "issues a code for a seeded demo mailbox and refuses any other" do
      described_class.new.seed!

      code = described_class.new.mint_login_code!("demo+admin@fuime.test")
      expect(code).to be_active
      expect(code.user.email).to eq("demo+admin@fuime.test")

      expect {
        described_class.new.mint_login_code!("maya@example.com")
      }.to raise_error(described_class::Error, /demo mailbox/)
    end
  end
end
