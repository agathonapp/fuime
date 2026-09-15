# frozen_string_literal: true

require "rails_helper"

# Fuime: the screen that makes outbound webhooks exist for a founder rather than
# only for Fuime. The machinery shipped with no UI at all, so a founder could not
# create an endpoint by any route.
RSpec.describe "webhooks screen", :merchant_of_record, type: :request do
  def sign_in(user)
    post logins_path, params: { email: user.email, login: { purpose: "" } }
    login = Login.order(:id).last
    post email_login_path(login)
    code = LoginCode.active.where(user:).order(:id).last
    post complete_login_path(login), params: { method: "email", login_code: code.code }
    expect(User::Session.where(user:)).to exist, "login failed for #{user.email}"
  end

  let(:founder) { create(:user) }
  let(:event) { create(:event, organizers: [founder]) }
  let(:stranger) { create(:user) }

  it "explains what the page is for before any endpoint exists" do
    sign_in(founder)

    get fuime_webhooks_path(event_slug: event.slug)

    expect(response).to have_http_status(:ok)
    expect(response.body).to match(/when you make a sale/i)
  end

  it "adds an endpoint and shows the signing secret once" do
    sign_in(founder)

    expect {
      post fuime_webhooks_create_path(event_slug: event.slug),
           params: { url: "https://hooks.example.com/fuime", description: "my bot" }
    }.to change(Fuime::WebhookEndpoint, :count).by(1)

    expect(response.body).to include(Fuime::WebhookEndpoint::SECRET_PREFIX)
  end

  # The secret must live in one response body and in no cookie, cache or log —
  # the session is Rails' default COOKIE store, so the flash would write a live
  # credential to disk. Same reasoning as the API-key reveal.
  it "never carries the secret into a later request" do
    sign_in(founder)
    post fuime_webhooks_create_path(event_slug: event.slug),
         params: { url: "https://hooks.example.com/fuime" }

    get fuime_webhooks_path(event_slug: event.slug)

    expect(response.body).not_to include(Fuime::WebhookEndpoint::SECRET_PREFIX)
  end

  it "tells a founder why a private address was refused, rather than failing silently" do
    sign_in(founder)

    expect {
      post fuime_webhooks_create_path(event_slug: event.slug),
           params: { url: "https://169.254.169.254/latest/meta-data/" }
    }.not_to change(Fuime::WebhookEndpoint, :count)

    follow_redirect!
    expect(response.body).to match(/private address/i)
  end

  it "refuses plaintext http with a readable reason" do
    sign_in(founder)

    post fuime_webhooks_create_path(event_slug: event.slug),
         params: { url: "http://hooks.example.com/x" }

    follow_redirect!
    expect(response.body).to match(/https/i)
  end

  # Disable rather than delete: the delivery history is the only evidence of
  # what went wrong on an endpoint that broke overnight.
  it "turns an endpoint off without losing its history" do
    endpoint = Fuime::WebhookEndpoint.create!(event:, url: "https://hooks.example.com/a")
    Fuime::WebhookDelivery.create!(endpoint:, event_id: "evt_1", event_type: "sale.completed",
                                   payload: {}, status: "failed")
    sign_in(founder)

    delete fuime_webhook_disable_path(event_slug: event.slug, id: endpoint.id)

    expect(endpoint.reload).not_to be_enabled
    expect(Fuime::WebhookDelivery.where(endpoint:).count).to eq(1)
  end

  it "says whether anything has actually been delivered" do
    Fuime::WebhookEndpoint.create!(event:, url: "https://hooks.example.com/a")
    sign_in(founder)

    get fuime_webhooks_path(event_slug: event.slug)

    expect(response.body).to match(/Nothing delivered yet/i)
  end

  it "refuses a stranger" do
    sign_in(stranger)

    get fuime_webhooks_path(event_slug: event.slug)

    expect(response).not_to have_http_status(:ok)
  end
end
