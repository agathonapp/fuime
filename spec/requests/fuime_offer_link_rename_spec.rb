# frozen_string_literal: true

require "rails_helper"

# Fuime: renaming a payment link has to be possible.
#
# ── The bug this file exists for ───────────────────────────────────────────
#
# `Fuime::OffersController#offer_params` merged `price_cents: price_cents_param`
# unconditionally. `price_cents_param` reads `params[:fuime_offer][:price]` and
# returns nil when there isn't one — deliberately, so an unparseable price gets
# the model's own message rather than "must be greater than 0".
#
# The "Change this link" form on the offers page submits the slug and nothing
# else. So every save wrote nil over a real price, failed validation, and told
# the operator their price "has to be an amount you've decided on" — a complaint
# about a field they were not editing and could not see on that form. The one
# affordance for tidying up the URL a founder pastes into an Instagram bio could
# never succeed.
#
# Absent and blank stay different: a submitted-but-empty price is still an
# attempt to set one and must reach the model.
RSpec.describe "renaming an offer's payment link", type: :request do
  def login_as!(user)
    post logins_path, params: { email: user.email, login: { purpose: "" } }
    login = Login.order(:id).last
    post email_login_path(login)
    code = LoginCode.active.where(user:).order(:id).last
    post complete_login_path(login), params: { method: "email", login_code: code.code }
    expect(User::Session.where(user:)).to exist, "login failed for #{user.email}"
  end

  let(:teen) { create(:user, :minor, birthday: 16.years.ago.to_date, verified: true) }
  let(:guardian) { create(:user, birthday: 40.years.ago.to_date, verified: true) }

  let(:event) do
    create(:event, business_category: "services", is_public: true, name: "Sunset Lawn Care").tap do |e|
      e.update!(operator_vetting_status: :approved, operator_vetted_at: Time.current)
      create(:organizer_position, event: e, user: teen)
    end
  end

  let!(:offer) { create(:fuime_offer, event:, name: "Front and back", price_cents: 3_500) }

  before do
    # With merchant-of-record off (the suite default) a minor cannot operate a
    # venture without an accepted guardian, and every write is refused with that
    # message instead of the one under test.
    create(:guardianship, :active, guardian:, minor: teen)
    login_as!(teen)
  end

  it "saves the new link and leaves the price alone" do
    patch fuime_offer_path(event_slug: event.slug, id: offer.id),
          params: { fuime_offer: { slug: "front-and-back" } }

    expect(offer.reload.slug).to eq("front-and-back")
    expect(offer.price_cents).to eq(3_500)
    expect(flash[:alert]).to be_blank
  end

  it "still updates a price when the form carries one" do
    patch fuime_offer_path(event_slug: event.slug, id: offer.id),
          params: { fuime_offer: { price: "42.50" } }

    expect(offer.reload.price_cents).to eq(4_250)
  end

  # Blank is not absent. Someone who cleared the price box is trying to set one,
  # and must get the message on the field they are looking at.
  it "still refuses a price that was submitted empty" do
    patch fuime_offer_path(event_slug: event.slug, id: offer.id),
          params: { fuime_offer: { price: "" } }

    expect(offer.reload.price_cents).to eq(3_500)
    expect(flash[:alert]).to be_present
  end
end
