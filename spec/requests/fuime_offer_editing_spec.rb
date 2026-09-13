# frozen_string_literal: true

require "rails_helper"

# Fuime: changing the price of something you already sell.
#
# ── What a founder could not do ─────────────────────────────────────────────
#
# Nothing. There was no edit route and no price form for a persisted offer — the
# only PATCH on the offers page submitted the slug — so the only way to change a
# price was archive-and-recreate. That burns the URL: `assign_slug` dedupes
# against archived rows, so the new offer cannot reuse the old slug, and the pay
# page scopes to published, so the old one 404s. Every flyer, QR code, bio link
# and repeat customer's bookmark breaks.
#
# For a teenager already running a business — which is half of who Fuime is for —
# that is a choice between charging the right price and keeping the customers
# they have. Prices move: materials, seasons, and getting better at the work.
#
# The controller was always ready for this. `offer_params` permits name,
# description and unit_label, and merges `price_cents` whenever the form carries
# a price. Only the form was missing.
#
# ── And what the price box did with a comma ─────────────────────────────────
#
# `price_cents_param` stripped every character outside `[0-9.]`, so "35,50"
# became "3550" and then $3,550 — a hundredfold error, silent, on the one field
# the product repeatedly promises Fuime will never influence.
RSpec.describe "editing something you already sell", :merchant_of_record, type: :request do
  # A date of birth, not the 13+ attestation: the operator floor is 16 and
  # `Fuime::OperatorEligibility` cannot clear an unknown age, so an attested-only
  # founder blocks the venture from selling and `Fuime::Offer#publish!` then
  # refuses — which would make every example here fail for an unrelated reason.
  let(:founder) { create(:user, :minor, birthday: 16.years.ago.to_date, full_name: "Rae Editor") }

  let(:event) do
    create(:event, name: "Rae Lawn Care", business_category: "services", is_public: true).tap do |e|
      create(:organizer_position, user: founder, event: e, role: :manager)
    end
  end

  let!(:offer) do
    create(:fuime_offer, :published, event:, name: "Front and back mow",
                                     price_cents: 35_00, slug: "mow")
  end

  def sign_in_as!(user)
    post logins_path, params: { email: user.email, login: { purpose: "" } }
    login = Login.order(:id).last
    post email_login_path(login)
    code = LoginCode.active.where(user:).order(:id).last
    post complete_login_path(login), params: { method: "email", login_code: code.code }
    expect(User::Session.where(user:)).to exist, "login failed for #{user.email}"
  end

  before { sign_in_as!(founder) }

  def patch_offer(params)
    patch fuime_offer_path(event_slug: event.slug, id: offer.id),
          params: { fuime_offer: params }
  end

  describe "the offers page" do
    it "offers a way to change the price at all" do
      get fuime_offers_path(event_slug: event.slug)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("fuime_offer[price]")
    end
  end

  describe "changing the price" do
    it "saves the new price" do
      patch_offer(price: "45")

      expect(offer.reload.price_cents).to eq(45_00)
    end

    # The reason the whole thing matters: the link a customer already has has to
    # survive, or the founder is back to archive-and-recreate.
    it "leaves the pay link untouched, so what customers already have still works" do
      patch_offer(price: "45")

      expect(offer.reload.slug).to eq("mow")
      expect(offer).to be_published

      get fuime_payment_page_path(event_slug: event.slug, offer: "mow")

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("45")
    end

    it "changes the name and the unit alongside it" do
      patch_offer(name: "Front, back and edging", price: "60", unit_label: "per visit")

      offer.reload
      expect(offer.name).to eq("Front, back and edging")
      expect(offer.price_cents).to eq(60_00)
      expect(offer.unit_label).to eq("per visit")
    end

    # The form submits a price on every save, so a rename must not be able to
    # reprice. This is the inverse of the bug fixed in b4352af15, where a rename
    # form that carried no price could never save at all.
    it "does not disturb the price when the form carries the same one" do
      patch_offer(name: "Front and back mow (spring)", price: "35.00")

      expect(offer.reload.price_cents).to eq(35_00)
    end
  end

  describe "what a person can type in the price box" do
    {
      "35"       => 35_00,
      "35.00"    => 35_00,
      "$35"      => 35_00,
      "$35.50"   => 35_50,
      "1,250.50" => 1_250_50,  # US grouping, US decimal
      "1.250,50" => 1_250_50,  # EU grouping, EU decimal
      "35,50"    => 35_50,     # EU decimal, or a US typo — either way, not $3,550
      "1,250"    => 1_250_00,  # grouping, not a decimal: three digits follow
      " 42 "     => 42_00,
      ".50"      => 50
    }.each do |typed, expected_cents|
      it "reads #{typed.inspect} as #{ActiveSupport::NumberHelper.number_to_currency(expected_cents / 100.0)}" do
        patch_offer(price: typed)

        expect(offer.reload.price_cents).to eq(expected_cents)
      end
    end

    # The specific hundredfold error, stated as itself so a regression is
    # recognisable rather than just a red dot.
    it "never multiplies a comma-decimal price by a hundred" do
      patch_offer(price: "35,50")

      expect(offer.reload.price_cents).not_to eq(3_550_00)
      expect(offer.price_cents).to eq(35_50)
    end

    it "refuses what it cannot read, rather than guessing at zero" do
      patch_offer(price: "about thirty five")

      expect(offer.reload.price_cents).to eq(35_00)
      expect(flash[:alert]).to be_present
    end
  end

  describe "somebody else's offer" do
    let(:stranger) { create(:user, :minor, birthday: 16.years.ago.to_date, full_name: "Not Rae") }

    it "cannot be edited" do
      sign_in_as!(stranger)

      patch_offer(price: "1")

      expect(offer.reload.price_cents).to eq(35_00)
    end
  end
end
