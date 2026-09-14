# frozen_string_literal: true

require "rails_helper"

# Fuime: the sales page renders, is authorised like the ledger, and is honest
# about what its numbers are not.
RSpec.describe "sales dashboard", :merchant_of_record, type: :request do
  # The real login dance, as the other Fuime request specs do it — the
  # SessionSupport factory shortcut trips over 2FA state here.
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

  def sell(cents, offer: nil, at: Time.current)
    Fuime::Sale.create!(
      stripe_payment_intent_id: "pi_#{SecureRandom.hex(6)}",
      event:, amount_cents: cents, occurred_at: at,
      fuime_offer_id: offer&.id, country: "US", state: "CA"
    )
  end

  it "tells a founder with no sales what will appear here" do
    sign_in(founder)

    get fuime_sales_path(event_slug: event.slug)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("No sales yet")
    expect(response.body).not_to include("Average sale")
  end

  it "shows revenue, count and average once there are sales" do
    sell(25_00)
    sell(75_00)
    sign_in(founder)

    get fuime_sales_path(event_slug: event.slug)

    expect(response.body).to include("Average sale")
    expect(response.body).to include("$100.00") # revenue
    expect(response.body).to include("$50.00")  # average
  end

  it "names what sells best" do
    offer = create(:fuime_offer, event:, name: "Lawn mow", price_cents: 35_00)
    2.times { sell(35_00, offer:) }
    sign_in(founder)

    get fuime_sales_path(event_slug: event.slug)

    expect(response.body).to include("Lawn mow")
    expect(response.body).to include("2 sales")
  end

  # A number a founder cannot reconcile against their payout is worse than no
  # number, so the disclaimers ride along with the figures.
  it "says on the page that refunds are not subtracted and this is not the payout" do
    sell(10_00)
    sign_in(founder)

    get fuime_sales_path(event_slug: event.slug)

    expect(response.body).to match(/refund/i)
    expect(response.body).to match(/payouts page/i)
  end

  # A founder cannot deliver what they sold without knowing who bought it, and
  # cannot get repeat business without knowing who came back.
  describe "customers" do
    def buy(cents, email:, name: nil)
      customer = Fuime::Customer.record!(event:, email:, name:)
      Fuime::Sale.create!(stripe_payment_intent_id: "pi_#{SecureRandom.hex(6)}",
                          event:, amount_cents: cents, occurred_at: Time.current,
                          fuime_customer_id: customer.id, country: "US", state: "CA")
    end

    it "names them, with how to reach them" do
      buy(40_00, email: "ada@example.com", name: "Ada Lovelace")
      sign_in(founder)

      get fuime_sales_path(event_slug: event.slug)

      expect(response.body).to include("Ada Lovelace")
      expect(response.body).to include("ada@example.com")
    end

    it "says who came back" do
      buy(10_00, email: "ada@example.com")
      buy(15_00, email: "ada@example.com")
      buy(20_00, email: "grace@example.com")
      sign_in(founder)

      get fuime_sales_path(event_slug: event.slug)

      expect(response.body).to include("2") # customers
      expect(response.body).to match(/came back/)
      expect(response.body).to match(/bought 2 times/)
    end

    it "shows no customer section before anyone has bought" do
      sell(10_00)
      sign_in(founder)

      get fuime_sales_path(event_slug: event.slug)

      expect(response.body).not_to include("Your customers")
    end
  end

  it "refuses a stranger, the same as the ledger does" do
    sell(10_00)
    sign_in(stranger)

    get fuime_sales_path(event_slug: event.slug)

    expect(response).not_to have_http_status(:ok)
  end

  it "falls back to a sane interval rather than trusting the query string" do
    sell(10_00)
    sign_in(founder)

    get fuime_sales_path(event_slug: event.slug, interval: "fortnight'); DROP TABLE--")

    expect(response).to have_http_status(:ok)
  end
end
