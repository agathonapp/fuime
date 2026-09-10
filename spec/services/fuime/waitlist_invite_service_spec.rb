# frozen_string_literal: true

require "rails_helper"

# Fuime G1: admit a waitlist address. The value of these examples is the
# contract — create a login-ready user, mail a working link, stamp Redis —
# against a real store, same as waitlist_roster_spec.
RSpec.describe Fuime::WaitlistInviteService do
  def redis_url
    uri = URI.parse(ENV["REDIS_URL"].presence || "redis://localhost:6379")
    uri.path = "/15"
    uri.to_s
  end

  let(:redis) { Redis.new(url: redis_url) }
  let(:admin) { create(:user, :make_admin, birthday: 40.years.ago.to_date, email: "ops@example.com") }

  def store(email, at: "2026-08-05T10:00:00Z", source: "home-hero")
    redis.sadd(Fuime::WaitlistRoster::LIST_KEY, email)
    redis.hset("#{Fuime::WaitlistRoster::META_PREFIX}#{email}",
               "at" => at, "source" => source, "ip" => "1.1.1.1")
  end

  before do
    ENV["WAITLIST_REDIS_URL"] = redis_url
    redis.flushdb
    Rails.cache.delete(Fuime::WaitlistRoster::NAV_CACHE_KEY)
    ActionMailer::Base.deliveries.clear
  end

  after do
    redis.flushdb
    ENV.delete("WAITLIST_REDIS_URL")
  end

  describe "#invite!" do
    it "creates a user, mails a login link, and stamps the roster" do
      store("maya@example.com")

      result = described_class.new(invited_by: admin).invite!("Maya@Example.com")

      expect(result.email).to eq("maya@example.com")
      expect(result.user).to be_waitlist
      expect(result.user.email).to eq("maya@example.com")
      expect(ActionMailer::Base.deliveries.size).to eq(1)
      mail = ActionMailer::Base.deliveries.last
      expect(mail.to).to eq(["maya@example.com"])
      expect(mail.subject).to include("You're in")
      expect(mail.html_part.body.to_s).to include(waitlist_invite_url(result.token))

      stamp = Fuime::WaitlistRoster.new.invite_stamp("maya@example.com")
      expect(stamp.invited_by).to eq(admin.email)
      expect(stamp.invited_at).to be_present
    end

    it "reuses an existing user instead of duplicating" do
      store("maya@example.com")
      existing = create(:user, email: "maya@example.com", creation_method: :login)

      result = described_class.new(invited_by: admin).invite!("maya@example.com")

      expect(result.user).to eq(existing)
      expect(existing.reload.creation_method).to eq("login")
    end

    it "stamps a live cohort and puts the code in the mail" do
      store("maya@example.com")
      cohort = Fuime::Cohort.create!(
        name: "Founders Weekend", code: "FOUNDERS26", created_by: admin,
        rationale: "I'm running this event and I know everyone attending.",
        expires_at: 3.days.from_now, max_members: 50, risk_level: "slight"
      )

      result = described_class.new(invited_by: admin, cohort_code: "founders26").invite!("maya@example.com")

      expect(result.cohort).to eq(cohort)
      expect(ActionMailer::Base.deliveries.last.text_part.body.to_s).to include("FOUNDERS26")
      expect(Fuime::WaitlistRoster.new.invite_stamp("maya@example.com").cohort_code).to eq("FOUNDERS26")
    end

    it "refuses an address that is not on the waitlist" do
      expect {
        described_class.new(invited_by: admin).invite!("stranger@example.com")
      }.to raise_error(described_class::Error, /not on the waitlist/)
      expect(ActionMailer::Base.deliveries).to be_empty
      expect(User.find_by(email: "stranger@example.com")).to be_nil
    end

    it "turns a mail outage into a service error instead of a 500" do
      store("maya@example.com")
      allow(WaitlistMailer).to receive(:invite).and_raise(StandardError, "smtp down")

      expect {
        described_class.new(invited_by: admin).invite!("maya@example.com")
      }.to raise_error(described_class::Error, /couldn't send the invite email/)
      expect(Fuime::WaitlistRoster.new.invite_stamp("maya@example.com")).to be_nil
    end

    it "refuses a dead cohort code" do
      store("maya@example.com")
      Fuime::Cohort.create!(
        name: "Expired Event", code: "OLDCODE1", created_by: admin,
        rationale: "This event already happened.",
        expires_at: 1.day.ago, max_members: 50, risk_level: "slight"
      )

      expect {
        described_class.new(invited_by: admin, cohort_code: "OLDCODE1").invite!("maya@example.com")
      }.to raise_error(described_class::Error, /not admitting/)
      expect(ActionMailer::Base.deliveries).to be_empty
    end
  end

  describe "#invite_next!" do
    it "invites the oldest uninvited addresses first" do
      store("new@example.com", at: "2026-08-08T10:00:00Z")
      store("old@example.com", at: "2026-08-01T10:00:00Z")
      store("mid@example.com", at: "2026-08-04T10:00:00Z")

      outcome = described_class.new(invited_by: admin).invite_next!(count: 2)

      expect(outcome[:invited].map(&:email)).to eq(["old@example.com", "mid@example.com"])
      expect(outcome[:errors]).to be_empty
      expect(Fuime::WaitlistRoster.new.invite_stamp("new@example.com")).to be_nil
    end

    it "skips addresses that are already invited" do
      store("old@example.com", at: "2026-08-01T10:00:00Z")
      store("new@example.com", at: "2026-08-08T10:00:00Z")
      described_class.new(invited_by: admin).invite!("old@example.com")
      ActionMailer::Base.deliveries.clear

      outcome = described_class.new(invited_by: admin).invite_next!(count: 1)

      expect(outcome[:invited].map(&:email)).to eq(["new@example.com"])
    end

    it "refuses a count outside 1..25" do
      store("a@example.com")

      expect {
        described_class.new(invited_by: admin).invite_next!(count: 0)
      }.to raise_error(described_class::Error, /between 1 and 25/)
      expect {
        described_class.new(invited_by: admin).invite_next!(count: 26)
      }.to raise_error(described_class::Error, /between 1 and 25/)
    end
  end

  describe ".verify_token" do
    it "returns the user and the cohort code from the Redis stamp" do
      store("maya@example.com")
      user = create(:user, email: "maya@example.com")
      Fuime::WaitlistRoster.new.mark_invited("maya@example.com", invited_by: admin.email, cohort_code: "FOUNDERS26")
      token = described_class.generate_token(user:)

      expect(described_class.verify_token(token)).to eq([user, "FOUNDERS26"])
    end

    it "returns nil for garbage" do
      expect(described_class.verify_token("nope")).to be_nil
    end
  end
end
