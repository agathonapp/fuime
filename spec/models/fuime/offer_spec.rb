# frozen_string_literal: true

require "rails_helper"

RSpec.describe Fuime::Offer do
  # `#accepts_payments?` needs a Stripe account ready for payments, which no
  # factory event has. Stubbed rather than built because these examples are about
  # the offer, not about onboarding — the one example that cares about the gate
  # uses a venture where the block is vetting instead.
  let(:event) { create(:event).tap { |e| allow(e).to receive(:accepts_payments?).and_return(true) } }

  def offer(**attrs)
    build(:fuime_offer, event:, **attrs)
  end

  describe "the price" do
    # The whole reason this object has no default and no suggestion column.
    # A default is a Fuime-set rate for every operator who never changed it,
    # which is what §8.3 D2's misclassification mitigation forbids.
    it "has no default — the operator must supply one" do
      expect(described_class.new.price_cents).to be_nil
      expect(described_class.column_defaults["price_cents"]).to be_nil
    end

    it "refuses zero and negatives" do
      expect(offer(price_cents: 0)).not_to be_valid
      expect(offer(price_cents: -100)).not_to be_valid
    end

    it "refuses an amount above the ceiling" do
      expect(offer(price_cents: described_class::MAXIMUM_PRICE_CENTS + 1)).not_to be_valid
    end

    # The message must not name a range or an average — saying "most people
    # charge…" is the exact thing the schema is shaped to prevent.
    it "does not suggest an amount when it refuses one" do
      bad = offer(price_cents: 0)
      bad.valid?

      expect(bad.errors[:price_cents].join).to match(/decided on/)
      expect(bad.errors[:price_cents].join).not_to match(/most|average|typical|usually|suggest/i)
    end
  end

  describe "#price_sentence" do
    it "is the price alone with no unit" do
      expect(offer(price_cents: 35_00, unit_label: nil).price_sentence).to eq("$35.00")
    end

    it "uses the operator's own words for the unit" do
      expect(offer(price_cents: 35_00, unit_label: "per lawn").price_sentence).to eq("$35.00 per lawn")
    end
  end

  # Before offers, every ledger line said whatever an anonymous buyer typed into
  # a free-text box. This is the other half of what the object is worth.
  describe "#payment_description" do
    it "describes the thing sold, not whatever a stranger typed" do
      expect(offer(name: "Front and back lawn mow", unit_label: "per visit").payment_description)
        .to eq("Front and back lawn mow — per visit")
    end
  end

  describe "publishing" do
    it "goes draft → published → draft again" do
      record = create(:fuime_offer, event:)

      record.publish!
      expect(record).to be_published

      record.unpublish!
      expect(record).to be_draft
    end

    # A draft is for a teenager setting up their shop while a guardian finishes
    # Stripe onboarding — the ordinary case. Publishing is a public promise that
    # a payment will work.
    # AASM is not whiny by default: a transition whose save fails validation
    # REVERTS the in-memory state and returns false rather than raising. Asserted
    # here because the controller has to check that boolean — an unconditional
    # success message after `publish!` would tell a teenager their offer was live
    # while it sat in draft.
    it "refuses to publish an offer for a venture that cannot sell" do
      blocked = create(:event, :unvetted)
      record = create(:fuime_offer, event: blocked)

      expect(record.publish!).to be(false)
      expect(record.reload).to be_draft
      expect(record.errors.full_messages.to_sentence).to match(/can't take payments/)
    end

    it "still allows a draft on a venture that cannot sell" do
      blocked = create(:event, :unvetted)

      expect(build(:fuime_offer, event: blocked)).to be_valid
    end
  end

  describe "archiving" do
    # A sold offer is referenced by a ledger memo and a buyer's receipt.
    it "archives rather than deleting, and comes back as a draft" do
      record = create(:fuime_offer, event:)
      record.publish!

      record.archive!
      expect(record).to be_archived
      expect(described_class.find(record.id)).to be_present

      record.restore!
      expect(record).to be_draft, "a restored offer must be re-checked before it is on sale again"
    end
  end

  describe "scopes" do
    it "shows the storefront only published offers, in the operator's order" do
      second = create(:fuime_offer, event:, position: 2, name: "Second")
      first = create(:fuime_offer, event:, position: 1, name: "First")
      create(:fuime_offer, event:, position: 0, name: "Draft")
      [second, first].each { |o| expect(o.publish!).to be_truthy }

      expect(described_class.published.in_operator_order.map(&:name)).to eq(%w[First Second])
    end
  end
end
