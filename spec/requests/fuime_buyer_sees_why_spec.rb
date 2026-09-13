# frozen_string_literal: true

require "rails_helper"

# Fuime: a Buy button that refuses has to say so on the page it returns to.
#
# `layouts/fuime_payment_page.html.erb` rendered head, `<main><%= yield %></main>`
# and the footer — no flash container anywhere. Three paths redirect back to that
# page carrying an explanation in `flash[:alert]`, and all three arrived
# invisible:
#
#   * `#refuse_minor_buyer` — "Checkout is billed to an adult." Signup collects
#     no date of birth, so `User#known_adult?` is false for the entire teen user
#     base, and the first person to meet this refusal is the operator testing
#     their own payment link.
#   * the `Stripe::StripeError` rescue — "We couldn't start that payment."
#   * a closed or unpublished offer.
#
# What the buyer saw was the page reloading unchanged. The teenager hears about
# that as a sale that did not happen, with no reason attached.
# `:merchant_of_record` at the top: `Fuime::Offer#publish!` refuses while the
# venture cannot take payments, and under Connect a venture with no connected
# account never can — so without the tag the offer stays a draft and the pay page
# 404s for a reason that has nothing to do with this file.
RSpec.describe "what a buyer is told when checkout refuses", :merchant_of_record, type: :request do
  let(:event) do
    create(:event, name: "Nova Dog Walking", business_category: "services", is_public: true)
  end

  let!(:offer) do
    create(:fuime_offer, :published, event:, name: "One walk", price_cents: 3_500)
  end

  let(:teen) { create(:user, :attested_teen, full_name: "Ira Buyer") }

  def sign_in_as!(user)
    post logins_path, params: { email: user.email, login: { purpose: "" } }
    login = Login.order(:id).last
    post email_login_path(login)
    code = LoginCode.active.where(user:).order(:id).last
    post complete_login_path(login), params: { method: "email", login_code: code.code }
    expect(User::Session.where(user:)).to exist, "login failed for #{user.email}"
  end

  describe "the payment page layout" do
    it "renders a flash container at all" do
      get fuime_payment_page_path(event_slug: event.slug, offer: offer.to_param)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("flash-container")
    end
  end

  describe "a signed-in minor pressing Buy" do
    before { sign_in_as!(teen) }

    it "is told why, on the page it sends them back to" do
      # `offer_token` is the parameter the pay page's form posts
      # (fuime/payment_pages/show.html.erb:69); `offer` is the URL segment on the
      # GET. Getting it wrong here would silently exercise the storefront
      # redirect instead.
      post fuime_storefront_pay_path(slug: event.slug), params: { offer_token: offer.to_param }

      expect(response).to be_redirect
      expect(flash[:alert]).to include("billed to an adult")

      # Asserted explicitly: the refusal sends them back to the PAY page when an
      # offer was named (Fuime::CheckoutsController#return_url), which is the
      # layout that rendered no flash. Without this the example would still pass
      # if the redirect fell through to the storefront, whose layout has always
      # rendered one — and would then prove nothing about the fix.
      expect(response.headers["Location"])
        .to eq(fuime_payment_page_url(event_slug: event.slug, offer: offer.to_param))

      follow_redirect!

      expect(response.body).to include("flash-container")
      expect(response.body).to include("billed to an adult")
    end
  end
end
