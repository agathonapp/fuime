# frozen_string_literal: true

require "rails_helper"

# Fuime: the family-plan page — the paywall's face. The L2 line is the point:
# a subscription is a contract, so only an adult can start or manage one, and
# a minor is told WHO to ask rather than shown a dead button.
RSpec.describe "billing page", type: :request do
  # The real login dance (proven in family_signup_flow_spec) — the
  # SessionSupport factory shortcut trips over 2FA state in request specs.
  def login_as!(user)
    post logins_path, params: { email: user.email, login: { purpose: "" } }
    login = Login.order(:id).last
    post email_login_path(login)
    code = LoginCode.active.where(user:).order(:id).last
    post complete_login_path(login), params: { method: "email", login_code: code.code }
    expect(User::Session.where(user:)).to exist, "login failed for #{user.email}"
  end

  let(:guardian) { create(:user, birthday: 40.years.ago.to_date, verified: true) }
  let(:teen) { create(:user, birthday: 15.years.ago.to_date, verified: true) }

  before { Guardianship.create!(guardian:, minor: teen, status: :active) }

  it "shows an adult the upgrade, and sends them to Stripe checkout" do
    allow(Stripe::Customer).to receive(:create)
      .and_return(Stripe::Customer.construct_from(id: "cus_bill_1"))
    allow(Stripe::Price).to receive(:list)
      .and_return(Stripe::ListObject.construct_from(data: []))
    allow(Stripe::Price).to receive(:create)
      .and_return(Stripe::Price.construct_from(id: "price_bill_1"))
    allow(Stripe::Checkout::Session).to receive(:create)
      .and_return(Stripe::Checkout::Session.construct_from(id: "cs_bill_1", url: "https://checkout.stripe.com/bill"))

    login_as!(guardian)

    get my_billing_path
    expect(response.body).to include("Upgrade")
    expect(response.body).to include("unlimited businesses")

    post my_billing_subscribe_path
    expect(response).to redirect_to("https://checkout.stripe.com/bill")
  end

  it "shows a teen who to ask, and refuses to bill them" do
    login_as!(teen)

    get my_billing_path
    expect(response.body).to include("ask")
    expect(response.body).not_to include("Upgrade —")

    post my_billing_subscribe_path
    expect(response).to redirect_to(my_billing_path)
    expect(flash[:alert]).to include("parent or guardian")
    expect(Fuime::Subscription.count).to eq(0)
  end

  # Staff have no birthday on file, and the age check is fail-closed, so before
  # User#staff? every Fuime admin was shown "ask your parent" on their own
  # subscription page and could not buy the plan they sell.
  it "lets staff buy the plan on their own account, birthday or not" do
    admin = create(:user, :make_admin, :unknown_age, verified: true)

    allow(Stripe::Customer).to receive(:create)
      .and_return(Stripe::Customer.construct_from(id: "cus_bill_admin"))
    allow(Stripe::Price).to receive(:list)
      .and_return(Stripe::ListObject.construct_from(data: []))
    allow(Stripe::Price).to receive(:create)
      .and_return(Stripe::Price.construct_from(id: "price_bill_admin"))
    allow(Stripe::Checkout::Session).to receive(:create)
      .and_return(Stripe::Checkout::Session.construct_from(id: "cs_bill_admin", url: "https://checkout.stripe.com/admin"))

    login_as!(admin)

    get my_billing_path
    expect(response.body).to include("Upgrade —")
    expect(response.body).to include(admin.email) # whose card this is

    post my_billing_subscribe_path
    expect(response).to redirect_to("https://checkout.stripe.com/admin")
  end

  it "sends a subscribed adult to Stripe's portal for management" do
    Fuime::Subscription.create!(billed_to: guardian, status: "active", stripe_customer_id: "cus_port_1")
    allow(Stripe::BillingPortal::Session).to receive(:create)
      .and_return(Stripe::BillingPortal::Session.construct_from(url: "https://billing.stripe.com/p"))

    login_as!(guardian)

    get my_billing_path
    expect(response.body).to include("family plan 🎉")

    post my_billing_portal_path
    expect(response).to redirect_to("https://billing.stripe.com/p")
  end

  # Fuime: the double-subscribe hole. Before the guard, a repeat POST here — a
  # double submit, a back-button re-post — minted a SECOND Stripe subscription
  # against the same customer. The webhook then overwrote stripe_subscription_id,
  # so the first kept charging the card every month with nothing in Fuime able to
  # see it.
  it "refuses to sell the plan twice to the same family" do
    Fuime::Subscription.create!(billed_to: guardian, status: "active", stripe_customer_id: "cus_dupe")
    expect(Stripe::Checkout::Session).not_to receive(:create)

    login_as!(guardian)
    post my_billing_subscribe_path

    expect(response).to redirect_to(my_billing_path)
    expect(flash[:alert]).to include("already on the family plan")
  end

  # past_due / unpaid are stripe_backed but not active. Guarding only #active?
  # left the invisible-charge hole open: a second Checkout session, then the
  # webhook overwrites stripe_subscription_id and the first keeps charging.
  %w[past_due unpaid].each do |status|
    it "refuses a second Checkout when the existing Stripe subscription is #{status}" do
      Fuime::Subscription.create!(
        billed_to: guardian,
        status:,
        stripe_customer_id: "cus_#{status}",
        stripe_subscription_id: "sub_#{status}"
      )
      expect(Stripe::Checkout::Session).not_to receive(:create)
      allow(Stripe::BillingPortal::Session).to receive(:create)
        .and_return(Stripe::BillingPortal::Session.construct_from(url: "https://billing.stripe.com/#{status}"))

      login_as!(guardian)

      get my_billing_path
      expect(response.body).not_to include("Upgrade —")
      expect(response.body).to include("Manage billing")

      post my_billing_subscribe_path
      expect(response).to redirect_to("https://billing.stripe.com/#{status}")
    end
  end

  it "tells a comped family there is nothing to buy, and shows no card controls" do
    admin = create(:user, :make_admin, verified: true)
    Fuime::Subscription.grant_family_plan!(user: guardian, by: admin, notes: "school partner")
    expect(Stripe::Checkout::Session).not_to receive(:create)

    login_as!(guardian)

    get my_billing_path
    expect(response.body).to include("comped this plan")
    expect(response.body).not_to include("Manage billing")

    post my_billing_subscribe_path
    expect(flash[:alert]).to include("comped by Fuime")
  end
end
