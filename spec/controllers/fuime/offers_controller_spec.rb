# frozen_string_literal: true

require "rails_helper"

# Fuime: the operator's own shop page.
#
# Two things are being protected. One is the authorization split — the operator
# prices their work and the guardian does not, which is the opposite of the
# payout screen and deliberately so. The other is that **nothing on this page
# suggests a price**, which is a §8.3 D2 constraint and will be under permanent
# pressure from anybody trying to be helpful.
RSpec.describe Fuime::OffersController, type: :controller do
  include SessionSupport
  render_views

  let(:teen) { create(:user, birthday: 16.years.ago.to_date, verified: true) }
  let(:guardian) { create(:user, birthday: 40.years.ago.to_date, verified: true) }
  let(:event) { create(:event) }

  before do
    create(:organizer_position, event:, user: teen)
    create(:guardianship, :active, guardian:, minor: teen)
  end

  describe "who may price the work" do
    it "lets the operator add an offer" do
      create_session(teen, verified: true)

      post :create, params: { event_slug: event.slug,
                              fuime_offer: { name: "Lawn mow", price: "35" }
}

      expect(event.fuime_offers.count).to eq(1)
      expect(event.fuime_offers.first.price_cents).to eq(35_00)
    end

    # The contrast with payouts is the design. A guardian decides money leaving,
    # because they own the account and the funds (L2). A guardian does not decide
    # what their kid's work is worth — §8.3 D2's mitigation is that the OPERATOR
    # controls their own pricing, and a third party setting the rate is a third
    # party whether that party is Fuime or a parent.
    it "does not let the guardian set a price" do
      create_session(guardian, verified: true)

      post :create, params: { event_slug: event.slug,
                              fuime_offer: { name: "Lawn mow", price: "35" }
}

      expect(event.fuime_offers.count).to eq(0)
    end

    it "still lets the guardian see everything" do
      create(:fuime_offer, event:, name: "Lawn mow")
      create_session(guardian, verified: true)

      get :index, params: { event_slug: event.slug }

      expect(response).to have_http_status(:ok)
      expect(CGI.unescapeHTML(response.body)).to include("Lawn mow")
    end
  end

  describe "the page never suggests a price" do
    before { create_session(teen, verified: true) }

    suggestion = /most people charge|typical(ly)? charge|average (price|rate)|suggested (price|rate)|we recommend charging/i

    it "puts no number in the price field" do
      get :new, params: { event_slug: event.slug, step: "price" }

      body = CGI.unescapeHTML(response.body)
      price_field = body[/<input[^>]*fuime_offer\[price\][^>]*>/]

      expect(price_field).to be_present, "the price field should render"
      expect(price_field).not_to match(/placeholder="[^"]*\d/),
                                 "the price placeholder must not contain a number"
    end

    it "says the price is the operator's on the listing" do
      get :index, params: { event_slug: event.slug }

      expect(CGI.unescapeHTML(response.body))
        .to match(/You set the price|never sets it/i)
    end

    %w[what price storefront review].each do |step|
      it "quotes no average, typical or suggested amount on the #{step} screen" do
        get :new, params: { event_slug: event.slug, step: }

        expect(CGI.unescapeHTML(response.body)).not_to match(suggestion)
      end
    end

    it "quotes no average, typical or suggested amount on the listing" do
      get :index, params: { event_slug: event.slug }

      expect(CGI.unescapeHTML(response.body)).not_to match(suggestion)
    end
  end

  describe "the create wizard" do
    before { create_session(teen, verified: true) }

    it "creates a draft after the price step and does not publish it" do
      post :wizard, params: {
        event_slug: event.slug,
        step: "what",
        fuime_offer: { name: "Lawn mow", description: "I bring my own mower." }
      }
      expect(response).to redirect_to(new_fuime_offer_step_path(event_slug: event.slug, step: "price"))

      post :wizard, params: {
        event_slug: event.slug,
        step: "price",
        fuime_offer: { price: "35", unit_label: "per visit" }
      }

      offer = event.fuime_offers.last
      expect(offer).to be_present
      expect(offer).to be_draft
      expect(offer.price_cents).to eq(35_00)
      expect(response).to redirect_to(new_fuime_offer_step_path(event_slug: event.slug, step: "storefront"))
    end

    it "refuses to publish from review without sale terms" do
      offer = create(:fuime_offer, event:, name: "Lawn mow")
      session[:offer_wizard] = { event.slug => { "offer_id" => offer.id, "name" => offer.name } }

      post :wizard, params: { event_slug: event.slug, step: "review", intent: "publish" }

      expect(offer.reload).to be_draft
      expect(flash[:alert]).to match(/confirm how selling through Fuime works|can't take payments|published/i)
    end
  end

  describe "publishing" do
    before { create_session(teen, verified: true) }

    # AASM reverts the state on a failed save and returns false rather than
    # raising, so an unconditional success message here would tell a teenager
    # their offer was live while it sat in draft. This is that bug, caught.
    it "tells the operator when publishing was refused, rather than claiming success" do
      offer = create(:fuime_offer, event:)

      post :publish, params: { event_slug: event.slug, id: offer.id }

      expect(offer.reload).to be_draft
      expect(flash[:notice]).to be_blank
      expect(flash[:alert]).to match(/can't take payments/)
    end

    it "lets an unvetted venture save a draft through the wizard" do
      event.update!(operator_vetting_status: :unvetted, operator_vetted_at: nil)

      post :wizard, params: {
        event_slug: event.slug,
        step: "what",
        fuime_offer: { name: "Lawn mow", description: "I bring my own mower." }
      }
      post :wizard, params: {
        event_slug: event.slug,
        step: "price",
        fuime_offer: { price: "35" }
      }

      offer = event.fuime_offers.last
      expect(offer).to be_present
      expect(offer).to be_draft
      expect(event.reload.accepts_payments?).to be(false)
    end

    it "does not publish while the venture is unvetted" do
      event.update!(operator_vetting_status: :unvetted, operator_vetted_at: nil)
      offer = create(:fuime_offer, event:)

      post :publish, params: { event_slug: event.slug, id: offer.id }

      expect(offer.reload).to be_draft
      expect(event.accepts_payments?).to be(false)
      expect(flash[:alert]).to match(/can't take payments|not been approved/i)
    end

    it "does not publish while the venture is suspended" do
      event.update!(operator_vetting_status: :suspended)
      offer = create(:fuime_offer, event:)

      post :publish, params: { event_slug: event.slug, id: offer.id }

      expect(offer.reload).to be_draft
      expect(event.accepts_payments?).to be(false)
      expect(flash[:alert]).to match(/can't take payments|suspended/i)
    end

    it "publishes once the venture is approved and can sell" do
      allow_any_instance_of(::Event).to receive(:accepts_payments?).and_return(true)
      offer = create(:fuime_offer, event:)

      post :publish, params: { event_slug: event.slug, id: offer.id }

      expect(offer.reload).to be_published
      expect(flash[:notice]).to match(/live on your storefront/)
    end
  end

  describe "scoping" do
    # `decide_payout?` had the same hazard: an id from another venture acted on
    # because authorization was checked against @event rather than the record.
    it "will not let an operator act on another venture's offer" do
      create_session(teen, verified: true)
      other = create(:fuime_offer, event: create(:event))

      expect {
        post :archive, params: { event_slug: event.slug, id: other.id }
      }.to raise_error(ActiveRecord::RecordNotFound)

      expect(other.reload).not_to be_archived
    end
  end
end
