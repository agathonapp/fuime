# frozen_string_literal: true

require "rails_helper"

# Fuime: this handler writes to business ledgers from an external webhook, so
# idempotency and reversal handling are correctness-critical.
# See docs/fuime/PRODUCTION_READINESS.md §1.4.
RSpec.describe Fuime::PaymentWebhookHandler do
  let(:event) { create(:event) }

  def stripe_event(type, object)
    Stripe::Event.construct_from(type:, data: { object: })
  end

  def payment_intent(id: "pi_test_1", amount: 10_000, event_id: event.id)
    {
      id:,
      object: "payment_intent",
      amount_received: amount,
      created: Time.current.to_i,
      description: "Print order",
      metadata: { "fuime_event_id" => event_id.to_s },
    }
  end

  def handle(type, object)
    described_class.new(event: stripe_event(type, object)).handle
  end

  def ledger_lines
    CanonicalPendingEventMapping
      .where(event_id: event.id)
      .map(&:canonical_pending_transaction)
  end

  describe "recording a payment" do
    it "posts one ledger line mapped to the business" do
      handle("payment_intent.succeeded", payment_intent)

      expect(ledger_lines.size).to eq(1)
      expect(ledger_lines.first.amount_cents).to eq(10_000)
    end

    # Fronting means advancing spendable credit against unsettled money. Fuime
    # has no reserves to back that.
    it "does not mark the transaction as fronted" do
      handle("payment_intent.succeeded", payment_intent)

      expect(ledger_lines.first.fronted).to be false
    end

    it "ignores payments with no business in metadata" do
      handle("payment_intent.succeeded", payment_intent(event_id: "").merge(metadata: {}))

      expect(ledger_lines).to be_empty
    end

    it "ignores payments referencing an unknown business" do
      handle("payment_intent.succeeded", payment_intent(event_id: 0))

      expect(ledger_lines).to be_empty
    end

    it "ignores non-positive amounts" do
      handle("payment_intent.succeeded", payment_intent(amount: 0))

      expect(ledger_lines).to be_empty
    end
  end

  describe "idempotency" do
    it "does not double-post when Stripe retries the same event" do
      3.times { handle("payment_intent.succeeded", payment_intent) }

      expect(ledger_lines.size).to eq(1)
    end

    # A Checkout payment emits BOTH events with different object ids. Handling
    # both posted the same payment twice.
    it "ignores checkout.session.completed for the same payment" do
      handle("payment_intent.succeeded", payment_intent)
      handle("checkout.session.completed", {
        id: "cs_test_1",
        object: "checkout_session",
        amount_total: 10_000,
        created: Time.current.to_i,
        metadata: { "fuime_event_id" => event.id.to_s },
      })

      expect(ledger_lines.size).to eq(1)
    end
  end

  describe "refunds" do
    before { handle("payment_intent.succeeded", payment_intent) }

    def charge(amount_refunded:, id: "ch_test_1")
      {
        id:,
        object: "charge",
        payment_intent: "pi_test_1",
        amount_refunded:,
        created: Time.current.to_i,
      }
    end

    it "posts a negative line reversing the payment" do
      handle("charge.refunded", charge(amount_refunded: 10_000))

      expect(ledger_lines.size).to eq(2)
      expect(ledger_lines.sum(&:amount_cents)).to eq(0)
    end

    it "handles a partial refund" do
      handle("charge.refunded", charge(amount_refunded: 4_000))

      expect(ledger_lines.sum(&:amount_cents)).to eq(6_000)
    end

    it "is idempotent on retries of the same refund" do
      3.times { handle("charge.refunded", charge(amount_refunded: 10_000)) }

      expect(ledger_lines.size).to eq(2)
      expect(ledger_lines.sum(&:amount_cents)).to eq(0)
    end

    # Stripe emits a fresh charge.refunded per increment, each carrying the
    # CUMULATIVE amount_refunded — so reversals must not stack.
    it "never reverses more than the original payment across increments" do
      handle("charge.refunded", charge(amount_refunded: 4_000))
      handle("charge.refunded", charge(amount_refunded: 10_000))

      expect(ledger_lines.sum(&:amount_cents)).to eq(0)
    end

    it "ignores a refund for a payment it never recorded" do
      expect {
        handle("charge.refunded", charge(amount_refunded: 5_000, id: "ch_other").merge(payment_intent: "pi_unknown"))
      }.not_to change { ledger_lines.size }
    end
  end

  describe "disputes" do
    before { handle("payment_intent.succeeded", payment_intent) }

    it "posts a chargeback reversal" do
      handle("charge.dispute.created", {
        id: "dp_test_1",
        object: "dispute",
        payment_intent: "pi_test_1",
        amount: 10_000,
        created: Time.current.to_i,
      })

      expect(ledger_lines.size).to eq(2)
      expect(ledger_lines.sum(&:amount_cents)).to eq(0)
      expect(ledger_lines.map(&:memo)).to include(/chargeback/i)
    end
  end

  it "ignores unrelated event types" do
    expect { handle("customer.created", { id: "cus_1", object: "customer" }) }
      .not_to change { ledger_lines.size }
  end
end
