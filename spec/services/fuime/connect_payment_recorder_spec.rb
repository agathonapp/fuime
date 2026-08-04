# frozen_string_literal: true

require "rails_helper"

# Fuime: this is the money-in path for the architecture that actually ships —
# direct charges on a guardian-owned connected account. It writes to a minor's
# business ledger from an external webhook, so venture resolution, idempotency and
# reversal arithmetic are all correctness-critical.
RSpec.describe Fuime::ConnectPaymentRecorder do
  let(:venture) { create(:event) }
  let!(:connected_account) { create(:stripe_connected_account, :ready, event: venture) }
  let(:account_id) { connected_account.stripe_id }

  # Connected-account events carry the account at the TOP level of the event, not
  # inside the object. That field is the join to a venture.
  def stripe_event(type, object, account: account_id)
    Stripe::Event.construct_from(type:, account:, data: { object: })
  end

  def handle(type, object, account: account_id)
    described_class.new(event: stripe_event(type, object, account:)).handle
  end

  # A direct charge. `application_fee_amount` is what Stripe actually deducted for
  # Fuime before the money reached the venture's balance.
  def payment_intent(id: "pi_connect_1", amount: 10_000, fee: 400)
    {
      id:,
      object: "payment_intent",
      amount_received: amount,
      created: Time.current.to_i,
      description: "Sticker order",
      **(fee.nil? ? {} : { application_fee_amount: fee }),
    }
  end

  def charge(id: "ch_connect_1", intent: "pi_connect_1", refunded: 0)
    {
      id:,
      object: "charge",
      payment_intent: intent,
      amount_refunded: refunded,
      created: Time.current.to_i,
    }
  end

  def ledger_lines(for_event: venture)
    CanonicalPendingEventMapping
      .where(event_id: for_event.id)
      .map(&:canonical_pending_transaction)
  end

  def net_cents
    ledger_lines.sum(&:amount_cents)
  end

  def memos
    ledger_lines.map(&:memo)
  end

  describe "recording a direct charge" do
    it "posts the gross payment and Fuime's fee as separate lines" do
      handle("payment_intent.succeeded", payment_intent)

      expect(ledger_lines.map(&:amount_cents)).to contain_exactly(10_000, -400)
      # $100 sale, $4 to Fuime, family keeps $96.
      expect(net_cents).to eq(9_600)
    end

    it "resolves the venture from the connected account, not from metadata" do
      # No `fuime_event_id` anywhere in this payload. The pooled handler would
      # drop it; this one must not, because `event.account` is Stripe's own
      # statement of whose account the money moved through.
      handle("payment_intent.succeeded", payment_intent)

      expect(ledger_lines.size).to eq(2)
    end

    it "records the fee Stripe actually took rather than recomputing a rate" do
      # A fee that does not match any plan percentage. If this class computed the
      # cut instead of observing it, this would come out as -400.
      handle("payment_intent.succeeded", payment_intent(fee: 137))

      expect(ledger_lines.map(&:amount_cents)).to contain_exactly(10_000, -137)
    end

    it "posts no fee line for a venture whose plan takes no cut" do
      # The Founders plan is 0%, and Stripe rejects a zero application fee, so the
      # field is absent rather than zero. A phantom fee line here would charge a
      # venture whose entire promise is that it is not charged.
      handle("payment_intent.succeeded", payment_intent(fee: nil))

      expect(ledger_lines.map(&:amount_cents)).to contain_exactly(10_000)
      expect(memos).not_to include(match(/platform fee/i))
    end

    it "does not front the money" do
      handle("payment_intent.succeeded", payment_intent)

      # Stripe settlement is T+2 and Fuime holds no reserves, so nothing here may
      # be spendable before it settles.
      expect(ledger_lines.map(&:fronted)).to all(be false)
    end

    it "ignores a zero-amount payment" do
      handle("payment_intent.succeeded", payment_intent(amount: 0))

      expect(ledger_lines).to be_empty
    end
  end

  describe "Stripe's own processing fee" do
    # Stubs a charge whose balance transaction breaks the fees down by type. On a direct
    # charge, `fee` is the TOTAL deducted and INCLUDES the application fee — which is
    # exactly why only the stripe_fee entries may be posted.
    def stub_charge(stripe_fee: 320, application_fee: 400, id: "ch_connect_1")
      allow(Stripe::Charge).to receive(:retrieve).and_return(
        Stripe::Charge.construct_from(
          id:,
          balance_transaction: {
            id: "txn_1",
            fee: stripe_fee + application_fee,
            fee_details: [
              { type: "stripe_fee", amount: stripe_fee, currency: "usd" },
              { type: "application_fee", amount: application_fee, currency: "usd" }
            ]
          }
        )
      )
    end

    def intent_with_charge(**opts)
      payment_intent(**opts).merge(latest_charge: "ch_connect_1")
    end

    it "posts Stripe's cut as its own line so the ledger reconciles" do
      stub_charge(stripe_fee: 320)

      handle("payment_intent.succeeded", intent_with_charge)

      expect(ledger_lines.map(&:amount_cents)).to contain_exactly(10_000, -400, -320)
      # $100 sale, $4 to Fuime, $3.20 to Stripe, family keeps $92.80.
      expect(net_cents).to eq(9_280)
    end

    it "names the two fees separately, because they are two different companies" do
      stub_charge

      handle("payment_intent.succeeded", intent_with_charge)

      expect(memos).to include(match(/Fuime platform fee/i))
      expect(memos).to include(match(/Stripe processing fee/i))
    end

    # THE bug this guards. `balance_transaction.fee` here is 720; posting that alongside
    # the $4 application fee would charge the family Fuime's cut twice.
    it "never double-counts the application fee" do
      stub_charge(stripe_fee: 320, application_fee: 400)

      handle("payment_intent.succeeded", intent_with_charge)

      fee_total = ledger_lines.select { |l| l.amount_cents.negative? }.sum(&:amount_cents)
      expect(fee_total).to eq(-720)
    end

    it "reads the charge on the venture's own connected account" do
      stub_charge

      handle("payment_intent.succeeded", intent_with_charge)

      expect(Stripe::Charge).to have_received(:retrieve).with(
        hash_including(expand: ["balance_transaction"]),
        hash_including(stripe_account: account_id)
      )
    end

    it "is idempotent across retries" do
      stub_charge

      3.times { handle("payment_intent.succeeded", intent_with_charge) }

      expect(ledger_lines.size).to eq(3)
      expect(net_cents).to eq(9_280)
    end

    # A charge Stripe took no fee on is a real answer, and a phantom zero line would be
    # noise on a teenager's books.
    it "posts nothing when Stripe took no fee" do
      stub_charge(stripe_fee: 0, application_fee: 400)

      handle("payment_intent.succeeded", intent_with_charge)

      expect(memos).not_to include(match(/Stripe processing fee/i))
    end

    # Older payloads and some payment types have no charge to read. The payment must
    # still post.
    it "still records the payment when there is no charge to inspect" do
      handle("payment_intent.succeeded", payment_intent)

      expect(ledger_lines.map(&:amount_cents)).to contain_exactly(10_000, -400)
    end

    # Raising lets Stripe retry the whole webhook. Because every ledger key is shared and
    # idempotent, the retry re-posts nothing for the payment and simply tries the fee
    # again — whereas swallowing the error would leave the balance permanently overstated.
    it "raises so Stripe retries when the fee cannot be read" do
      allow(Stripe::Charge).to receive(:retrieve).and_raise(Stripe::APIError.new("boom"))

      expect {
        handle("payment_intent.succeeded", intent_with_charge)
      }.to raise_error(Stripe::APIError)
    end

    it "records the payment on the retry after a transient failure" do
      allow(Stripe::Charge).to receive(:retrieve).and_raise(Stripe::APIError.new("boom"))
      expect { handle("payment_intent.succeeded", intent_with_charge) }.to raise_error(Stripe::APIError)

      stub_charge(stripe_fee: 320)
      handle("payment_intent.succeeded", intent_with_charge)

      expect(net_cents).to eq(9_280)
    end

    # Both fees are genuine deductible business expenses, unlike a payout.
    it "keeps both fees countable as deductible expenses" do
      stub_charge

      handle("payment_intent.succeeded", intent_with_charge)

      Fuime::TaxTrackerService::EXCLUDED_MEMO_PATTERNS.each do |pattern|
        expect("Stripe processing fee".downcase).not_to include(pattern)
      end
    end
  end

  describe "venture resolution failures" do
    it "ignores an event from a connected account Fuime does not know" do
      # Stripe legitimately delivers events for accounts a platform created and
      # abandoned, and replaying old events after a restore hits this honestly.
      expect {
        handle("payment_intent.succeeded", payment_intent, account: "acct_unknown")
      }.not_to change(CanonicalPendingTransaction, :count)
    end

    it "ignores an event with no connected account at all" do
      expect {
        handle("payment_intent.succeeded", payment_intent, account: nil)
      }.not_to change(CanonicalPendingTransaction, :count)
    end

    it "books the payment to the venture that owns the account, not another one" do
      other_venture = create(:event)
      create(:stripe_connected_account, :ready, event: other_venture)

      handle("payment_intent.succeeded", payment_intent)

      expect(ledger_lines(for_event: other_venture)).to be_empty
      expect(ledger_lines(for_event: venture).size).to eq(2)
    end
  end

  describe "idempotency" do
    it "posts one ledger line per payment however many times Stripe retries" do
      3.times { handle("payment_intent.succeeded", payment_intent) }

      expect(ledger_lines.size).to eq(2)
      expect(net_cents).to eq(9_600)
    end

    # The reason Fuime::VentureLedger owns the key scheme instead of each handler
    # defining its own. Webhook endpoint scoping is a dashboard checkbox, and
    # ticking "also send connected account events" on the platform endpoint would
    # otherwise post every sale to a teenager's ledger twice.
    it "does not double-post a payment also seen by the pooled handler" do
      handle("payment_intent.succeeded", payment_intent)

      pooled = Stripe::Event.construct_from(
        type: "payment_intent.succeeded",
        data: {
          object: payment_intent.merge(
            metadata: { "fuime_event_id" => venture.id.to_s, "fuime_fee_cents" => "400" }
          )
        }
      )
      Fuime::PaymentWebhookHandler.new(event: pooled).handle

      expect(ledger_lines.size).to eq(2)
      expect(net_cents).to eq(9_600)
    end
  end

  describe "refunds" do
    before { handle("payment_intent.succeeded", payment_intent) }

    it "posts a negative line reversing the payment" do
      handle("charge.refunded", charge(refunded: 10_000))

      expect(memos).to include(match(/refunded payment/i))
      # Gross +100, fee -4, reversal -100. The fee has NOT come back yet.
      expect(net_cents).to eq(-400)
    end

    # The single most important difference from the pooled handler. Stripe does not
    # return the platform's application fee when a charge is refunded unless the
    # refund explicitly asks it to, so crediting it here would print money into a
    # family's ledger that is still sitting in Fuime's account.
    it "does not credit Fuime's fee back until Stripe says it was returned" do
      handle("charge.refunded", charge(refunded: 10_000))

      expect(memos).not_to include(match(/fee refunded/i))
    end

    it "reverses only the outstanding amount across incremental refunds" do
      # `amount_refunded` is CUMULATIVE, so posting it verbatim on the second
      # event would claw back $150 against a $100 payment.
      handle("charge.refunded", charge(id: "ch_a", refunded: 6_000))
      handle("charge.refunded", charge(id: "ch_b", refunded: 10_000))

      reversals = ledger_lines.select { |l| l.memo.to_s.match?(/refunded payment/i) }
      expect(reversals.sum(&:amount_cents)).to eq(-10_000)
    end

    it "ignores a refund for a payment it never recorded" do
      expect {
        handle("charge.refunded", charge(id: "ch_ghost", intent: "pi_never_seen", refunded: 5_000))
      }.not_to change(CanonicalPendingTransaction, :count)
    end

    it "is idempotent on replay" do
      2.times { handle("charge.refunded", charge(refunded: 10_000)) }

      reversals = ledger_lines.select { |l| l.memo.to_s.match?(/refunded payment/i) }
      expect(reversals.size).to eq(1)
    end
  end

  describe "disputes" do
    before { handle("payment_intent.succeeded", payment_intent) }

    def dispute(id: "dp_1", intent: "pi_connect_1", amount: 10_000)
      { id:, object: "dispute", payment_intent: intent, amount:, created: Time.current.to_i }
    end

    it "posts a chargeback line against the venture" do
      handle("charge.dispute.created", dispute)

      expect(memos).to include(match(/disputed payment/i))
      expect(net_cents).to eq(-400)
    end
  end

  describe "application_fee.refunded" do
    before { handle("payment_intent.succeeded", payment_intent) }

    # Application fees are platform objects, so this event has no connected
    # account on it. It is traced to a venture through the fee line already in the
    # ledger rather than through `event.account`.
    def fee_refund(id: "fee_1", intent: "pi_connect_1", refunded: 400)
      {
        id:,
        object: "application_fee",
        originating_transaction: intent,
        charge: "ch_connect_1",
        amount_refunded: refunded,
        created: Time.current.to_i,
      }
    end

    def handle_fee(object)
      described_class.new(
        event: Stripe::Event.construct_from(type: "application_fee.refunded", data: { object: })
      ).handle
    end

    it "credits the fee back once Stripe confirms it was returned" do
      handle_fee(fee_refund)

      expect(memos).to include(match(/fee refunded/i))
      # Gross +100, fee -4, fee back +4.
      expect(net_cents).to eq(10_000)
    end

    it "never credits back more than was charged" do
      handle_fee(fee_refund(refunded: 999_999))

      rebates = ledger_lines.select { |l| l.memo.to_s.match?(/fee refunded/i) }
      expect(rebates.sum(&:amount_cents)).to eq(400)
    end

    it "caps cumulative partial fee refunds at the original fee" do
      handle_fee(fee_refund(id: "fee_a", refunded: 300))
      handle_fee(fee_refund(id: "fee_b", refunded: 300))

      rebates = ledger_lines.select { |l| l.memo.to_s.match?(/fee refunded/i) }
      expect(rebates.sum(&:amount_cents)).to eq(400)
    end

    it "ignores a fee refund for a payment with no recorded fee line" do
      expect {
        handle_fee(fee_refund(intent: "pi_never_seen"))
      }.not_to change(CanonicalPendingTransaction, :count)
    end
  end

  describe "event types it does not own" do
    it "ignores account lifecycle events" do
      expect {
        handle("account.updated", { id: account_id, object: "account", charges_enabled: true })
      }.not_to change(CanonicalPendingTransaction, :count)
    end
  end
end
