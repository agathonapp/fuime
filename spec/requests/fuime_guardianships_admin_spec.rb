# frozen_string_literal: true

require "rails_helper"

# Fuime: /admin/guardianships — the stale-pending invite queue (TEEN_GROWTH G5).
#
# How to test by hand:
#   1. As an admin, open /admin/guardianships. A fresh invite is on
#      "All pending", not "Stale".
#   2. In console: g = Guardianship.pending.last; g.update!(invite_sent_at: 8.days.ago)
#      Reload the page — the row is on Stale with an Expired badge.
#   3. Resend invite. Token refreshes; the row leaves Stale.
#   4. For mail: g.update!(invite_sent_at: 3.days.ago - 1.hour,
#      invite_day3_reminded_at: nil); Fuime::GuardianInviteReminderJob.perform_now
#      Check the mailer (letter_opener / logs). Repeat at 6 days. Accept or
#      expire the invite and run again — no mail.
#   5. Confirm the card is on /admin_tools ("Stale guardian invites") and
#      in the Organizations nav.
RSpec.describe "admin guardianships", type: :request do
  def login_as!(user)
    post logins_path, params: { email: user.email, login: { purpose: "" } }
    login = Login.order(:id).last
    post email_login_path(login)
    code = LoginCode.active.where(user:).order(:id).last
    post complete_login_path(login), params: { method: "email", login_code: code.code }
    expect(User::Session.where(user:)).to exist, "login failed for #{user.email}"
  end

  let(:admin) { create(:user, :make_admin, birthday: 40.years.ago.to_date, verified: true, full_name: "Ada Admin") }
  let(:guardian) { create(:user, birthday: 41.years.ago.to_date, verified: true, email: "pat-stale@example.com") }
  let(:teen) { create(:user, :minor, verified: true, full_name: "Maya Stale") }

  describe "the queue" do
    it "shows stale pending invites and hides a fresh one from the default tab" do
      stale = create(:guardianship, :expired_invite, guardian:, minor: teen)
      fresh = create(:guardianship,
                     guardian: create(:user, birthday: 42.years.ago.to_date, email: "fresh-parent@example.com"),
                     minor: create(:user, :minor, email: "fresh-teen@example.com"))

      login_as!(admin)
      get guardianships_admin_index_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Maya Stale", guardian.email, "Expired")
      expect(response.body).to include(resend_invite_guardianship_path(stale))
      expect(response.body).not_to include(fresh.guardian.email)
    end

    it "lists every pending invite on the all-pending tab, oldest first" do
      older = create(:guardianship, :expired_invite, guardian:, minor: teen)
      newer = create(:guardianship,
                     guardian: create(:user, birthday: 42.years.ago.to_date, email: "newer-parent@example.com"),
                     minor: create(:user, :minor, full_name: "Newer Teen"))

      login_as!(admin)
      get guardianships_admin_index_path(filter: "pending")

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(older.guardian.email, newer.guardian.email)
      expect(response.body.index(older.guardian.email)).to be < response.body.index(newer.guardian.email)
    end

    it "shows submitted-not-accepted verifications without identity fields" do
      venture = create(:event, name: "Lemonade Stand")
      GuardianVerification.create!(
        event: venture,
        user: guardian,
        verification_method: GuardianVerification::STRIPE_HOSTED,
        submitted_at: 2.days.ago,
        vendor: "stripe",
        vendor_ref: "vs_admin_queue",
        fields_forwarded: %w[dob]
      )

      login_as!(admin)
      get guardianships_admin_index_path(filter: "verifications")

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Lemonade Stand", "vs_admin_queue", "Stripe hosted")
      expect(response.body).not_to include("ssn")
      expect(response.body).not_to include("data:image")
    end

    it "is admin-only" do
      login_as!(guardian)
      get guardianships_admin_index_path

      expect(response).not_to have_http_status(:ok)
    end
  end

  describe "resend from the queue" do
    it "reuses the existing resend action and leaves the stale list" do
      stale = create(:guardianship, :expired_invite, guardian:, minor: teen)
      old_token = stale.invite_token

      login_as!(admin)
      post resend_invite_guardianship_path(stale)

      expect(stale.reload.invite_token).not_to eq(old_token)
      expect(stale).not_to be_invite_expired
      expect(Guardianship.stale_pending).not_to include(stale)
    end
  end

  describe "discoverability" do
    it "is on both admin surfaces, not just the nav" do
      login_as!(admin)

      get admin_tools_path
      expect(response.body).to include(guardianships_admin_index_path)
      expect(response.body).to include("Stale guardian invites")

      nav = Admin::Nav.new(page_title: "Guardian invites (Fuime)")
      item = nav.sections.flat_map(&:items).find { |i| i.name == "Guardian invites (Fuime)" }
      expect(item).to be_present
      expect(item.path).to eq(guardianships_admin_index_path)
      expect(item).to be_task_count
    end
  end
end
