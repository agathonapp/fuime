# frozen_string_literal: true

require "rails_helper"

# Fuime: /admin/operator_vetting — the queue where a human decides who may sell.
#
# This page is the only way an operator gets unblocked, so "it renders" and "the
# buttons post the right thing" are load-bearing rather than cosmetic: a broken
# form here means nobody can sell at all, and the failure looks like a product
# outage rather than an admin bug.
RSpec.describe "admin operator vetting", type: :request do
  # The real login dance (see fuime_waitlist_admin_spec) — the SessionSupport
  # factory shortcut trips over 2FA state in request specs.
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

  # Pinned rather than Faker'd: several examples match rendered HTML, and a name
  # containing an apostrophe or ampersand is escaped in the output — a
  # seed-dependent flake. Same reasoning as storefronts_controller_spec.
  let!(:waiting) { create(:event, :unvetted, name: "Maya Design Studio", slug: "maya-design") }

  describe "who may see it" do
    it "refuses a signed-out visitor" do
      get operator_vetting_admin_index_path

      expect(response).not_to have_http_status(:ok)
    end

    # The queue lists children's names and ages. It is an admin surface and has
    # to stay one.
    it "refuses a signed-in non-admin" do
      login_as!(normal_user)

      get operator_vetting_admin_index_path

      expect(response).not_to have_http_status(:ok)
      expect(response.body).not_to include("Maya Design Studio")
    end

    # Reading the queue and acting on it are separate authorisations, so the POST
    # is checked on its own rather than assumed from the GET. Approving yourself
    # is the whole prize here — an operator who can reach this endpoint can lift
    # their own suspension.
    it "refuses a decision from a signed-in non-admin" do
      login_as!(normal_user)

      post operator_vetting_decide_admin_index_path(id: waiting.slug),
           params: { status: "approved" }

      expect(waiting.reload).to be_operator_vetting_unvetted
    end

    it "refuses a decision from a signed-out visitor" do
      post operator_vetting_decide_admin_index_path(id: waiting.slug),
           params: { status: "approved" }

      expect(waiting.reload).to be_operator_vetting_unvetted
    end
  end

  context "as an admin" do
    before { login_as!(admin) }

    describe "the queue" do
      it "renders and lists a venture waiting for review" do
        get operator_vetting_admin_index_path

        expect(response).to have_http_status(:ok)
        expect(response.body).to include("Maya Design Studio")
      end

      it "shows why the venture cannot sell" do
        get operator_vetting_admin_index_path

        expect(response.body).to match(/not been approved by Fuime yet/)
      end

      it "filters to a single status" do
        create(:event, name: "Already Approved Co")

        get operator_vetting_admin_index_path(status: "unvetted")

        expect(response.body).to include("Maya Design Studio")
        expect(response.body).not_to include("Already Approved Co")
      end

      # A junk status must not silently return everything as though it filtered.
      it "ignores a status outside the enum rather than filtering on it" do
        get operator_vetting_admin_index_path(status: "'; DROP TABLE events; --")

        expect(response).to have_http_status(:ok)
        expect(response.body).to include("Maya Design Studio")
      end

      it "puts unreviewed ventures above reviewed ones" do
        create(:event, name: "Already Approved Co")

        get operator_vetting_admin_index_path

        expect(response.body.index("Maya Design Studio"))
          .to be < response.body.index("Already Approved Co")
      end
    end

    describe "deciding" do
      it "approves, and records who decided" do
        post operator_vetting_decide_admin_index_path(id: waiting.slug),
             params: { status: "approved", notes: "Spoke to the parent" }

        expect(waiting.reload).to be_operator_vetting_approved
        expect(waiting.operator_vetted_by).to eq(admin)
        expect(waiting.operator_vetting_notes).to include("Spoke to the parent")
      end

      it "lets an approved venture sell" do
        create(:stripe_connected_account, :ready, event: waiting)
        expect(waiting.reload.accepts_payments?).to be(false)

        post operator_vetting_decide_admin_index_path(id: waiting.slug),
             params: { status: "approved" }

        expect(waiting.reload.accepts_payments?).to be(true)
      end

      it "suspends" do
        post operator_vetting_decide_admin_index_path(id: waiting.slug),
             params: { status: "suspended", notes: "Chargebacks" }

        expect(waiting.reload).to be_operator_vetting_suspended
      end

      it "rejects" do
        post operator_vetting_decide_admin_index_path(id: waiting.slug),
             params: { status: "rejected" }

        expect(waiting.reload).to be_operator_vetting_rejected
      end

      # The three buttons share one form and one `status` param, which is exactly
      # the shape that breaks quietly if the markup regresses to `form.submit`
      # (whose label IS its value). If this ever posts "Approve" instead of
      # "approved", the controller must not guess.
      it "refuses a status outside the enum and changes nothing" do
        post operator_vetting_decide_admin_index_path(id: waiting.slug),
             params: { status: "Approve" }

        expect(waiting.reload).to be_operator_vetting_unvetted
        expect(flash[:alert]).to be_present
      end

      it "refuses a missing status" do
        post operator_vetting_decide_admin_index_path(id: waiting.slug)

        expect(waiting.reload).to be_operator_vetting_unvetted
      end

    end
  end
end
