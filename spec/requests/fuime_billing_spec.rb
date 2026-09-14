# frozen_string_literal: true

require "rails_helper"

# Fuime: the billing page.
#
# ── 2026-09-14: there is nothing to sell here any more ───────────────────────
#
# This page used to be the paywall's face, and most of this file tested the
# upgrade funnel: who was allowed to enter a card (L2 — a subscription is a
# contract, so only an adult), who was told whom to ask, and the guards against
# selling the same family the plan twice.
#
# Fuime moved to one flat price with nothing gated, so the funnel is gone. What
# replaces those examples is the inverse contract, and it is worth as much:
#
#   1. NOBODY can start a subscription any more — including the adults who used
#      to be allowed to. Enforced in the controller, not by hiding a button, so
#      a bookmarked POST cannot charge anyone for a plan that grants nothing.
#   2. Families still being billed can still reach the portal to CANCEL. That is
#      now the only Stripe writer on this controller, and breaking it would trap
#      a parent in a subscription Fuime retired underneath them.
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

  describe "with nothing to sell" do
    it "states the one price to an adult, and offers no upgrade" do
      login_as!(guardian)

      get my_billing_path

      expect(response.body).to include("5% + $0.50")
      expect(response.body).not_to match(/Upgrade/)
    end

    # The page used to branch three ways on who was allowed to enter a card.
    # Nobody enters a card now, so a teen sees the same thing an adult does —
    # and specifically is NOT told to go and ask someone for an upgrade that
    # does not exist.
    it "shows a teen the same price, and sends them to ask nobody" do
      login_as!(teen)

      get my_billing_path

      expect(response.body).to include("5% + $0.50")
      expect(response.body).not_to match(/Upgrade|ask your parent|to upgrade from their account/i)
    end

    # The control that matters: the button is gone, but this route has always
    # been reachable by a bookmark or a back-button re-post. Selling a plan that
    # grants nothing would be a recurring charge for a feature set every account
    # already has.
    it "refuses to start a subscription, even for an adult who used to be allowed" do
      login_as!(guardian)

      expect { post my_billing_subscribe_path }.not_to change(Fuime::Subscription, :count)

      expect(response).to redirect_to(my_billing_path)
      expect(flash[:alert]).to include("one flat price")
      expect(flash[:alert]).to include("nothing to subscribe to")
    end

    it "refuses a minor too, without ever reaching Stripe" do
      expect(Stripe::Checkout::Session).not_to receive(:create)
      login_as!(teen)

      post my_billing_subscribe_path

      expect(response).to redirect_to(my_billing_path)
    end
  end

  # Retiring a plan must not trap the families still paying for it.
  describe "a family still being billed for the retired plan" do
    before do
      Fuime::Subscription.create!(billed_to: guardian, status: "active", stripe_customer_id: "cus_port_1")
      allow(Stripe::BillingPortal::Session).to receive(:create)
        .and_return(Stripe::BillingPortal::Session.construct_from(url: "https://billing.stripe.com/p"))
      login_as!(guardian)
    end

    it "tells them plainly that it buys nothing and to cancel it" do
      get my_billing_path

      expect(response.body).to include("no longer gives you anything")
      expect(response.body).to include("Cancel this subscription")
    end

    it "still sends them to Stripe's portal, which is how they cancel" do
      post my_billing_portal_path

      expect(response).to redirect_to("https://billing.stripe.com/p")
    end
  end
end
