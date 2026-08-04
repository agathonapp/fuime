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

  # The business's net after Fuime's cut — what the teen actually keeps.
  def net_cents
    ledger_lines.sum(&:amount_cents)
  end

  def fee_lines
    ledger_lines.select { |l| l.memo.to_s.match?(/platform fee/i) }
  end

  describe "recording a payment" do
    it "posts the gross payment and Fuime's fee as separate lines" do
      handle("payment_intent.succeeded", payment_intent)

      expect(ledger_lines.size).to eq(2)
      expect(ledger_lines.map(&:amount_cents)).to contain_exactly(10_000, -400)
      # 4% of $100.00 = $4.00, so the business keeps $96.00.
      expect(net_cents).to eq(9_600)
    end

    it "labels the fee so the teen can see what Fuime charged" do
      handle("payment_intent.succeeded", payment_intent)

      expect(fee_lines.size).to eq(1)
      expect(fee_lines.first.memo).to match(/Fuime platform fee \(4%\)/i)
      expect(fee_lines.first.fronted).to be false
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

      # One payment line + one fee line, however many times Stripe retries.
      expect(ledger_lines.size).to eq(2)
      expect(fee_lines.size).to eq(1)
      expect(net_cents).to eq(9_600)
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

      expect(ledger_lines.size).to eq(2)
      expect(net_cents).to eq(9_600)
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

    # A fully refunded payment must leave the business exactly where it started.
    # Fuime keeping its fee on money the teen never got would leave them net
    # NEGATIVE on a refund.
    it "posts a negative line reversing the payment and gives back the fee" do
      handle("charge.refunded", charge(amount_refunded: 10_000))

      expect(net_cents).to eq(0)
      expect(ledger_lines.map(&:memo)).to include(/fee refunded/i)
    end

    it "handles a partial refund, rebating the fee in proportion" do
      handle("charge.refunded", charge(amount_refunded: 4_000))

      # $100 in, $4 fee, $40 refunded → $1.60 of fee returned.
      # Business keeps 6000 - 400 + 160 = 5760.
      expect(net_cents).to eq(5_760)
    end

    it "is idempotent on retries of the same refund" do
      3.times { handle("charge.refunded", charge(amount_refunded: 10_000)) }

      expect(net_cents).to eq(0)
    end

    # Stripe emits a fresh charge.refunded per increment, each carrying the
    # CUMULATIVE amount_refunded — so reversals must not stack.
    it "never reverses more than the original payment across increments" do
      handle("charge.refunded", charge(amount_refunded: 4_000))
      handle("charge.refunded", charge(amount_refunded: 10_000))

      expect(net_cents).to eq(0)
    end

    it "never rebates more fee than it charged across increments" do
      handle("charge.refunded", charge(amount_refunded: 4_000))
      handle("charge.refunded", charge(amount_refunded: 10_000))

      rebated = ledger_lines.select { |l| l.memo.to_s.match?(/fee refunded/i) }.sum(&:amount_cents)
      expect(rebated).to eq(400)
    end

    it "ignores a refund for a payment it never recorded" do
      expect {
        handle("charge.refunded", charge(amount_refunded: 5_000, id: "ch_other").merge(payment_intent: "pi_unknown"))
      }.not_to(change { ledger_lines.size })
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

      # A chargeback must not leave the teen paying Fuime a fee on money that
      # was taken back from them.
      expect(net_cents).to eq(0)
      expect(ledger_lines.map(&:memo)).to include(/chargeback/i)
      expect(ledger_lines.map(&:memo)).to include(/fee refunded/i)
    end
  end

  it "ignores unrelated event types" do
    expect { handle("customer.created", { id: "cus_1", object: "customer" }) }
      .not_to(change { ledger_lines.size })
  end
end
