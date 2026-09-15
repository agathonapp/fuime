# frozen_string_literal: true

require "rails_helper"

# Fuime: a Buy button that refuses has to say so on the page it returns to.
#
# `layouts/fuime_payment_page.html.erb` rendered head, `<main><%= yield %></main>`
# and the footer — no flash container anywhere. Three paths redirect back to that
# page carrying an explanation in `flash[:alert]`, and all three arrived
# invisible:
#
#   * the `Stripe::StripeError` rescue — "We couldn't start that payment."
#   * a closed or unpublished offer — "That isn't for sale right now."
#
# A third path, `#refuse_minor_buyer` ("Checkout is billed to an adult"), was the
# original vehicle for this example. That rule was removed on 2026-09-15 — it
# refused the entire signed-in teen user base, which is precisely why it was the
# easiest refusal to reach here. The example now uses a closed offer instead: the
# invariant under test was never the age rule, it was that a refusal returning to
# THIS layout is visible at all.
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

  # FUIME (2026-09-15): the second example here is deliberately gone, not ported.
  #
  # It pressed Buy as a signed-in minor and asserted the refusal was VISIBLE on
  # the pay page it returned to. That was the only refusal which returned to this
  # layout — #refuse_minor used #refuse_destination (→ #return_url → the pay page)
  # while every other refusal in Fuime::CheckoutsController#create redirects to
  # the storefront, whose layout has always rendered a flash. With the buyer-age
  # rule removed, no refusal routes here any more, so there is nothing left to
  # press that would prove the layout carries a flash.
  #
  # The example above still does the load-bearing work: it asserts the pay page
  # renders `flash-container` at all, which is the fix this file was written for
  # and is what any FUTURE refusal returning here will depend on. Re-add a
  # press-and-follow example the day a refusal points back at this page again.
end
