# frozen_string_literal: true

require "rails_helper"

# Fuime: the buyer has to be able to see who they are contracting with.
#
# Under FEATURE_MERCHANT_OF_RECORD, customer money lands in Fuime's own Stripe
# balance. That is Fuime's own revenue — and so lawful without a money-transmitter
# licence — only if Fuime is genuinely the seller: Fuime's terms of sale, Fuime's
# name on the receipt, Fuime carrying the refund and chargeback obligation
# (docs/fuime/MOR_RISK_ACCEPTANCE.md §2 Q1).
#
# Until 2026-08-19 that claim appeared ONLY in operator-facing and admin copy.
# Every screen asserting "Fuime LLC is the seller of record" faced an operator or
# an admin; the customer handing over money was told nothing. The claim was made
# everywhere except to the party it is about.
#
# This spec exists because that is a legal position held up by page copy, and page
# copy is the easiest thing in a codebase to delete by accident.
RSpec.describe "seller of record disclosure", type: :request do
  let(:venture) do
    create(:event, business_category: "services", is_public: true, name: "Sunset Lawn Care").tap do |e|
      e.update!(operator_vetting_status: "approved")
    end
  end

  let!(:offer) do
    create(:fuime_offer, event: venture, name: "Lawn mowing", price_cents: 4000).tap(&:publish!)
  end

  context "under merchant-of-record", :merchant_of_record do
    it "names Fuime LLC as the seller on the storefront" do
      get fuime_storefront_path(slug: venture.slug)

      expect(response.body).to include("Fuime LLC")
      expect(response.body).to match(/fulfilled by/i)
    end

    it "names Fuime LLC as the seller on the page where the buyer actually pays" do
      get fuime_payment_page_path(event_slug: venture.slug, offer: offer.to_param)

      expect(response.body).to include("Fuime LLC")
    end

    # The refund obligation is the substance of the claim. A page that says Fuime
    # sells but sends refund questions to a fifteen-year-old would assert the
    # structure and then contradict it.
    it "points payment problems at Fuime rather than at the young founder" do
      get terms_path

      expect(response.body).to include("support@fuime.com")
      expect(response.body).to match(/Fuime LLC is the seller/i)
      # \s+ rather than a literal space: the sentence wraps in the ERB source, so
      # the rendered HTML carries a newline and indentation mid-phrase. A literal
      # space here fails for a reason that has nothing to do with the copy.
      expect(response.body).to match(/chargeback is ours to\s+answer/i)
    end
  end

  # Under Connect the guardian's own connected account is the merchant, so this
  # disclosure would be false. Asserting the negative because a partial that
  # renders unconditionally is the likely shape of a future mistake.
  context "under Connect, where the guardian's account is the merchant" do
    it "does not claim Fuime is the seller on the storefront" do
      get fuime_storefront_path(slug: venture.slug)

      expect(response.body).not_to match(/Sold by\s*<strong>Fuime LLC/i)
    end
  end

  # The beta-era sentence "no real payments are processed, so no real fees are
  # charged" was true in test mode and became false the moment STRIPE_MODE=live.
  # L8 exists because Fuime has already once shipped copy describing a product it
  # did not have; this is the same failure pointed at customers.
  it "no longer tells customers that no real payments are processed" do
    get terms_path

    expect(response.body).not_to match(/no\s+real payments are processed/i)
  end
end
