# frozen_string_literal: true

require "rails_helper"

# Fuime: keeping the ledger honest about money leaving for the family's bank.
#
# The load-bearing examples are the ones about WHEN the debit posts (at creation,
# because that is when Stripe moves the balance) and the ones about payouts with no
# Fuime request behind them, because a guardian owns the account outright and can
# move their own money without asking Fuime.
RSpec.describe Fuime::ConnectPayoutRecorder do
  let(:venture) { create(:event) }
  let(:minor) { create(:user, :minor) }
  let(:guardian) { create(:user, birthday: 40.years.ago.to_date) }
  let!(:account) { create(:stripe_connected_account, :ready, event: venture, owner: guardian) }

  def stripe_event(type, object, account_id: account.stripe_id)
    Stripe::Event.construct_from(type:, account: account_id, data: { object: })
  end

  def handle(type, object, account_id: account.stripe_id)
    described_class.new(event: stripe_event(type, object, account_id:)).handle
  end

  def payout(id: "po_1", amount: 5_000, **extra)
    {
      id:,
      object: "payout",
      amount:,
      currency: "usd",
      created: Time.current.to_i,
      arrival_date: 2.days.from_now.to_i,
      **extra,
    }
  end

  def ledger_lines
    CanonicalPendingEventMapping
      .where(event_id: venture.id)
      .map(&:canonical_pending_transaction)
  end

  def balance_cents
    ledger_lines.sum(&:amount_cents)
  end

  describe "payout.created" do
    it "debits the ledger, because Stripe moves the balance at creation" do
      handle("payout.created", payout)

      expect(ledger_lines.map(&:amount_cents)).to contain_exactly(-5_000)
    end

    it "labels the line as a payout so the tax tracker excludes it" do
      handle("payout.created", payout)

      # A payout is the family moving money they already earned. Counting it as a
      # business expense would understate the teen's taxable income.
      expect(ledger_lines.first.memo).to match(/payout/i)
      expect(Fuime::TaxTrackerService::EXCLUDED_MEMO_PATTERNS).to include("payout")
    end

    it "is idempotent across Stripe retries" do
      3.times { handle("payout.created", payout) }

      expect(ledger_lines.size).to eq(1)
    end

    # A guardian owns this Stripe account and can pay themselves without Fuime.
    # The balance dropped either way, so the ledger has to say so.
    it "records a payout that has no Fuime request behind it" do
      expect(PayoutRequest.count).to eq(0)

      handle("payout.created", payout)

      expect(balance_cents).to eq(-5_000)
    end

    it "ignores a payout from a connected account Fuime does not know" do
      expect {
        handle("payout.created", payout, account_id: "acct_unknown")
      }.not_to change(CanonicalPendingTransaction, :count)
    end
  end

  describe "payout.paid" do
    let!(:request) do
      create(:payout_request, :approved, event: venture, requested_by: minor,
                                        amount_cents: 5_000, stripe_payout_id: "po_1")
    end

    it "marks the request paid" do
      handle("payout.paid", payout)

      expect(request.reload).to be_paid
      expect(request.paid_at).to be_present
    end

    # The money left the balance at creation. Debiting again here would show the
    # venture as having paid out twice.
    it "does not move the ledger again" do
      handle("payout.created", payout)
      handle("payout.paid", payout)

      expect(balance_cents).to eq(-5_000)
    end

    it "is idempotent" do
      2.times { handle("payout.paid", payout) }

      expect(request.reload).to be_paid
    end

    it "tolerates a payout with no Fuime request" do
      expect { handle("payout.paid", payout(id: "po_unknown")) }.not_to raise_error
    end
  end

  describe "payout.failed" do
    let!(:request) do
      create(:payout_request, :approved, event: venture, requested_by: minor,
                                        amount_cents: 5_000, stripe_payout_id: "po_1")
    end

    before { handle("payout.created", payout) }

    it "credits the funds back, because Stripe returns them to the balance" do
      handle("payout.failed", payout(failure_code: "account_closed", failure_message: "Bank account closed."))

      expect(balance_cents).to eq(0)
      expect(ledger_lines.map(&:memo)).to include(match(/funds returned/i))
    end

    it "records Stripe's own failure words for the family to act on" do
      handle("payout.failed", payout(failure_code: "account_closed", failure_message: "Bank account closed."))

      expect(request.reload).to be_failed
      expect(request.failure_code).to eq("account_closed")
      expect(request.failure_message).to eq("Bank account closed.")
    end

    it "is idempotent" do
      2.times { handle("payout.failed", payout(failure_code: "account_closed")) }

      returns = ledger_lines.select { |l| l.memo.to_s.match?(/funds returned/i) }
      expect(returns.size).to eq(1)
      expect(balance_cents).to eq(0)
    end

    # Crediting back funds that were never debited would invent money.
    it "does not credit anything back if the debit was never recorded" do
      other_payout = payout(id: "po_never_created", failure_code: "account_closed")

      expect { handle("payout.failed", other_payout) }
        .not_to(change { ledger_lines.select { |l| l.memo.to_s.match?(/funds returned/i) }.size })
    end
  end

  describe "payout.canceled" do
    before { handle("payout.created", payout) }

    it "returns the funds and says it was cancelled" do
      handle("payout.canceled", payout)

      expect(balance_cents).to eq(0)
      expect(ledger_lines.map(&:memo)).to include(match(/cancelled/i))
    end
  end

  describe "a full round trip" do
    it "leaves the venture with the sale minus the fee minus the payout" do
      create(:stripe_connected_account, :ready) # unrelated venture, must not be touched

      Fuime::ConnectPaymentRecorder.new(
        event: Stripe::Event.construct_from(
          type: "payment_intent.succeeded",
          account: account.stripe_id,
          data: {
            object: {
              id: "pi_round_trip", object: "payment_intent", amount_received: 10_000,
              application_fee_amount: 400, created: Time.current.to_i, description: "Sticker order"
            }
          }
        )
      ).handle

      handle("payout.created", payout(id: "po_round_trip", amount: 9_600))
      handle("payout.paid", payout(id: "po_round_trip", amount: 9_600))

      # $100 in, $4 to Fuime, $96 out to the family's bank, nothing left at Stripe.
      expect(balance_cents).to eq(0)
    end
  end
end
