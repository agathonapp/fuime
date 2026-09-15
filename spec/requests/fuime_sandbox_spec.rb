# frozen_string_literal: true

require "rails_helper"

# Fuime: Sandbox Mode — a founder rehearsing a sale on their own storefront.
#
# The interesting assertions here are the negative ones. A test purchase must
# not reach Stripe, must not reach the ledger, and must not move the balance a
# family is shown or the amount a payout is computed from. Those are the
# properties the feature is worth having only if it keeps.
#
# The other half is the diversion rule: Sandbox Mode changes what the OPERATOR's
# Buy click does and nothing about a customer's. That is what makes the flag
# safe to leave switched on, which is the only reason it is safe to ship to
# teenagers at all.
# Composed below so the "writes nothing anywhere" expectation reads as one
# statement rather than five, and fails naming the table that moved.
RSpec::Matchers.define_negated_matcher :not_change, :change

RSpec.describe "Sandbox Mode", :merchant_of_record, type: :request do
  def sign_in(user)
    post logins_path, params: { email: user.email, login: { purpose: "" } }
    login = Login.order(:id).last
    post email_login_path(login)
    code = LoginCode.active.where(user:).order(:id).last
    post complete_login_path(login), params: { method: "email", login_code: code.code }
    expect(User::Session.where(user:)).to exist, "login failed for #{user.email}"
  end

  let(:founder) { create(:user) }
  # `business_category` matters: Fuime::Offer's `only_a_selling_venture_may_publish`
  # requires `accepts_payments?`, and the `:published` trait fails SILENTLY without
  # it (AASM's bang method returns false rather than raising), leaving a draft
  # offer that `find_public` correctly refuses to sell.
  let(:event) do
    create(:event, organizers: [founder], is_public: true, sandbox_mode: true,
                   business_category: "services")
  end
  let!(:offer) { create(:fuime_offer, :published, event:, price_cents: 35_00) }

  describe "turning it on and off" do
    it "starts off" do
      expect(create(:event).sandbox_mode).to be(false)
    end

    it "lets the operator switch it on and back off" do
      event.update_column(:sandbox_mode, false)
      sign_in(founder)

      post fuime_sandbox_enable_path(event_slug: event.slug)
      expect(event.reload.sandbox_mode).to be(true)

      post fuime_sandbox_disable_path(event_slug: event.slug)
      expect(event.reload.sandbox_mode).to be(false)
    end

    it "refuses a stranger" do
      sign_in(create(:user))

      post fuime_sandbox_enable_path(event_slug: event.slug)

      expect(event.reload.sandbox_mode).to be(true) # unchanged; it started on
      expect(response).not_to have_http_status(:ok)
    end
  end

  # A rehearsal is a REAL Stripe Checkout Session created with the test-mode key.
  # The session creation is stubbed here (the suite must not call Stripe), but
  # what is asserted is that the sandbox path asks for a test-mode session and
  # sends the founder to Stripe's own page.
  describe "starting a rehearsal" do
    let(:stripe_session) { double("Stripe::Checkout::Session", url: "https://checkout.stripe.com/c/pay/cs_test_x") }
    let(:payment_link) { instance_double(Fuime::PaymentLinkService, create_checkout_session: stripe_session) }

    before do
      sign_in(founder)
      allow(Fuime::PaymentLinkService).to receive(:new).and_return(payment_link)
    end

    it "sends the founder to Stripe's real checkout, in sandbox mode" do
      post fuime_storefront_pay_path(slug: event.slug), params: { offer_token: offer.to_param }

      expect(Fuime::PaymentLinkService).to have_received(:new)
        .with(hash_including(sandbox: true, amount_cents: 35_00))
      expect(response).to redirect_to(stripe_session.url)
    end

    # Stripe substitutes the real id into this template on redirect. Without it
    # the return leg has nothing to ask Stripe about, and the rehearsal silently
    # never records.
    it "asks Stripe to hand the session id back" do
      post fuime_storefront_pay_path(slug: event.slug), params: { offer_token: offer.to_param }

      expect(payment_link).to have_received(:create_checkout_session)
        .with(hash_including(success_url: a_string_including("sandbox_session={CHECKOUT_SESSION_ID}")))
    end

    it "writes nothing until Stripe says the rehearsal was paid" do
      expect {
        post fuime_storefront_pay_path(slug: event.slug), params: { offer_token: offer.to_param }
      }.not_to change(Fuime::TestSale, :count)
    end

    it "accepts the free-amount path" do
      post fuime_storefront_pay_path(slug: event.slug), params: { amount: "12.50" }

      expect(Fuime::PaymentLinkService).to have_received(:new).with(hash_including(amount_cents: 12_50))
    end

    it "refuses an amount outside the real checkout's bounds" do
      post fuime_storefront_pay_path(slug: event.slug), params: { amount: "0.50" }

      expect(Fuime::PaymentLinkService).not_to have_received(:new)
    end

    # A minor operator is the person this feature was built for. The
    # refuse-minor-buyer rule exists to stop a minor being CHARGED, and a
    # test-mode session charges nobody.
    it "lets a teenage operator rehearse" do
      teen = create(:user, birthday: 16.years.ago)
      teen_event = create(:event, organizers: [teen], is_public: true, sandbox_mode: true,
                                  business_category: "services")
      sign_in(teen)

      post fuime_storefront_pay_path(slug: teen_event.slug), params: { amount: "20" }

      expect(Fuime::PaymentLinkService).to have_received(:new).with(hash_including(sandbox: true))
    end
  end

  # The return leg: Stripe sends the founder back with a session id and we ask
  # Stripe what actually happened.
  describe "coming back from Stripe" do
    let(:session_id) { "cs_test_returnleg" }

    def stripe_session(livemode: false, payment_status: "paid", event_id: nil, amount: 35_00)
      double(
        "Stripe::Checkout::Session",
        livemode:,
        payment_status:,
        amount_total: amount,
        metadata: {
          "fuime_event_id" => (event_id || event.id).to_s,
          "fuime_offer_name" => "Front and back lawn mow"
        }
      )
    end

    before { sign_in(founder) }

    it "records the rehearsal Stripe confirms" do
      allow(Stripe::Checkout::Session).to receive(:retrieve).and_return(stripe_session)

      expect {
        get fuime_storefront_path(slug: event.slug), params: { paid: 1, sandbox_session: session_id }
      }.to change(Fuime::TestSale, :count).by(1)

      expect(Fuime::TestSale.last.stripe_checkout_session_id).to eq(session_id)
      expect(Fuime::TestSale.last.amount_cents).to eq(35_00)
    end

    # The load-bearing gate, and the reason real Stripe test mode is SAFER than
    # the mock this replaced: `livemode` is the processor's own assertion that no
    # money moved. A live session must never be recordable as a rehearsal.
    it "refuses a live-mode session" do
      allow(Stripe::Checkout::Session).to receive(:retrieve).and_return(stripe_session(livemode: true))

      expect {
        get fuime_storefront_path(slug: event.slug), params: { paid: 1, sandbox_session: session_id }
      }.not_to change(Fuime::TestSale, :count)
    end

    it "refuses a session that was never paid" do
      allow(Stripe::Checkout::Session).to receive(:retrieve).and_return(stripe_session(payment_status: "unpaid"))

      expect {
        get fuime_storefront_path(slug: event.slug), params: { paid: 1, sandbox_session: session_id }
      }.not_to change(Fuime::TestSale, :count)
    end

    # Without this, a session id from one venture's rehearsal could be replayed
    # against another venture's page.
    it "refuses a session belonging to another venture" do
      allow(Stripe::Checkout::Session).to receive(:retrieve).and_return(stripe_session(event_id: 999_999))

      expect {
        get fuime_storefront_path(slug: event.slug), params: { paid: 1, sandbox_session: session_id }
      }.not_to change(Fuime::TestSale, :count)
    end

    it "records a session only once, however many times the page is reloaded" do
      allow(Stripe::Checkout::Session).to receive(:retrieve).and_return(stripe_session)

      expect {
        3.times { get fuime_storefront_path(slug: event.slug), params: { paid: 1, sandbox_session: session_id } }
      }.to change(Fuime::TestSale, :count).by(1)
    end

    # The whole point. If this ever fails, the feature is worse than not having
    # shipped it: a teenager would be shown money they do not have.
    it "does not move the ledger, the sales record or the fees" do
      allow(Stripe::Checkout::Session).to receive(:retrieve).and_return(stripe_session)

      expect {
        get fuime_storefront_path(slug: event.slug), params: { paid: 1, sandbox_session: session_id }
      }.to not_change(CanonicalTransaction, :count)
        .and not_change(CanonicalPendingTransaction, :count)
        .and not_change(CanonicalEventMapping, :count)
        .and not_change(Fuime::Sale, :count)
        .and not_change(Fee, :count)
    end

    # Stated separately from the ledger tables above so a failure names the
    # balance directly — it is the number a teenager actually reads.
    it "does not move the balance" do
      allow(Stripe::Checkout::Session).to receive(:retrieve).and_return(stripe_session)

      expect {
        get fuime_storefront_path(slug: event.slug), params: { paid: 1, sandbox_session: session_id }
      }.not_to(change { event.reload.balance_v2_cents })
    end

    # A stranger who gets hold of a session id cannot mint rehearsals on someone
    # else's venture: the return leg runs only for the operator.
    it "ignores a session id presented by someone who is not the operator" do
      allow(Stripe::Checkout::Session).to receive(:retrieve).and_return(stripe_session)
      reset! # drop the signed-in session established in `before`

      expect {
        get fuime_storefront_path(slug: event.slug), params: { paid: 1, sandbox_session: session_id }
      }.not_to change(Fuime::TestSale, :count)
    end

    # A Stripe hiccup on the way back from a successful test payment must not
    # put a founder on an error page.
    it "degrades quietly when Stripe cannot be reached" do
      allow(Stripe::Checkout::Session).to receive(:retrieve).and_raise(Stripe::APIError.new("boom"))

      get fuime_storefront_path(slug: event.slug), params: { paid: 1, sandbox_session: session_id }

      expect(response).to have_http_status(:ok)
      expect(Fuime::TestSale.count).to eq(0)
    end
  end

  # The property that makes leaving Sandbox Mode on harmless, asserted from both
  # sides: the customer writes no rehearsal AND reaches the real Stripe path. If
  # only the first were checked, a bug that dropped the click on the floor would
  # pass while every founder who forgot to switch Sandbox Mode off silently lost
  # every sale.
  describe "a customer" do
    let(:stripe_session) { double("Stripe::Checkout::Session", url: "https://checkout.stripe.com/c/pay/cs_test") }
    let(:payment_link) { instance_double(Fuime::PaymentLinkService, create_checkout_session: stripe_session) }

    before { allow(Fuime::PaymentLinkService).to receive(:new).and_return(payment_link) }

    it "is never diverted into a rehearsal" do
      expect {
        post fuime_storefront_pay_path(slug: event.slug), params: { amount: "20" }
      }.not_to change(Fuime::TestSale, :count)

      expect(Fuime::PaymentLinkService).to have_received(:new)
      expect(response).to redirect_to(stripe_session.url)
    end

    it "is not diverted even when signed in as an operator of a different venture" do
      other_founder = create(:user, birthday: 30.years.ago)
      create(:event, organizers: [other_founder], business_category: "services", sandbox_mode: true)
      sign_in(other_founder)

      expect {
        post fuime_storefront_pay_path(slug: event.slug), params: { amount: "20" }
      }.not_to change(Fuime::TestSale, :count)

      expect(Fuime::PaymentLinkService).to have_received(:new)
    end
  end

  describe "the page" do
    it "shows the operator their rehearsals" do
      sign_in(founder)
      create(:fuime_test_sale, event:, user: founder, description: "Front and back lawn mow")

      get fuime_sandbox_path(event_slug: event.slug)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Front and back lawn mow")
      # The sentence that stops the list reading as income.
      expect(response.body).to match(/not on your ledger/i)
    end

    it "clears them" do
      sign_in(founder)
      create(:fuime_test_sale, event:, user: founder)

      expect {
        delete fuime_sandbox_clear_path(event_slug: event.slug)
      }.to change { event.fuime_test_sales.count }.to(0)
    end
  end

  describe "the storefront" do
    it "warns the operator, and only the operator, that Buy is a rehearsal" do
      sign_in(founder)
      get fuime_storefront_path(slug: event.slug)
      expect(response.body).to match(/this is a rehearsal/i)
    end

    it "says nothing to a customer" do
      get fuime_storefront_path(slug: event.slug)
      expect(response.body).not_to match(/this is a rehearsal/i)
    end
  end
end
