# frozen_string_literal: true

require "rails_helper"

# Fuime G1: the public end of a waitlist admit — click the mailed link, land
# in a real session, optionally carry a cohort onto the application.
RSpec.describe "waitlist invite accept", type: :request do
  def redis_url
    uri = URI.parse(ENV["REDIS_URL"].presence || "redis://localhost:6379")
    uri.path = "/15"
    uri.to_s
  end

  let(:redis) { Redis.new(url: redis_url) }
  let(:admin) { create(:user, :make_admin, birthday: 40.years.ago.to_date) }

  def login_as!(user)
    post logins_path, params: { email: user.email, login: { purpose: "" } }
    login = Login.order(:id).last
    post email_login_path(login)
    code = LoginCode.active.where(user:).order(:id).last
    post complete_login_path(login), params: { method: "email", login_code: code.code }
    expect(User::Session.where(user:)).to exist, "login failed for #{user.email}"
  end

  def store(email)
    redis.sadd(Fuime::WaitlistRoster::LIST_KEY, email)
    redis.hset("#{Fuime::WaitlistRoster::META_PREFIX}#{email}",
               "at" => "2026-08-05T10:00:00Z", "source" => "home-hero")
  end

  before do
    ENV["WAITLIST_REDIS_URL"] = redis_url
    redis.flushdb
    ActionMailer::Base.deliveries.clear
  end

  after do
    redis.flushdb
    ENV.delete("WAITLIST_REDIS_URL")
  end

  it "signs a new waitlist user in and sends them to onboarding" do
    store("maya@example.com")
    result = Fuime::WaitlistInviteService.new(invited_by: admin).invite!("maya@example.com")

    get waitlist_invite_path(result.token)

    user = result.user.reload
    expect(user).to be_verified
    expect(User::Session.where(user:)).to exist
    expect(response).to redirect_to(setup_path)
  end

  # Fuime A2: onboarding is finished once a user has a name. Signup does not
  # ask for a phone number, so a blank one must not decide where the invite
  # lands — the same name-only test LoginsController#complete uses.
  it "sends an invitee who already has a name straight to the product, phone or no phone" do
    store("maya@example.com")
    user = create(:user, email: "maya@example.com", full_name: "Maya Founder", phone_number: nil)
    result = Fuime::WaitlistInviteService.new(invited_by: admin).invite!("maya@example.com")

    get waitlist_invite_path(result.token)

    expect(User::Session.where(user:)).to exist
    expect(response).to redirect_to(root_path)
  end

  it "keeps a 2FA user on the existing login flow for the second factor" do
    store("maya@example.com")
    user = create(:user, email: "maya@example.com",
                         use_two_factor_authentication: true,
                         phone_number: "+18556254225",
                         phone_number_verified: true,
                         use_sms_auth: true)
    result = Fuime::WaitlistInviteService.new(invited_by: admin).invite!("maya@example.com")

    get waitlist_invite_path(result.token)

    expect(User::Session.where(user:)).not_to exist
    login = Login.order(:id).last
    expect(login.authenticated_with_email).to be true
    expect(login).to be_incomplete
    expect(response).to redirect_to(choose_login_preference_login_path(login))
  end

  it "refuses a garbage token and points at the ordinary login page" do
    get waitlist_invite_path("not-a-token")

    expect(response).to redirect_to(auth_users_path)
    expect(flash[:error]).to match(/expired or is not valid/)
  end

  it "stamps a cohort onto the application after they click the invite" do
    store("maya@example.com")
    cohort = Fuime::Cohort.create!(
      name: "Founders Weekend", code: "FOUNDERS26", created_by: admin,
      rationale: "I'm running this event and I know everyone attending.",
      expires_at: 3.days.from_now, max_members: 50, risk_level: "slight"
    )
    result = Fuime::WaitlistInviteService
             .new(invited_by: admin, cohort_code: "FOUNDERS26")
             .invite!("maya@example.com")

    get waitlist_invite_path(result.token)
    follow_redirect! if response.redirect?

    get start_applications_path, params: { teen_led: "true" }

    application = Event::Application.order(:id).last
    expect(application.user).to eq(result.user)
    expect(application.fuime_cohort).to eq(cohort)
  end

  it "does not stamp another signed-in user's application with this invite's cohort" do
    store("maya@example.com")
    cohort = Fuime::Cohort.create!(
      name: "Founders Weekend", code: "FOUNDERS26", created_by: admin,
      rationale: "I'm running this event and I know everyone attending.",
      expires_at: 3.days.from_now, max_members: 50, risk_level: "slight"
    )
    result = Fuime::WaitlistInviteService
             .new(invited_by: admin, cohort_code: "FOUNDERS26")
             .invite!("maya@example.com")
    other = create(:user, birthday: 16.years.ago.to_date, full_name: "Other Founder")
    login_as!(other)

    get waitlist_invite_path(result.token)

    expect(response).to redirect_to(root_path)
    expect(flash[:error]).to include("signed in as #{other.email}")

    get start_applications_path, params: { teen_led: "true" }

    application = Event::Application.order(:id).last
    expect(application.user).to eq(other)
    expect(application.fuime_cohort).to be_nil
    expect(application.fuime_cohort).not_to eq(cohort)
  end

  it "still applies a Redis-stamped cohort when they log in the ordinary way" do
    store("maya@example.com")
    cohort = Fuime::Cohort.create!(
      name: "Founders Weekend", code: "FOUNDERS26", created_by: admin,
      rationale: "I'm running this event and I know everyone attending.",
      expires_at: 3.days.from_now, max_members: 50, risk_level: "slight"
    )
    Fuime::WaitlistInviteService
      .new(invited_by: admin, cohort_code: "FOUNDERS26")
      .invite!("maya@example.com")
    user = User.find_by!(email: "maya@example.com")
    user.update!(full_name: "Maya Waitlist", birthday: 16.years.ago.to_date)

    login_as!(user)
    get start_applications_path, params: { teen_led: "true" }

    expect(Event::Application.order(:id).last.fuime_cohort).to eq(cohort)
  end
end
