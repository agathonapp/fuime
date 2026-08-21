# frozen_string_literal: true

require "rails_helper"

# Fuime: a signed-in minor must not open a Stripe Checkout session.
#
# Storefront pay (`POST /b/:slug/pay`) and the hosted pay-link form both
# create the session through Fuime::CheckoutsController. Guests (no
# session) still check out — the link a teen texts to a customer they
# know has to work without a Fuime account. Price still comes off the
# offer record, never the POST body.
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

    it "refuses storefront pay and does not open a Stripe session" do
      pay_storefront!

      expect(Fuime::PaymentLinkService).not_to have_received(:new)
      expect(response).to redirect_to(fuime_storefront_path(slug: event.slug))
      expect(flash[:alert]).to match(/adult/i)
    end

    it "refuses a pay-link checkout and does not open a Stripe session" do
      pay_offer!

      expect(Fuime::PaymentLinkService).not_to have_received(:new)
      expect(response).to redirect_to(fuime_payment_page_path(event_slug: event.slug, offer: offer.to_param))
      expect(flash[:alert]).to match(/adult/i)
    end
  end

  describe "a signed-in user whose age is unknown" do
    let(:unknown) { create(:user, :unknown_age, verified: true) }

    before { login_as!(unknown) }

    it "is treated as a minor and refused" do
      pay_storefront!

      expect(Fuime::PaymentLinkService).not_to have_received(:new)
      expect(flash[:alert]).to match(/adult/i)
    end
  end

  # Same exemption as BillingController#adult?: staff accounts have no
  # birthday, and fail-closed age would otherwise lock the console's own
  # operators out of a public checkout.
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
