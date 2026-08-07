# frozen_string_literal: true

require "rails_helper"

# Fuime: /admin/waitlist. The point of it living in Rails rather than on the
# marketing site is this spec — "who may see it" is the admin console's existing
# question, not a shared token somebody has to hand out and remember to revoke.
RSpec.describe "admin waitlist", type: :request do
  # The real login dance (see fuime_billing_spec) — the SessionSupport factory
  # shortcut trips over 2FA state in request specs.
  def login_as!(user)
    post logins_path, params: { email: user.email, login: { purpose: "" } }
    login = Login.order(:id).last
    post email_login_path(login)
    code = LoginCode.active.where(user:).order(:id).last
    post complete_login_path(login), params: { method: "email", login_code: code.code }
    expect(User::Session.where(user:)).to exist, "login failed for #{user.email}"
  end

  let(:admin) { create(:user, :make_admin, birthday: 40.years.ago.to_date, verified: true) }
  let(:normal_user) { create(:user, birthday: 40.years.ago.to_date, verified: true) }

  # A real Redis on DB 15, same reasoning as waitlist_roster_spec: the value of
  # these examples is that the page renders what the store actually returns.
  def redis_url
    uri = URI.parse(ENV["REDIS_URL"].presence || "redis://localhost:6379")
    uri.path = "/15"
    uri.to_s
  end

  let(:redis) { Redis.new(url: redis_url) }

  def configure_store!
    ENV["WAITLIST_REDIS_URL"] = redis_url
  end

  def stub_roster(emails:, metas:)
    emails.each do |email|
      redis.sadd(Fuime::WaitlistRoster::LIST_KEY, email)
      meta = metas[email]
      redis.hset("#{Fuime::WaitlistRoster::META_PREFIX}#{email}", meta) if meta.present?
    end
  end

  before do
    ENV.delete("WAITLIST_REDIS_URL")
    redis.flushdb
    Rails.cache.delete(Fuime::WaitlistRoster::NAV_CACHE_KEY)
  end

  after do
    redis.flushdb
    ENV.delete("WAITLIST_REDIS_URL")
  end

  it "is not reachable by a signed-out visitor" do
    get admin_waitlist_index_path

    expect(response).to have_http_status(:redirect)
  end

  it "is not reachable by an ordinary signed-in user" do
    login_as!(normal_user)

    get admin_waitlist_index_path

    expect(response).to have_http_status(:redirect)
    expect(flash[:error]).to include("admin")
  end

  it "shows any admin the roster and the count against the goal" do
    configure_store!
    stub_roster(
      emails: ["b@example.com", "a@example.com"],
      metas: {
        "b@example.com" => { "at" => "2026-08-06T09:00:00Z", "source" => "pricing-foot", "ip" => "2.2.2.2" },
        "a@example.com" => { "at" => "2026-08-05T10:00:00Z", "source" => "home-hero", "ip" => "1.1.1.1" }
      }
    )
    login_as!(admin)

    get admin_waitlist_index_path

    expect(response).to have_http_status(:success)
    expect(response.body).to include("b@example.com")
    expect(response.body).to include("a@example.com")
    expect(response.body).to include("pricing-foot")
    expect(response.body).to include("1,000") # the goal
    expect(response.body).to include("998 to go")
  end

  it "says it has nothing to read rather than showing a confident zero" do
    login_as!(admin)

    get admin_waitlist_index_path

    expect(response).to have_http_status(:success)
    expect(response.body).to include("No stored list")
  end

  it "renders the page — not a 500 — when the store is unreachable" do
    ENV["WAITLIST_REDIS_URL"] = "redis://127.0.0.1:6390/0" # nothing listening
    login_as!(admin)

    get admin_waitlist_index_path

    expect(response).to have_http_status(:success)
    expect(response.body).to include("Could not read the waitlist")
  end

  # There are two admin surfaces and it is easy to add to one and forget the
  # other: the nav dropdown (Admin::Nav) and the /admin_tools card desk. This
  # is the regression guard — the first version of this feature shipped in the
  # nav only, and the desk is where people actually go looking.
  it "is reachable from both admin surfaces, not just the nav" do
    login_as!(admin)

    get admin_tools_path

    expect(response.body).to include(admin_waitlist_index_path)
    expect(response.body).to include("Waitlist")
  end

  describe "CSV export" do
    it "serves the roster as a download" do
      configure_store!
      stub_roster(
        emails: ["a@example.com"],
        metas: { "a@example.com" => { "at" => "2026-08-05T10:00:00Z", "source" => "home-hero", "ip" => "1.1.1.1" } }
      )
      login_as!(admin)

      get admin_waitlist_index_path(format: :csv)

      expect(response).to have_http_status(:success)
      expect(response.header["Content-Type"]).to include("text/csv")
      expect(response.body).to start_with("email,source,signed_up_at,ip")
      expect(response.body).to include("a@example.com,home-hero")
    end

    it "neutralises a spreadsheet formula smuggled in through the form" do
      configure_store!
      stub_roster(
        emails: ["=cmd|'/c calc'!A1@example.com"],
        metas: { "=cmd|'/c calc'!A1@example.com" => { "at" => "2026-08-05T10:00:00Z", "source" => "=HYPERLINK(\"x\")" } }
      )
      login_as!(admin)

      get admin_waitlist_index_path(format: :csv)

      # Every attacker-controlled cell is prefixed, so Excel treats it as text.
      expect(response.body).to include("'=cmd")
      expect(response.body).to include("'=HYPERLINK")
    end

    it "is refused to an ordinary user like the HTML page is" do
      login_as!(normal_user)

      get admin_waitlist_index_path(format: :csv)

      expect(response).to have_http_status(:redirect)
    end
  end

end
