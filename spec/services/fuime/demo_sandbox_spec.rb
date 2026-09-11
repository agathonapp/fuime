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
      expect(Event.unscoped.where(slug: described_class::SLUGS.values)).to all(satisfy(&:plan))
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

    it "resets after checkout leftovers, a billing row, a waive, and a Solo admit" do
      described_class.new.seed!
      store = Event.unscoped.find_by!(slug: described_class::SLUGS[:storefront])
      admin = User.find_by!(email: "demo+admin@fuime.test")
      parent = User.find_by!(email: "demo+parent.store@fuime.test")
      uma = User.find_by!(email: "demo+teen.unguarded@fuime.test")
      sonia = User.find_by!(email: "demo+teen.solo@fuime.test")
      application = Event::Application.find_by!(user: sonia, name: "Demo Solo Lawn")

      item = create(:ledger_item, amount_cents: 35_00, memo: "Demo leftover checkout")
      Ledger::Mapping.create!(ledger: store.ledger, ledger_item: item, on_primary_ledger: true)
      cpt = create(:canonical_pending_transaction, amount_cents: 35_00, memo: "Demo leftover [fuime_pi_demo]", ledger_item: item)
      create(:canonical_pending_event_mapping, event: store, canonical_pending_transaction: cpt)
      Fuime::Subscription.create!(billed_to: parent, status: "incomplete")
      uma.update_columns(guardian_requirement_waived_at: Time.current, guardian_requirement_waived_by_id: admin.id)
      admitted = create(:event, name: "Demo Solo Lawn", slug: "demo-solo-admitted-#{SecureRandom.hex(3)}")
      application.update_columns(event_id: admitted.id, aasm_state: "approved")

      expect { described_class.new.reset! }.not_to raise_error

      expect(User.where("email LIKE ?", "demo+%@fuime.test")).to be_empty
      expect(Event.unscoped.where(slug: described_class::SLUGS.values)).to be_empty
      expect(Event.unscoped.where(id: admitted.id)).to be_empty
      expect(Fuime::Subscription.where(billed_to: parent)).to be_empty
      expect(CanonicalPendingEventMapping.where(event_id: store.id)).to be_empty
      expect(Ledger.where(event_id: store.id)).to be_empty
    end
  end

  describe "#setup!" do
    it "wipes extras then reseeds a clean cast" do
      described_class.new.seed!
      User.find_by!(email: "demo+teen.unguarded@fuime.test").update_columns(full_name: "MUTATED")
      create(:user, email: "demo+orphan@fuime.test", verified: true)

      described_class.new.setup!

      expect(User.find_by(email: "demo+orphan@fuime.test")).to be_nil
      expect(User.find_by!(email: "demo+teen.unguarded@fuime.test").full_name).to eq("Uma Unguarded")
      expect(described_class.new.smoke_checks).to all(satisfy { |(_name, ok)| ok })
    end
  end

  describe "#checklist" do
    it "locks the 15-minute ids and every step has a path plus expect" do
      steps = described_class.new.checklist

      expect(steps.map { |step| step[:id] }).to eq(described_class::CHECKLIST_IDS)
      steps.each do |step|
        expect(step[:href].to_s).to start_with("/")
        expect(step[:expect]).to be_present
        expect(step[:title]).to be_present
        expect(step[:do]).to be_present
      end
    end

    it "points seeded steps at the live records" do
      described_class.new.seed!
      steps = described_class.new.checklist.index_by { |step| step[:id] }

      expect(steps["accept"][:href]).to match(/\A\/guardian\//)
      expect(steps["waive"][:href]).to match(/\A\/users\/.+\/admin\z/)
      expect(steps["solo"][:href]).to match(/\/submission\z/)
      expect(steps["checkout"][:href]).to eq("/b/demo-lawn-care")
      expect(steps.fetch("waitlist")[:expect]).to eq("demo+waitlist.fresh@fuime.test")

      stranger = create(:user, email: "other-applicant@example.com")
      decoy = create(:event_application, user: stranger, name: "Demo Solo Lawn")
      sonia_app = Event::Application.find_by!(user: User.find_by!(email: "demo+teen.solo@fuime.test"), name: "Demo Solo Lawn")
      href = described_class.new.checklist.find { |step| step[:id] == "solo" }[:href]
      expect(href).to eq(Rails.application.routes.url_helpers.submission_application_path(sonia_app))
      expect(href).not_to eq(Rails.application.routes.url_helpers.submission_application_path(decoy))
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

    it "refuses mint and remind writes without staging confirm outside local" do
      allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new("production"))
      ENV[described_class::STAGING_FLAG] = "1"
      ENV.delete(described_class::WRITE_CONFIRM)
      allow(StripeService).to receive(:live?).and_return(false)

      expect {
        described_class.new.mint_login_code!("demo+admin@fuime.test")
      }.to raise_error(described_class::Error, /FUIME_DEMO_CONFIRM/)
      expect { described_class.new.remind_now! }.to raise_error(described_class::Error, /FUIME_DEMO_CONFIRM/)
    ensure
      ENV.delete(described_class::STAGING_FLAG)
      ENV.delete(described_class::WRITE_CONFIRM)
    end
  end

  describe "#remind_now!" do
    it "nudges only the demo day-3 invite, not a real pending family" do
      described_class.new.seed!
      stranger = create(
        :guardianship,
        :due_for_day3_reminder,
        guardian: create(:user, email: "real-parent@example.com", birthday: 40.years.ago.to_date),
        minor: create(:user, email: "real-teen@example.com", birthday: 15.years.ago.to_date)
      )
      remy = User.find_by!(email: "demo+teen.remind@fuime.test")
      demo = Guardianship.find_by!(minor: remy)

      described_class.new.remind_now!

      expect(demo.reload.invite_day3_reminded_at).to be_present
      expect(stranger.reload.invite_day3_reminded_at).to be_nil
    end
  end
end
