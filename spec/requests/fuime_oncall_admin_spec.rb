# frozen_string_literal: true

require "rails_helper"

# Fuime: the on-call console and the two surfaces that must work without a session.
#
# How to test by hand:
#   1. As an admin, open /admin/oncall. With nothing configured you should see
#      the FUIME_HEARTBEAT_URL banner and an empty roster.
#   2. rake 'fuime:oncall:add[You,you@fuime.com]' — the row appears, marked
#      "email only", because email is not a page.
#   3. Press "Send a test page". Check the delivery table at the bottom.
#   4. Open the ack link from the email on a phone that is NOT signed in.
RSpec.describe "admin on-call", type: :request do
  def login_as!(user)
    post logins_path, params: { email: user.email, login: { purpose: "" } }
    login = Login.order(:id).last
    post email_login_path(login)
    code = LoginCode.active.where(user:).order(:id).last
    post complete_login_path(login), params: { method: "email", login_code: code.code }
    expect(User::Session.where(user:)).to exist, "login failed for #{user.email}"
  end

  let(:admin) { create(:user, :make_admin, birthday: 40.years.ago.to_date, verified: true, full_name: "Ada Admin") }

  describe "the console" do
    it "renders with nothing configured, and says so" do
      login_as!(admin)
      get "/admin/oncall"

      expect(response).to have_http_status(:ok)
      # The checklist is the most important thing on an unconfigured page: every
      # check below it runs inside the app and none of them can fire if the app
      # is gone.
      expect(response.body).to include("Nothing outside this app is watching it")
      expect(response.body).to include("Set this up")
    end

    # The alternative was a rake task in a Render shell, and a setup step that
    # needs a shell is a setup step that does not happen.
    it "puts the signed-in admin on the roster in one click" do
      login_as!(admin)

      post "/admin/oncall/add_me"

      responder = Fuime::Oncall::Responder.find_by(user: admin)
      expect(responder).to be_present
      expect(responder.email).to eq(admin.email)
      # The gap between "on the roster" and "can be woken" is the one a person is
      # most likely to assume away, so it is said at the moment of adding.
      expect(flash[:success]).to include("not a page")
    end

    it "does not add the same person twice" do
      Fuime::Oncall::Responder.create!(name: "Ada", email: admin.email)
      login_as!(admin)

      expect { post "/admin/oncall/add_me" }.not_to change(Fuime::Oncall::Responder, :count)
    end

    # On a public ntfy server the unguessability of the topic IS the access
    # control. A human picking a name picks "fuime-alerts", which is not a secret.
    it "generates a random ntfy topic rather than letting somebody choose one" do
      responder = Fuime::Oncall::Responder.create!(name: "Ada", email: admin.email)
      login_as!(admin)

      post "/admin/oncall/responders/#{responder.id}/ntfy"

      responder.reload
      expect(responder.push_kind).to eq("ntfy")
      expect(responder.push_url).to match(/\Ahttps:\/\/ntfy\.sh\/fuime-[a-z0-9]{18}\z/)
      expect(responder).to be_pageable
      # Untokened, so Fuime still treats it as public and strips the page down.
      expect(responder).not_to be_push_private
    end

    # The topic is shown once, in the flash, and never in the roster table — that
    # table is a page an admin opens casually and may screen share.
    it "shows the topic once and does not put it in the roster table" do
      responder = Fuime::Oncall::Responder.create!(name: "Ada", email: admin.email)
      login_as!(admin)
      post "/admin/oncall/responders/#{responder.id}/ntfy"
      topic = responder.reload.push_url.split("/").last

      follow_redirect!
      expect(response.body).to include(topic)

      get "/admin/oncall"
      expect(response.body).not_to include(topic)
    end

    it "renders incidents, the roster and the delivery record" do
      Fuime::Oncall::Responder.create!(name: "Ada Admin", email: "ada@fuime.com")
      incident = Fuime::Incident.raise!(key: "test.render", check_name: "workers",
                                        title: "A thing broke", severity: :sev1)
      Fuime::Oncall::Pager.page!(incident)

      login_as!(admin)
      get "/admin/oncall"

      expect(response.body).to include("A thing broke")
      expect(response.body).to include("Ada Admin")
      # A responder with only an email must be visibly not wakeable, or a roster
      # that reaches nobody looks fully staffed.
      expect(response.body).to include("email only")
    end

    it "fires a real page and resolves it, so the test cannot escalate all night" do
      Fuime::Oncall::Responder.create!(name: "Ada Admin", email: "ada@fuime.com")
      login_as!(admin)

      post "/admin/oncall/test_page"

      incident = Fuime::Incident.find_by(key: "oncall.test_page")
      expect(incident).to be_status_resolved
      expect(incident.notifications.pluck(:channel)).to include("email")
    end
  end

  # The whole point of the token is that it works on a phone at 3am without a
  # session. If this ever starts requiring a login, the page stops being
  # acknowledgeable and starts being silenceable — which is the failure this
  # subsystem exists to prevent.
  describe "one-tap acknowledgement" do
    it "acknowledges without a session" do
      incident = Fuime::Incident.raise!(key: "test.ack", check_name: "workers",
                                        title: "Broken", severity: :sev1)

      get "/oncall/ack/#{incident.ack_token}"

      expect(response).to have_http_status(:ok)
      expect(incident.reload).to be_status_acknowledged
    end

    # No hint that a valid token exists, and nothing enumerable.
    it "404s an unknown token" do
      get "/oncall/ack/not-a-real-token"

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "/healthz" do
    # `rails/health#show` answers 200 whenever a Puma worker can render a
    # template — including while the database is unreachable and no worker has
    # existed for a day. An external monitor watching only that would have
    # reported Fuime healthy through an outage in which no sale reached a ledger.
    it "answers without a session and reports keys, never detail" do
      get "/healthz"

      body = response.parsed_body
      expect(body).to have_key("status")
      expect(body["problems"]).to be_an(Array)
      # Keys only: whoever polls this is unauthenticated by construction.
      expect(response.body).not_to match(/venture|amount|\$/i)
    end

    it "answers 503 when infrastructure is sev-1, so a monitor can see it" do
      broken = Class.new(Fuime::Oncall::Check) do
        def self.check_name = "database"

        def call
          [Fuime::Oncall::Check::Finding.new(key: "database.gone", title: "Gone", severity: :sev1)]
        end
      end
      allow(Fuime::Oncall::Check).to receive(:infrastructure).and_return([broken])

      get "/healthz"

      expect(response).to have_http_status(:service_unavailable)
      expect(response.parsed_body["status"]).to eq("unhealthy")
    end
  end
end
