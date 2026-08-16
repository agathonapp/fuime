# frozen_string_literal: true

require "rails_helper"

# Fuime: buying an offer, and the four ways that has to be un-riggable.
#
# The checkout endpoint is public and unauthenticated — the payer is a customer,
# not a Fuime user — so everything about which offer is being bought and what it
# costs arrives from a stranger. These examples are the boundary.
RSpec.describe Fuime::CheckoutsController, type: :controller do
  let(:event) { create(:event, is_public: true) }
  let(:offer) { create(:fuime_offer, event:, price_cents: 35_00, name: "Front and back lawn mow") }

  before do
    allow_any_instance_of(::Event).to receive(:accepts_payments?).and_return(true)
    allow(::Fuime::PaymentLinkService).to receive(:new).and_return(payment_link)
  end

  let(:payment_link) do
    instance_double(::Fuime::PaymentLinkService,
                    create_checkout_session: double(url: "https://checkout.stripe.test/s"))
  end

  def buy!(params)
    post :create, params: { slug: event.slug }.merge(params)
  end

  describe "buying a published offer" do
    before { offer.publish! }

    it "charges the price the operator set" do
      expect(::Fuime::PaymentLinkService).to receive(:new)
        .with(hash_including(amount_cents: 35_00)).and_return(payment_link)

      buy!(offer_id: offer.id)
    end

    it "describes the thing sold rather than whatever the buyer typed" do
      expect(::Fuime::PaymentLinkService).to receive(:new)
        .with(hash_including(description: offer.payment_description)).and_return(payment_link)

      buy!(offer_id: offer.id, description: "lol")
    end

    # The one that matters most. A posted `amount` alongside an `offer_id` must
    # be ignored entirely — otherwise a stranger buys a $35 lawn mow for $1 by
    # editing a form field, and reading the price off the record is the only
    # version of this that cannot be rewritten in a browser.
    it "ignores an amount the buyer supplies alongside the offer" do
      expect(::Fuime::PaymentLinkService).to receive(:new)
        .with(hash_including(amount_cents: 35_00)).and_return(payment_link)

      buy!(offer_id: offer.id, amount: "1.00")
    end
  end

  describe "offers that are not for sale" do
    it "refuses a draft" do
      buy!(offer_id: offer.id)

      expect(::Fuime::PaymentLinkService).not_to have_received(:new)
      expect(flash[:alert]).to match(/isn't for sale/)
    end

    it "refuses an archived offer, so a stale link cannot buy one" do
      offer.publish!
      offer.archive!

      buy!(offer_id: offer.id)

      expect(flash[:alert]).to match(/isn't for sale/)
    end

    # An offer id from another venture would charge this buyer for something this
    # business does not sell — and credit the wrong operator's ledger.
    it "refuses an offer belonging to a different venture" do
      other = create(:fuime_offer, event: create(:event))
      other.publish!

      buy!(offer_id: other.id)

      expect(flash[:alert]).to match(/isn't for sale/)
    end

    it "refuses an id that does not exist rather than falling back to a free amount" do
      buy!(offer_id: 999_999, amount: "5.00")

      expect(::Fuime::PaymentLinkService).not_to have_received(:new)
      expect(flash[:alert]).to match(/isn't for sale/)
    end
  end

  # The pre-offers path still works: it is the right thing for a venture that has
  # listed nothing, and for a customer quoted a price in person.
  describe "paying a free amount" do
    it "still charges what the buyer entered when no offer is named" do
      expect(::Fuime::PaymentLinkService).to receive(:new)
        .with(hash_including(amount_cents: 25_00)).and_return(payment_link)

      buy!(amount: "25.00")
    end
  end
end
