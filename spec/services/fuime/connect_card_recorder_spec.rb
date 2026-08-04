# frozen_string_literal: true

require "rails_helper"

# Fuime: card spend landing on the venture's ledger. This is the half of the card
# feature that is actually the product — a card that works is a commodity, a card
# whose purchases land on the books is the bookkeeping story.
RSpec.describe Fuime::ConnectCardRecorder do
  let(:venture) { create(:event) }
  let(:guardian) { create(:user, birthday: 40.years.ago.to_date) }
  let!(:account) { create(:stripe_connected_account, :cards_active, event: venture, owner: guardian) }

  def handle(type, object, account_id: account.stripe_id)
    described_class.new(
      event: Stripe::Event.construct_from(type:, account: account_id, data: { object: })
    ).handle
  end

  # Stripe reports Issuing transaction amounts as NEGATIVE for a capture.
  def issuing_transaction(id: "ipi_1", amount: -4_200, type: "capture", merchant: "Acme Craft Supply")
    {
      id:,
      object: "issuing.transaction",
      amount:,
      currency: "usd",
      type:,
      created: Time.current.to_i,
      merchant_data: { name: merchant, category: "artists_supply_and_craft_shops" }
    }
  end

  def ledger_lines
    CanonicalPendingEventMapping
      .where(event_id: venture.id)
      .map(&:canonical_pending_transaction)
  end

  describe "a card purchase" do
    it "posts a negative line naming the merchant" do
      handle("issuing_transaction.created", issuing_transaction)

      expect(ledger_lines.map(&:amount_cents)).to contain_exactly(-4_200)
      expect(ledger_lines.first.memo).to eq("Card purchase — Acme Craft Supply")
    end

    # A card purchase genuinely spends money on the business, unlike a payout, so it
    # must stay countable as a deductible expense. The memo is worded to avoid every
    # exclusion pattern, and this is the assertion that keeps it that way.
    it "is not excluded from the tax tracker" do
      handle("issuing_transaction.created", issuing_transaction)

      memo = ledger_lines.first.memo.downcase
      Fuime::TaxTrackerService::EXCLUDED_MEMO_PATTERNS.each do |pattern|
        expect(memo).not_to include(pattern),
                            "card spend must remain a deductible expense, but its memo matches #{pattern.inspect}"
      end
    end

    it "falls back to a plain label when Stripe sends no merchant name" do
      handle("issuing_transaction.created", issuing_transaction(merchant: nil))

      expect(ledger_lines.first.memo).to eq("Card purchase")
    end

    it "is idempotent across Stripe retries" do
      3.times { handle("issuing_transaction.created", issuing_transaction) }

      expect(ledger_lines.size).to eq(1)
    end

    # Sign is taken from `type`, never from the reported amount. If Stripe's sign
    # convention changed, trusting it would silently turn a teenager's expenses into
    # income and inflate the tax figure shown to their family.
    it "records a capture as an expense even if the amount arrives positive" do
      handle("issuing_transaction.created", issuing_transaction(amount: 4_200, type: "capture"))

      expect(ledger_lines.map(&:amount_cents)).to contain_exactly(-4_200)
    end

    it "does not front the spend" do
      handle("issuing_transaction.created", issuing_transaction)

      expect(ledger_lines.map(&:fronted)).to all(be false)
    end
  end

  describe "a card refund" do
    it "posts a positive line" do
      handle("issuing_transaction.created", issuing_transaction(id: "ipi_ref", amount: 4_200, type: "refund"))

      expect(ledger_lines.map(&:amount_cents)).to contain_exactly(4_200)
      expect(ledger_lines.first.memo).to match(/card refund/i)
    end

    it "nets to zero against the original purchase" do
      handle("issuing_transaction.created", issuing_transaction)
      handle("issuing_transaction.created", issuing_transaction(id: "ipi_ref", amount: 4_200, type: "refund"))

      expect(ledger_lines.sum(&:amount_cents)).to eq(0)
    end
  end

  describe "things it declines to post" do
    # An authorization is a hold, not a purchase: it can expire, reverse, or capture a
    # different amount. Posting one would put a phantom expense on a teenager's books.
    it "ignores authorizations entirely" do
      expect {
        handle("issuing_authorization.request", { id: "iauth_1", object: "issuing.authorization", amount: -9_900 })
      }.not_to change(CanonicalPendingTransaction, :count)
    end

    it "ignores a transaction type it does not understand" do
      expect {
        handle("issuing_transaction.created", issuing_transaction(type: "dispute"))
      }.not_to change(CanonicalPendingTransaction, :count)
    end

    it "ignores a zero-amount transaction" do
      expect {
        handle("issuing_transaction.created", issuing_transaction(amount: 0))
      }.not_to change(CanonicalPendingTransaction, :count)
    end

    it "ignores an event from a connected account Fuime does not know" do
      expect {
        handle("issuing_transaction.created", issuing_transaction, account_id: "acct_unknown")
      }.not_to change(CanonicalPendingTransaction, :count)
    end

    it "books to the venture that owns the account, not another one" do
      other = create(:event)
      create(:stripe_connected_account, :cards_active, event: other)

      handle("issuing_transaction.created", issuing_transaction)

      expect(CanonicalPendingEventMapping.where(event_id: other.id)).to be_empty
    end
  end

  describe "dispatch through the Connect webhook handler" do
    it "routes issuing transactions to this recorder" do
      Fuime::ConnectWebhookHandler.new(
        event: Stripe::Event.construct_from(
          type: "issuing_transaction.created",
          account: account.stripe_id,
          data: { object: issuing_transaction }
        )
      ).handle

      expect(ledger_lines.map(&:amount_cents)).to contain_exactly(-4_200)
    end
  end

  describe "a full venture lifecycle" do
    it "leaves sale minus fee minus card spend on the books" do
      Fuime::ConnectPaymentRecorder.new(
        event: Stripe::Event.construct_from(
          type: "payment_intent.succeeded", account: account.stripe_id,
          data: { object: { id: "pi_life", object: "payment_intent", amount_received: 10_000,
                            application_fee_amount: 400, created: Time.current.to_i
}
}
        )
      ).handle

      handle("issuing_transaction.created", issuing_transaction(amount: -4_200))

      # $100 in, $4 to Fuime, $42 of supplies bought on the card.
      expect(ledger_lines.sum(&:amount_cents)).to eq(5_400)
    end
  end
end
