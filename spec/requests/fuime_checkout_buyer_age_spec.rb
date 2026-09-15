# frozen_string_literal: true

require "rails_helper"

# Fuime: anyone may buy — guest, adult, teen, or unknown age.
#
# This file used to assert the opposite. The adult-only buyer rule was removed
# on 2026-09-15 (Fuime::CheckoutsController#refuse_minor_buyer carries the
# reasoning): it was bypassable by its own instructions ("Sign out to pay as a
# guest"), it blocked teen-to-teen sales, and because `User#is_minor?` is nil
# without a birthday it refused every signed-in account that had never attested
# an age. The examples are inverted rather than deleted so the change is legible
# and so a future re-tightening has to argue with them.
#
# Storefront pay (`POST /b/:slug/pay`) and the hosted pay-link form both create
# the session through Fuime::CheckoutsController. What this file still guards is
# the invariant that did NOT change: **price comes off the offer record, never
# the POST body.**
RSpec.describe "checkout buyer age", type: :request do
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

  let(:event) { create(:event, slug: "mayas-prints", is_public: true) }
  let!(:connected_account) { create(:stripe_connected_account, :ready, event:) }
  let(:offer) { create(:fuime_offer, event:, price_cents: 35_00, name: "Front and back lawn mow") }
  let(:stripe_session) { double("Stripe::Checkout::Session", url: "https://checkout.stripe.com/c/pay/cs_test_buyer") }
  let(:payment_link) do
    instance_double(Fuime::PaymentLinkService, create_checkout_session: stripe_session)
  end

  before do
    allow_any_instance_of(::Event).to receive(:accepts_payments?).and_return(true)
    allow(Fuime::PaymentLinkService).to receive(:new).and_return(payment_link)
    offer.publish!
  end

  def pay_storefront!(params = {})
    post fuime_storefront_pay_path(slug: event.slug), params: { amount: "25.00" }.merge(params)
  end

  def pay_offer!(params = {})
    post fuime_storefront_pay_path(slug: event.slug),
         params: { offer_token: offer.to_param }.merge(params)
  end

  describe "a guest (no session)" do
    it "still starts checkout from the storefront" do
      pay_storefront!

      expect(Fuime::PaymentLinkService).to have_received(:new).with(
        hash_including(event:, amount_cents: 2500)
      )
      expect(response).to redirect_to("https://checkout.stripe.com/c/pay/cs_test_buyer")
    end

    # The pay-link form posts offer_token to the same action. The price is
    # the operator's, read off the record.
    it "still starts checkout from a pay link at the offer's price" do
      pay_offer!

      expect(Fuime::PaymentLinkService).to have_received(:new).with(
        hash_including(event:, amount_cents: 35_00, description: offer.payment_description)
      )
      expect(response).to redirect_to("https://checkout.stripe.com/c/pay/cs_test_buyer")
    end
  end

  describe "a signed-in adult" do
    let(:adult) { create(:user, birthday: 40.years.ago.to_date, verified: true) }

    before { login_as!(adult) }

    it "starts checkout from the storefront" do
      pay_storefront!

      expect(Fuime::PaymentLinkService).to have_received(:new)
      expect(response).to redirect_to("https://checkout.stripe.com/c/pay/cs_test_buyer")
    end

    it "starts checkout from a pay link" do
      pay_offer!

      expect(Fuime::PaymentLinkService).to have_received(:new).with(
        hash_including(amount_cents: 35_00)
      )
      expect(response).to redirect_to("https://checkout.stripe.com/c/pay/cs_test_buyer")
    end
  end

  describe "a signed-in teen" do
    # With a guardian so they are a real operator, not a parked account —
    # operating a business does not make them an adult buyer.
    let(:teen) { create(:user, :minor_with_guardian, verified: true) }

    before { login_as!(teen) }

    it "starts checkout from the storefront" do
      pay_storefront!

      expect(Fuime::PaymentLinkService).to have_received(:new)
      expect(response).to redirect_to("https://checkout.stripe.com/c/pay/cs_test_buyer")
    end

    # Teen-to-teen is the case the old rule cost most: one teenager buying from
    # another's storefront is the product working, not an edge case.
    it "starts a pay-link checkout at the operator's price, not a posted one" do
      pay_offer!(amount: "1.00")

      expect(Fuime::PaymentLinkService).to have_received(:new).with(
        hash_including(amount_cents: 35_00)
      )
      expect(response).to redirect_to("https://checkout.stripe.com/c/pay/cs_test_buyer")
    end
  end

  describe "a signed-in user whose age is unknown" do
    let(:unknown) { create(:user, :unknown_age, verified: true) }

    before { login_as!(unknown) }

    # The common case, and the one the old rule got most wrong: `User#is_minor?`
    # is `age&.<(18)`, nil with no birthday on record, so fail-closed age refused
    # adults who had simply never told Fuime when they were born.
    it "may start checkout" do
      pay_storefront!

      expect(Fuime::PaymentLinkService).to have_received(:new)
      expect(response).to redirect_to("https://checkout.stripe.com/c/pay/cs_test_buyer")
    end
  end

  # Kept after the rule's removal: staff could always check out, and asserting it
  # still holds means a re-tightening cannot quietly lock the console's own
  # operators out of a public checkout again.
  describe "signed-in staff" do
    let(:admin) { create(:user, :make_admin, :unknown_age, verified: true) }

    before { login_as!(admin) }

    it "may start checkout" do
      pay_storefront!

      expect(Fuime::PaymentLinkService).to have_received(:new)
      expect(response).to redirect_to("https://checkout.stripe.com/c/pay/cs_test_buyer")
    end
  end
end
