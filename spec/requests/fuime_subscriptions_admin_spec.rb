# frozen_string_literal: true

require "rails_helper"

# Fuime: /admin/subscriptions — the family-plan queue and the two writes an admin
# is allowed to make to it.
#
# The property worth asserting beyond "it renders": an admin can GIVE the plan
# away but cannot edit a subscription Stripe is billing. That boundary is the
# whole reason this model was read-only until now, and a page with buttons on it
# is exactly how such a boundary gets lost.
RSpec.describe "admin subscriptions", type: :request do
  # The real login dance — the SessionSupport factory shortcut trips over 2FA
  # state in request specs. Same as fuime_cohorts_admin_spec.
  def login_as!(user)
    post logins_path, params: { email: user.email, login: { purpose: "" } }
    login = Login.order(:id).last
    post email_login_path(login)
    code = LoginCode.active.where(user:).order(:id).last
    post complete_login_path(login), params: { method: "email", login_code: code.code }
    expect(User::Session.where(user:)).to exist, "login failed for #{user.email}"
  end

  let(:admin) { create(:user, :make_admin, birthday: 40.years.ago.to_date, verified: true, full_name: "Ada Admin") }
  let(:guardian) { create(:user, birthday: 40.years.ago.to_date, verified: true, full_name: "Gina Guardian") }
  let(:teen) { create(:user, birthday: 15.years.ago.to_date, verified: true) }

  describe "the queue" do
    it "renders, and separates a comp from a paid subscription" do
      Fuime::Subscription.grant_family_plan!(user: guardian, by: admin, notes: "Founders Weekend")
      payer = create(:user, birthday: 41.years.ago.to_date)
      Fuime::Subscription.create!(billed_to: payer, status: "past_due",
                                  stripe_customer_id: "cus_q", stripe_subscription_id: "sub_q")

      login_as!(admin)
      get subscriptions_admin_index_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Comped", guardian.email)
      expect(response.body).to include("Past due", "sub_q")
      # The comp offers a revoke; the paid one only offers Stripe.
      expect(response.body).to include("Revoke comp", "Cancel at Stripe")
    end

    it "renders a per-venture subscription too, not just family ones" do
      venture = create(:event, plan_type: Event::Plan::Standard)
      Fuime::Subscription.create!(billed_to: guardian, event: venture, status: "active",
                                  stripe_customer_id: "cus_v", stripe_subscription_id: "sub_v")

      login_as!(admin)
      get subscriptions_admin_index_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(venture.name, "one venture")
    end

    it "is admin-only" do
      login_as!(guardian)
      get subscriptions_admin_index_path

      expect(response).not_to have_http_status(:ok)
    end
  end

  describe "comping the plan" do
    it "grants by email and records the admin who did it" do
      login_as!(admin)

      post subscription_grant_admin_index_path, params: { user_id: guardian.email, notes: "school partner" }

      record = Fuime::Subscription.family.find_by(billed_to: guardian)
      expect(record).to be_active
      expect(record).to be_comped
      expect(record.granted_by).to eq(admin)
      expect(record.grant_notes).to include("Ada Admin", "school partner")
    end

    it "grants by id too" do
      login_as!(admin)
      post subscription_grant_admin_index_path, params: { user_id: guardian.id }

      expect(Fuime::Subscription.family.find_by(billed_to: guardian)).to be_active
    end

    it "says so when nobody matches, rather than 500ing" do
      login_as!(admin)
      post subscription_grant_admin_index_path, params: { user_id: "nobody@example.com" }

      expect(response).to have_http_status(:redirect)
      expect(flash[:alert]).to include("No user matches")
      expect(Fuime::Subscription.count).to eq(0)
    end

    it "refuses to overwrite a Stripe-billed subscription" do
      Fuime::Subscription.create!(billed_to: guardian, status: "past_due",
                                  stripe_customer_id: "cus_r", stripe_subscription_id: "sub_r")
      login_as!(admin)

      post subscription_grant_admin_index_path, params: { user_id: guardian.email }

      expect(flash[:alert]).to include("Cancel or change it in Stripe")
      expect(Fuime::Subscription.family.find_by(billed_to: guardian).status).to eq("past_due")
    end

    it "is not reachable by a non-admin" do
      login_as!(guardian)
      post subscription_grant_admin_index_path, params: { user_id: guardian.email }

      expect(Fuime::Subscription.count).to eq(0)
    end
  end

  describe "revoking" do
    it "cancels a comp" do
      record = Fuime::Subscription.grant_family_plan!(user: guardian, by: admin)
      login_as!(admin)

      post subscription_revoke_admin_index_path(record)

      expect(record.reload.status).to eq("canceled")
      expect(User.find(guardian.id).fuime_pro?).to be false
    end

    it "refuses to revoke a Stripe-billed subscription locally" do
      record = Fuime::Subscription.create!(billed_to: guardian, status: "active",
                                           stripe_customer_id: "cus_s", stripe_subscription_id: "sub_s")
      login_as!(admin)

      post subscription_revoke_admin_index_path(record)

      expect(flash[:alert]).to include("cancel it there")
      expect(record.reload.status).to eq("active")
    end
  end

  describe "cancelling at Stripe" do
    it "calls Stripe and leaves the mirror to the webhook" do
      record = Fuime::Subscription.create!(billed_to: guardian, status: "active",
                                           stripe_customer_id: "cus_t", stripe_subscription_id: "sub_t")
      expect(Stripe::Subscription).to receive(:cancel)
        .with("sub_t", {}, hash_including(:api_key))
        .and_return(Stripe::Subscription.construct_from(id: "sub_t", status: "canceled"))
      login_as!(admin)

      post subscription_cancel_in_stripe_admin_index_path(record)

      expect(flash[:success]).to include("Cancelled at Stripe")
      expect(record.reload.status).to eq("active")
    end

    it "surfaces a Stripe refusal instead of erroring" do
      record = Fuime::Subscription.create!(billed_to: guardian, status: "active",
                                           stripe_customer_id: "cus_u", stripe_subscription_id: "sub_u")
      allow(Stripe::Subscription).to receive(:cancel)
        .and_raise(Stripe::InvalidRequestError.new("No such subscription", nil))
      login_as!(admin)

      post subscription_cancel_in_stripe_admin_index_path(record)

      expect(flash[:alert]).to include("Stripe refused")
    end
  end

  describe "the panel on a user's admin page" do
    it "offers the comp on an adult account" do
      login_as!(admin)
      get admin_user_path(guardian)

      expect(response.body).to include("Family plan", "Comp the family plan")
    end

    it "refuses to comp to a minor, because a subscription is a contract (L2)" do
      login_as!(admin)
      get admin_user_path(teen)

      expect(response.body).to include("Family plan")
      expect(response.body).not_to include("Comp the family plan")
      expect(response.body).to include("only be comped to a confirmed")
    end
  end
end
