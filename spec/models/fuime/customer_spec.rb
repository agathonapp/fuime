# frozen_string_literal: true

require "rails_helper"

# Fuime: who bought.
#
# The gap behind every analytics question Fuime could not answer, and the thing
# a founder needs to actually deliver what they sold. Most of what is pinned here
# is the identity rule — scoped to ONE venture — and the upsert, because a buyer
# is recognised by email arriving twice from two different webhook threads.
RSpec.describe Fuime::Customer do
  let(:event) { create(:event) }
  let(:other_event) { create(:event) }

  describe ".record!" do
    it "records a buyer from the email Stripe already sends" do
      customer = described_class.record!(event:, email: "ada@example.com", name: "Ada L")

      expect(customer.email).to eq("ada@example.com")
      expect(customer.name).to eq("Ada L")
      expect(customer.first_purchased_at).to be_present
    end

    it "treats the same email as the same person, however it was typed" do
      described_class.record!(event:, email: "Ada@Example.com ")
      again = described_class.record!(event:, email: "ada@example.com")

      expect(described_class.where(event:).count).to eq(1)
      expect(again.email).to eq("ada@example.com")
    end

    # The identity rule. Venture A must not be able to learn that its customer
    # also buys from venture B, which a global customer table would make a JOIN
    # away on a platform whose operators are minors.
    it "scopes a customer to one venture — the same buyer elsewhere is a separate row" do
      described_class.record!(event:, email: "ada@example.com")
      described_class.record!(event: other_event, email: "ada@example.com")

      expect(described_class.count).to eq(2)
      expect(described_class.where(event:).count).to eq(1)
    end

    it "moves the last purchase forward but never the first" do
      first = described_class.record!(event:, email: "ada@example.com",
                                      purchased_at: 1.year.ago)
      described_class.record!(event:, email: "ada@example.com", purchased_at: Time.current)

      reloaded = first.reload
      expect(reloaded.first_purchased_at).to be_within(1.minute).of(1.year.ago)
      expect(reloaded.last_purchased_at).to be_within(1.minute).of(Time.current)
    end

    # A backfilled or out-of-order webhook must not make the most recent
    # purchase look older than it is.
    it "ignores an out-of-order webhook claiming an older purchase is the latest" do
      customer = described_class.record!(event:, email: "ada@example.com")
      described_class.record!(event:, email: "ada@example.com", purchased_at: 2.years.ago)

      expect(customer.reload.last_purchased_at).to be_within(1.minute).of(Time.current)
    end

    it "fills in a name or Stripe id a later sale supplies, and never blanks one" do
      described_class.record!(event:, email: "ada@example.com", name: "Ada L")
      described_class.record!(event:, email: "ada@example.com", stripe_customer_id: "cus_1")
      described_class.record!(event:, email: "ada@example.com")

      customer = described_class.find_by(event:, email: "ada@example.com")
      expect(customer.name).to eq("Ada L")
      expect(customer.stripe_customer_id).to eq("cus_1")
    end

    it "declines without an email — a wallet payment can complete without one" do
      expect(described_class.record!(event:, email: nil)).to be_nil
      expect(described_class.record!(event:, email: "  ")).to be_nil
    end

    # Same posture as Fuime::Sale.record!: a founder's ledger line must never be
    # lost because a customer row could not be written.
    it "never raises" do
      allow(described_class).to receive(:find_or_initialize_by).and_raise("boom")
      expect(Rails.error).to receive(:report)

      expect { described_class.record!(event:, email: "ada@example.com") }.not_to raise_error
    end
  end

  describe "what a founder sees" do
    let(:customer) { described_class.record!(event:, email: "ada@example.com", name: "Ada L") }

    def sale(cents)
      Fuime::Sale.create!(stripe_payment_intent_id: "pi_#{SecureRandom.hex(6)}",
                          event:, amount_cents: cents, occurred_at: Time.current,
                          fuime_customer_id: customer.id)
    end

    it "totals what they have spent and how often" do
      sale(25_00)
      sale(75_00)

      expect(customer.total_spent_cents).to eq(100_00)
      expect(customer.purchase_count).to eq(2)
      expect(customer).to be_repeat
    end

    it "is not a repeat customer after one purchase" do
      sale(25_00)

      expect(customer).not_to be_repeat
    end

    it "falls back to the email when Stripe sent no name" do
      nameless = described_class.record!(event:, email: "b@example.com")

      expect(nameless.display_name).to eq("b@example.com")
    end
  end
end
