# frozen_string_literal: true

require "rails_helper"

# Fuime: the payables framing, and the guarantee that its arithmetic holds.
#
# Two things are being tested and they matter for different reasons. The
# classification and reconciliation examples protect a number a teenager will act
# on. The copy examples protect a legal distinction (CLAUDE.md L1/L5): what an
# operator has is an amount Fuime owes them on a stated date, not a balance held
# on deposit.
RSpec.describe Fuime::PayablesLedger do
  let(:event)  { create(:event) }
  subject(:payables) { described_class.new(event:) }

  # Settled lines carry their Fuime::VentureLedger key in the memo as "[key]" —
  # written by VentureLedger.settled_memo and by ConnectSettlementSweep. Building
  # them directly rather than driving the sweep keeps these examples about
  # classification instead of about the import pipeline.
  # `post_line`, not `post`: Rails/HttpPositionalArguments assumes any `post(...)`
  # is an HTTP request and "corrects" the arguments into params:/session:, which
  # silently rewrote every line in this file into a request spec that tests
  # nothing. Renamed so the cop cannot mistake a ledger helper for a route.
  def post_line(key, amount_cents, memo: "Line")
    create(:canonical_transaction, amount_cents:, memo: "#{memo} [#{key}]", event:)
  end

  # One realistic sale: $100 in, Fuime's 4% out, Stripe's ~2.9%+30¢ out.
  # Returns the lines keyed by amount, so an example that needs to pair a settled
  # line with its pending twin can find it without re-deriving the memo.
  def sale(intent: "pi_1", gross: 100_00, fee: 4_00, processing: 3_20)
    lines = [
      post_line("fuime_#{intent}", gross, memo: "Payment from a customer"),
      post_line("fuime_fee_#{intent}", -fee, memo: "Fuime platform fee (4%)"),
      post_line("fuime_stripefee_#{intent}", -processing, memo: "Stripe processing fee"),
    ]
    lines.index_by(&:amount_cents)
  end

  # Fuime: the pending window — the state a venture is in for the days between a
  # sale succeeding and Stripe releasing the funds.
  #
  # This is not an edge case. Every venture is in it immediately after its first
  # sale, and Fuime's Stripe account releases funds a week out, so it is where a
  # Founders Weekend operator spends their whole first week.
  describe "a sale that has not settled yet" do
    # Pending lines carry their key on the raw row, not in the memo — the same
    # pair Fuime::PaymentWebhookHandler posts when a payment succeeds.
    def pending_line(key, amount_cents, memo: "Line")
      raw = RawPendingDonationTransaction.create!(
        donation_transaction_id: key, amount_cents:, date_posted: Date.current
      )
      cpt = CanonicalPendingTransaction.create!(
        date: raw.date, memo:, amount_cents: raw.amount_cents,
        raw_pending_donation_transaction_id: raw.id, fronted: false
      )
      CanonicalPendingEventMapping.create!(
        canonical_pending_transaction_id: cpt.id, event_id: event.id
      )
      cpt
    end

    before do
      pending_line("fuime_pi_9", 25_00, memo: "Payment from a customer")
      pending_line("fuime_fee_pi_9", -1_75, memo: "Fuime platform fee (7.0%)")
    end

    # The regression, found 2026-08-20 against a real test-mode charge one day
    # before the first live sales. `Event#balance_v2_cents` excludes pending
    # INCOMING (Fuime fronts nothing) but includes pending OUTGOING (a commitment
    # already made must not be spendable twice). Both rules are right on their own
    # terms; applied to the two halves of one sale they made a venture's first
    # sale read as a debt.
    it "does not report a successful sale as money owed to Fuime" do
      expect(payables.net_payable_cents).to eq(0)
      expect(payables).not_to be_in_arrears
      expect(payables.owed_sentence).not_to match(/refunded or disputed/i)
    end

    # The fee is one half of a pair that settles as a unit — it is not a card hold.
    it "does not count the unsettled fee as a spending commitment" do
      expect(payables.committed_cents).to eq(0)
    end

    # Promising $25 and settling $23.25 leaves $1.75 explained nowhere.
    it "reports what is coming net of the fee on it" do
      expect(payables.pending_sales_cents).to eq(23_25)
    end

    # The add-back must be a deferral, not a suppression. Once the pair settles the
    # fee has to leave the pending sum and arrive on the settled side — otherwise
    # this fix would simply have stopped charging the fee.
    #
    # Driven by creating the settled mapping, because that mapping's absence is
    # exactly what `.unsettled_sum_for` keys on. Stubbing the method under test
    # would assert only that the stub works.
    it "hands the fee to the settled side once the sale settles" do
      settled = sale(intent: "pi_9", gross: 25_00, fee: 1_75, processing: 0)

      CanonicalPendingTransaction.find_each do |cpt|
        CanonicalPendingSettledMapping.create!(
          canonical_pending_transaction: cpt, canonical_transaction: settled.fetch(cpt.amount_cents)
        )
      end

      expect(payables.unsettled_fuime_fee_cents).to eq(0)
      expect(payables.fuime_fee_cents).to eq(1_75)
      expect(payables.gross_sales_cents).to eq(25_00)
      expect(payables.net_payable_cents).to eq(23_25)
    end
  end

  describe "the breakdown" do
    before { sale }

    it "reports gross sales before any deduction" do
      expect(payables.gross_sales_cents).to eq(100_00)
    end

    it "reports Fuime's cut as a positive number" do
      expect(payables.fuime_fee_cents).to eq(4_00)
    end

    # Two different companies taking two different amounts. A family reconciling
    # their books needs to see which is which, so these never merge into "fees".
    it "reports Stripe's processing fee separately from Fuime's cut" do
      expect(payables.processing_fee_cents).to eq(3_20)
      expect(payables.processing_fee_cents).not_to eq(payables.fuime_fee_cents)
    end

    it "owes the operator what is left" do
      expect(payables.net_payable_cents).to eq(92_80)
    end

    it "does not confuse a fee line for a sale" do
      # The bug this guards: every key starts with "fuime_", so a sloppy pattern
      # for sales would sum the fee lines too and report gross sales of $107.20.
      expect(payables.gross_sales_cents).to eq(100_00)
    end
  end

  # The property that matters most. A page showing components that do not add up
  # to the total is worse than a page showing only the total.
  describe "reconciliation" do
    it "sums to the net payable for a simple sale" do
      sale

      expect(reconciled(payables)).to eq(payables.net_payable_cents)
    end

    it "sums to the net payable after a refund, a card purchase and a payout" do
      sale
      post_line("fuime_rev_pi_1_refund_re_1_2000", -20_00, memo: "Refunded payment")
      post_line("fuime_feerev_pi_1_fr_1_80", 80, memo: "Fuime platform fee refunded")
      post_line("fuime_card_ipi_1", -15_00, memo: "Card purchase")
      post_line("fuime_payout_po_1", -30_00, memo: "Payout to bank")

      expect(reconciled(payables)).to eq(payables.net_payable_cents)
    end

    # A line no category recognises must still be accounted for, or the figures
    # stop adding up the first time a new money path ships.
    it "absorbs an unrecognised line into the residual rather than losing it" do
      sale
      create(:canonical_transaction, amount_cents: -5_00, memo: "Something new entirely", event:)

      expect(payables.other_adjustments_cents).to eq(-5_00)
      expect(reconciled(payables)).to eq(payables.net_payable_cents)
    end

    def reconciled(p)
      p.gross_sales_cents -
        p.fuime_fee_cents -
        p.processing_fee_cents -
        p.refunds_cents -
        p.card_spend_cents -
        p.paid_out_cents -
        p.committed_cents +
        p.other_adjustments_cents
    end
  end

  # The figure this page shows and the figure PayoutService will actually send
  # must be the same one. If they drift, Fuime tells an operator it owes them $80
  # and then refuses to send $80, with no sentence available that explains why.
  describe "agreement with the payout cap" do
    it "reads the same figure Event#balance_v2_cents reports" do
      sale
      post_line("fuime_payout_po_1", -30_00)

      expect(payables.net_payable_cents).to eq(event.balance_v2_cents)
    end

    it "still agrees once an unsettled outgoing commitment exists" do
      sale
      create(:canonical_pending_transaction, amount_cents: -15_00, event:)

      expect(payables.committed_cents).to eq(15_00)
      expect(payables.net_payable_cents).to eq(event.balance_v2_cents)
    end
  end

  describe "what is payable" do
    # Fuime cannot pay out money Stripe has not released. Promising it would be
    # Fuime advancing its own cash against an unsettled sale — the thing
    # Event#can_front_balance? is gated to prevent.
    it "excludes money Stripe has not released yet" do
      create(:canonical_pending_transaction, amount_cents: 50_00, event:, fronted: false)

      expect(payables.net_payable_cents).to eq(0)
      expect(payables.pending_sales_cents).to eq(50_00)
    end

    it "never shows a negative amount owed" do
      post_line("fuime_rev_pi_9_refund_re_9_1000", -10_00)

      expect(payables.net_payable_cents).to eq(-10_00)
      expect(payables.amount_owed_cents).to eq(0)
    end

    it "reports arrears separately so a debt can be explained rather than negated" do
      post_line("fuime_rev_pi_9_refund_re_9_1000", -10_00)

      expect(payables).to be_in_arrears
      expect(payables.arrears_cents).to eq(10_00)
    end
  end

  describe "the payout cadence" do
    it "is the next Friday" do
      # Wednesday 12 August 2026.
      expect(payables.next_payout_on(from: Date.new(2026, 8, 12))).to eq(Date.new(2026, 8, 14))
    end

    # `Date#next_occurring` skips to next week when today already is the day,
    # which would tell somebody on payout morning that their money comes in seven
    # days.
    it "is today when today is a Friday" do
      friday = Date.new(2026, 8, 14)

      expect(payables.next_payout_on(from: friday)).to eq(friday)
    end

    it "is stated even when nothing is owed, because the schedule is the promise" do
      expect(payables.next_payout_on).to be_a(Date)
    end
  end

  # L5 forbids bank/deposit vocabulary while no partner bank exists, and the
  # payables framing forbids "balance" specifically: a stored balance the holder
  # withdraws at will is the deposit product Fuime is not offering.
  describe "the copy" do
    it "says what Fuime owes and when, without calling it a balance" do
      sale

      expect(payables.owed_sentence).to match(/Fuime owes you/)
      expect(payables.owed_sentence).to match(/paid on/)
    end

    # The ban applies to AFFIRMATIVE copy — the sentence describing what the
    # operator has. It deliberately does not apply to the disclosure, whose whole
    # job is to name what this is not, and which therefore has to use the words in
    # order to deny them. Same distinction the standing footer makes: "Fuime is a
    # financial technology company, not a bank… does not hold deposits."
    #
    # Applying one blanket list to both is how a disclosure gets watered down to
    # satisfy a spec, which is the opposite of what L5 is for.
    it "never uses deposit-account vocabulary to describe what the operator has" do
      sale
      text = payables.owed_sentence.downcase

      ["balance", "deposit", "fdic", "insured", "withdraw", "bank account", "account balance"].each do |forbidden|
        expect(text).not_to include(forbidden), "the owed sentence must not say #{forbidden.inspect}"
      end
    end

    it "states plainly that this is not money held on account" do
      expect(payables.disclosure).to match(/seller of record/)
      expect(payables.disclosure).to match(/not a bank balance/)
      expect(payables.disclosure).to match(/not.*held for you on account/)
    end

    it "explains an arrears position instead of showing a negative" do
      post_line("fuime_rev_pi_9_refund_re_9_1000", -10_00)

      expect(payables.owed_sentence).to match(/taken off your next payouts/)
    end

    it "says nothing is owed when nothing is owed" do
      expect(payables.owed_sentence).to eq("Fuime doesn't owe you anything yet.")
    end
  end

  # ── Who is actually paying ────────────────────────────────────────────────
  #
  # Two shapes coexist, and a single student can be in BOTH at once: a venture
  # funded through their school's payment account, and their own business on its
  # own account. The branch is therefore per-VENTURE, never per-user.
  #
  #   * school-shared account — the money sits in the school's Stripe account and
  #     the school settles with the student directly (PayoutRequest::PERSONAL_TRANSFER).
  #     Fuime is not the rail and must not claim to be the debtor.
  #   * own account — Fuime is the seller of record and the payer.
  describe "who owes the money" do
    # `shares_payment_account?` is stubbed rather than built out of a real school
    # tree: the branch under test reads exactly that predicate, and constructing a
    # school, a parent venture and an inherited connected account would test
    # Event#payment_account's resolution instead — which has its own spec
    # (event_school_payment_account_spec.rb).
    it "names Fuime on a venture with its own payment account" do
      sale

      expect(payables.owed_sentence).to match(/Fuime owes you/)
      expect(payables.disclosure).to match(/seller of record/)
    end

    it "names the school, and promises no date, on a school-settled venture" do
      allow(event).to receive(:shares_payment_account?).and_return(true)
      sale

      expect(payables.owed_sentence).to match(/has earned and not yet spent/)
      expect(payables.owed_sentence).to match(/Ask the school to pay it out/)
      expect(payables.owed_sentence).not_to match(/Fuime owes you/)
      # No payout date: the school decides when it pays, and Fuime cannot commit
      # somebody else to a Friday.
      expect(payables.owed_sentence).not_to match(/paid on/)
    end

    it "still refuses deposit vocabulary on the school path" do
      allow(event).to receive(:shares_payment_account?).and_return(true)
      sale

      expect(payables.owed_sentence.downcase).not_to include("balance")
      expect(payables.disclosure).to match(/not a bank balance/)
    end

    # The case the school programme actually produces: one student, two ventures,
    # two different payers, two different sentences.
    it "answers per venture, so a student with both gets the right sentence for each" do
      own_business = create(:event)
      school_venture = create(:event)
      allow(school_venture).to receive(:shares_payment_account?).and_return(true)

      expect(described_class.new(event: own_business).owed_sentence)
        .to match(/Fuime doesn't owe you anything yet/)
      expect(described_class.new(event: school_venture).owed_sentence)
        .to match(/haven't earned anything yet/)
    end
  end
end
