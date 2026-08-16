# frozen_string_literal: true

require "rails_helper"

# Fuime: the operator's own link.
#
# `fuime.com/pay/sunset-lawn-care/mow` rather than `/pay/x7Kp2mQb9rTs`. The
# random token is kept as a permalink — see AddSlugToFuimeOffers — and the rule
# that makes both worth having is that **renaming must never break a link
# somebody already sent.**
RSpec.describe Fuime::Offer, "the payment link" do
  let(:event) { create(:event) }

  describe "the slug an operator gets without asking" do
    it "reads as the thing they sell" do
      offer = create(:fuime_offer, event:, name: "Front and back lawn mow")

      expect(offer.slug).to eq("front-and-back-lawn-mow")
      expect(offer.to_param).to eq("front-and-back-lawn-mow")
    end

    # Within the venture only. Two businesses may both sell "mow" and neither
    # should have to find out the other got there first.
    it "dedupes within the venture, not across the platform" do
      create(:fuime_offer, event:, name: "Mow")
      second = create(:fuime_offer, event:, name: "Mow")
      elsewhere = create(:fuime_offer, event: create(:event), name: "Mow")

      expect(second.slug).to eq("mow-2")
      expect(elsewhere.slug).to eq("mow")
    end

    # An offer named entirely in a script that parameterizes to nothing still
    # needs a working link, and the token is it.
    it "falls back to the token when a name yields no slug" do
      offer = create(:fuime_offer, event:, name: "日本語")

      expect(offer.slug).to be_nil
      expect(offer.to_param).to eq(offer.public_token)
      expect(offer.to_param).to be_present
    end
  end

  describe "an operator choosing their own" do
    it "tidies what they type rather than refusing it" do
      offer = create(:fuime_offer, event:, slug: "  Lawn Mow  ")

      expect(offer.slug).to eq("lawn-mow")
    end

    it "collapses spaces, underscores and repeated hyphens" do
      expect(create(:fuime_offer, event:, slug: "lawn__mow--now").slug).to eq("lawn-mow-now")
    end

    it "refuses anything that would not read as a link" do
      offer = build(:fuime_offer, event:, slug: "lawn mow!")
      offer.valid?

      # normalise_slug turns the space into a hyphen; the "!" is what is left.
      expect(offer.errors[:slug].join).to match(/lowercase letters, numbers and hyphens/)
    end

    # A link like /pay/shop/checkout reads as a Fuime page rather than as one
    # operator's thing.
    it "refuses a reserved word" do
      offer = build(:fuime_offer, event:, slug: "checkout")

      expect(offer).not_to be_valid
      expect(offer.errors[:slug].join).to match(/reserved/)
    end

    it "refuses a duplicate within the same venture" do
      create(:fuime_offer, event:, slug: "mow", name: "One")
      duplicate = build(:fuime_offer, event:, slug: "mow", name: "Two")

      expect { duplicate.save! }.to raise_error(ActiveRecord::RecordNotUnique)
    end
  end

  # The whole reason the token survives alongside the slug. "Will this break the
  # link I already sent?" is the question that stops a 16-year-old from ever
  # tidying a name, and the answer has to be no.
  describe "renaming" do
    it "keeps the old permalink working" do
      offer = create(:fuime_offer, event:, name: "Mow")
      token = offer.public_token
      scope = event.fuime_offers

      offer.update!(slug: "lawn-mowing")

      expect(described_class.find_public(scope, "lawn-mowing")).to eq(offer)
      expect(described_class.find_public(scope, token)).to eq(offer),
                                                           "a flyer already printed must not stop working"
    end

    it "frees the old slug for another offer" do
      first = create(:fuime_offer, event:, name: "Mow")
      first.update!(slug: "lawn-mowing")

      expect(build(:fuime_offer, event:, slug: "mow", name: "Something else")).to be_valid
    end
  end

  describe ".find_public" do
    it "finds nothing for a blank identifier" do
      expect(described_class.find_public(event.fuime_offers, nil)).to be_nil
      expect(described_class.find_public(event.fuime_offers, "")).to be_nil
    end

    # The scope is the namespace, and the caller is responsible for it — this is
    # what stops a slug from another business buying here.
    it "only looks inside the scope it is given" do
      elsewhere = create(:fuime_offer, event: create(:event), name: "Mow")

      expect(described_class.find_public(event.fuime_offers, elsewhere.slug)).to be_nil
      expect(described_class.find_public(event.fuime_offers, elsewhere.public_token)).to be_nil
    end
  end
end
