# frozen_string_literal: true

require "rails_helper"

# Fuime: one request pass over the seeded demo world. Proves the admin
# queues, storefront, billing page, and parent-accept screen all render
# the cast — the click-through the walkthrough describes.
RSpec.describe "demo sandbox smoke", :merchant_of_record, type: :request do
  def login_as!(user)
    post logins_path, params: { email: user.email, login: { purpose: "" } }
    login = Login.order(:id).last
    post email_login_path(login)
    code = LoginCode.active.where(user:).order(:id).last
    post complete_login_path(login), params: { method: "email", login_code: code.code }
    expect(User::Session.where(user:)).to exist, "login failed for #{user.email}"
  end

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
    Fuime::DemoSandbox.new.seed!
  end

  after do
    redis.flushdb
    ENV.delete("WAITLIST_REDIS_URL")
  end

  it "lets an admin open every queue and see the demo cast" do
    admin = User.find_by!(email: "demo+admin@fuime.test")
    login_as!(admin)

    get demo_admin_index_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Demo sandbox")
    expect(response.body).to include("demo+teen.pending@fuime.test")
    expect(response.body).to include("DEMOFOUNDERS")

    get admin_waitlist_index_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("demo+waitlist.fresh@fuime.test")

    get applications_admin_index_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Demo Solo Lawn")

    get cohorts_admin_index_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("DEMOFOUNDERS")

    get operator_vetting_admin_index_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Demo Window Wash")

    get guardianships_admin_index_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("demo+parent.stale@fuime.test")

    get nav_admin_index_path, params: { title: "Demo sandbox (Fuime)" }
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Demo sandbox (Fuime)")
  end

  it "renders the storefront, the parent billing page, and the accept checkbox" do
    admin = User.find_by!(email: "demo+admin@fuime.test")
    login_as!(admin)

    get "/b/demo-lawn-care"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Demo Lawn Care")

    delete logout_users_path

    parent = User.find_by!(email: "demo+parent.store@fuime.test")
    login_as!(parent)
    get my_billing_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Upgrade")
    expect(response.body).to include("$19.99")

    delete logout_users_path

    pending_parent = User.find_by!(email: "demo+parent.pending@fuime.test")
    login_as!(pending_parent)
    pending = Guardianship.find_by!(minor: User.find_by!(email: "demo+teen.pending@fuime.test"))
    get guardianship_path(pending.invite_token)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("I confirm")
  end

  it "hides the sandbox when Stripe is live" do
    allow(StripeService).to receive(:live?).and_return(true)
    admin = User.find_by!(email: "demo+admin@fuime.test")
    login_as!(admin)

    get demo_admin_index_path
    expect(response).to redirect_to(admin_tools_path)
  end
end
