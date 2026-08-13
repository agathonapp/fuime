# frozen_string_literal: true

# Fuime: what Fuime OWES an operator, and why — never "your balance".
#
# ── Why this class exists at all ────────────────────────────────────────────
#
# The distinction it enforces is legal, not cosmetic. Under the umbrella
# merchant-of-record model Fuime LLC is the seller: a customer pays Fuime for a
# sale Fuime made, that money is Fuime's own revenue, and the operator is a vendor
# Fuime pays on a fixed cadence. What the operator has is a RECEIVABLE against
# Fuime — an amount owed, payable on a stated date.
#
# What the operator does NOT have is a balance on deposit. A stored balance the
# holder can withdraw at will is a deposit, and taking deposits without a bank
# charter is the thing Fuime cannot do (CLAUDE.md L1/L5, LEGAL_RESEARCH §3). The
# difference between the two products is almost entirely in how the number is
# framed and what the user can do with it, which means the framing is part of the
# compliance posture and not decoration on top of it.
#
# So: "Fuime owes you $84.20, paid Friday 15 August." Never "your balance is
# $84.20", never a Withdraw button against an indefinitely-held sum.
#
# ── Why a presenter rather than renaming Event#balance ──────────────────────
#
# `Event#balance_v2_cents` and its fourteen relatives are HCB's subledger. The
# arithmetic is right and is reused verbatim here — the sum of an operator's
# ledger lines IS what they are owed. Two reasons not to touch it:
#
#   * 111 files under app/views reference "balance", and `balance`,
#     `available_balance` and `balance_available` are all aliases of it. Renaming
#     is a mechanical change across hundreds of call sites that would break every
#     future merge from hackclub/hcb (CLAUDE.md Rule 6).
#   * The ledger engine is not to be modified, only fed (Rule 3).
#
# This is therefore a thin reframing layer, and the rule that makes it worth
# anything is: OPERATOR-FACING VIEWS CALL THIS AND NOTHING ELSE. A spec enforces
# it. Admin and internal pages may keep saying "balance", because there the word
# is accurate — it is Fuime's own money they are looking at.
#
# ── Why the breakdown always reconciles ────────────────────────────────────
#
# `#net_payable_cents` is authoritative: it is the settled ledger balance, the
# same figure Fuime::PayoutService caps against. The named components (gross
# sales, Fuime's fee, Stripe's fee, refunds, card spend, payouts already made) are
# an EXPLANATION of it, derived by classifying lines by their
# Fuime::VentureLedger key.
#
# Classification is a heuristic over a real ledger, so it can be incomplete —
# school awards, corrections, and anything posted by a path that predates the key
# scheme. `#other_adjustments_cents` is the residual, defined as whatever is left
# over rather than as a category. That makes the breakdown sum to the total by
# construction, so this class can never show a teenager a set of figures that do
# not add up to what they are owed. A residual that grows is a signal that a new
# money path needs naming here; it is not a rounding bin.
#
# See docs/fuime/MOR_MIGRATION_PLAN.md §3.4.
module Fuime
  class PayablesLedger
    # Fuime pays on a fixed cadence, and the cadence is the product.
    #
    # A user-initiated withdrawal of a sum Fuime holds indefinitely is the deposit
    # account this model exists to not be. A scheduled settlement of an invoice is
    # ordinary commerce between a company and its vendors. Same money, different
    # legal object, and the difference is precisely that the operator does not
    # choose the timing.
    #
    # Friday because it is far enough from a weekend that a failed transfer can be
    # retried inside the same week. Weekly by default per the pivot brief.
    PAYOUT_WEEKDAY = :friday

    # ── Line classification ──────────────────────────────────────────────────
    #
    # Every line Fuime posts carries a Fuime::VentureLedger key: on the raw row
    # while pending, and embedded in the memo as "[key]" once settled (see
    # VentureLedger.settled_memo and ConnectSettlementSweep). Keys are the reliable
    # way to ask what a line IS — memo prose is written for humans and changes.
    #
    # Order matters: "fuime_" prefixes every key, so the specific patterns must be
    # tested before the bare payment pattern. `fuime_pi_` is safe as the sale
    # pattern precisely because every other key inserts a word between "fuime_" and
    # the Stripe id.
    GROSS_SALE_PREFIX     = "fuime_pi_"
    FUIME_FEE_PREFIX      = "fuime_fee_"
    PROCESSING_FEE_PREFIX = "fuime_stripefee_"
    REFUND_PREFIX         = "fuime_rev_"
    FEE_REBATE_PREFIX     = "fuime_feerev_"
    PAYOUT_PREFIX         = "fuime_payout_"
    PAYOUT_REVERSAL_PREFIX = "fuime_payoutrev_"
    SCHOOL_PAID_PREFIX    = "fuime_schoolpaid_"
    CARD_SPEND_PREFIX     = "fuime_card_"

    attr_reader :event

    def initialize(event:)
      @event = event
    end

    # ── The headline figure ─────────────────────────────────────────────────

    # What Fuime owes this operator right now, in cents.
    #
    # `Event#balance_v2_cents` deliberately, and the choice is load-bearing rather
    # than incidental. Three candidates and only one is safe:
    #
    #   * settled_balance_cents — settled lines only. Ignores money already
    #     committed but not yet settled, so it OVERSTATES what can be paid.
    #   * balance_v2_cents — settled, plus unsettled OUTGOING commitments, plus
    #     fronted incoming only when fronting is on (it is not; see
    #     Event#can_front_balance?). The conservative figure.
    #   * anything including pending incoming — money Stripe has taken and not
    #     released. Fuime cannot pay out what it has not received; promising it
    #     would be Fuime advancing its own cash against an unsettled sale.
    #
    # The second one, and specifically because `Fuime::PayoutService` caps a payout
    # against exactly this figure. If this page and that cap read different numbers
    # then Fuime tells an operator it owes them $80 and then refuses to send $80,
    # with no sentence available that explains why. One number, read once, in both
    # places.
    #
    # Not clamped: a chargeback after a payout legitimately drives this negative,
    # and a caller deciding whether to claw back needs the real sign.
    # `#amount_owed_cents` is the display-safe version.
    def net_payable_cents
      @net_payable_cents ||= event.balance_v2_cents
    end

    # The same figure floored at zero, for display.
    #
    # "Fuime owes you -$12.40" is not a sentence to show a teenager; owing a
    # negative amount is a debt, and a debt has to be presented as one with an
    # explanation, not as a balance with a minus sign. `#in_arrears?` is how a view
    # asks whether to switch to that copy.
    def amount_owed_cents
      [net_payable_cents, 0].max
    end

    def in_arrears?
      net_payable_cents.negative?
    end

    def arrears_cents
      in_arrears? ? net_payable_cents.abs : 0
    end

    # Money from completed sales that Stripe has not released yet.
    #
    # Shown separately and never added to what is owed, because the honest sentence
    # is "this is coming, it is not payable yet". Conflating the two is how a user
    # concludes Fuime is holding a balance for them.
    def pending_sales_cents
      @pending_sales_cents ||= event.pending_incoming_balance_v2_cents
    end

    # ── The breakdown, which always sums to net_payable_cents ───────────────

    # Customer money attributed to this operator, before any deduction.
    def gross_sales_cents
      @gross_sales_cents ||= settled_sum(GROSS_SALE_PREFIX)
    end

    # Fuime's cut, as a positive number. Observed from the ledger rather than
    # recomputed from a rate, so a plan change can never retroactively disagree
    # with what was actually charged (see Fuime::ConnectPaymentRecorder).
    def fuime_fee_cents
      @fuime_fee_cents ||= (settled_sum(FUIME_FEE_PREFIX) + settled_sum(FEE_REBATE_PREFIX)).abs
    end

    # Stripe's processing fee (~2.9% + 30¢), as a positive number. A separate
    # figure from Fuime's cut because they are two different companies taking two
    # different amounts, and a family reconciling their books needs to see which is
    # which.
    def processing_fee_cents
      @processing_fee_cents ||= settled_sum(PROCESSING_FEE_PREFIX).abs
    end

    # Refunds and chargebacks, as a positive number.
    def refunds_cents
      @refunds_cents ||= settled_sum(REFUND_PREFIX).abs
    end

    # Business spending on a Fuime card, as a positive number. A real expense that
    # reduces what is owed, and deliberately distinct from a payout — one buys the
    # business something, the other moves money to the operator.
    def card_spend_cents
      @card_spend_cents ||= settled_sum(CARD_SPEND_PREFIX).abs
    end

    # Money already paid to this operator, as a positive number. Covers both rails:
    # a Stripe payout, and a transfer a school settled itself.
    def paid_out_cents
      @paid_out_cents ||= (settled_sum(PAYOUT_PREFIX) +
                           settled_sum(PAYOUT_REVERSAL_PREFIX) +
                           settled_sum(SCHOOL_PAID_PREFIX)).abs
    end

    # Money already spent or committed that has not settled yet, as a positive
    # number — a pending card authorisation being the usual case.
    #
    # Named rather than left to the residual because it is the one component that
    # explains a gap between "my sales minus fees" and what Fuime says it owes. An
    # operator looking at a figure $15 lower than their own arithmetic should be
    # able to see the $15 hold that caused it.
    def committed_cents
      @committed_cents ||= event.pending_outgoing_balance_v2_cents.abs
    end

    # Whatever the named categories do not account for.
    #
    # Defined as a residual, not a category: school awards, corrections, and lines
    # posted by any path that predates or postdates the key scheme all land here,
    # so `#breakdown` sums to `#net_payable_cents` by construction. See the class
    # header for why that guarantee is worth more than a tidier taxonomy.
    def other_adjustments_cents
      @other_adjustments_cents ||=
        net_payable_cents - (gross_sales_cents -
                             fuime_fee_cents -
                             processing_fee_cents -
                             refunds_cents -
                             card_spend_cents -
                             paid_out_cents -
                             committed_cents)
    end

    # The whole picture, ordered as it should be read on a page.
    def breakdown
      {
        gross_sales: gross_sales_cents,
        fuime_fee: fuime_fee_cents,
        processing_fee: processing_fee_cents,
        refunds: refunds_cents,
        card_spend: card_spend_cents,
        paid_out: paid_out_cents,
        committed: committed_cents,
        other_adjustments: other_adjustments_cents,
        net_payable: net_payable_cents
      }
    end

    # ── The cadence ─────────────────────────────────────────────────────────

    # The next date Fuime pays out, whether or not anything is owed.
    #
    # Shown unconditionally and even at zero, because the promise is the schedule
    # rather than the amount: an operator who can read "paid every Friday" off the
    # page does not go looking for a withdraw button. Includes today when today is
    # the payout day — `Date#next_occurring` would skip a week, telling somebody on
    # payout morning that their money comes in seven days.
    def next_payout_on(from: Date.current)
      return from if from.strftime("%A").downcase.to_sym == PAYOUT_WEEKDAY

      from.next_occurring(PAYOUT_WEEKDAY)
    end

    # Payouts already made, newest first, for the history table.
    #
    # Reads PayoutRequest rather than ledger lines: the request carries the
    # approval, the destination and any failure reason, which is what somebody
    # asking "where is my money?" actually needs.
    def payout_history
      event.payout_requests.order(created_at: :desc)
    end

    # ── Copy helpers ────────────────────────────────────────────────────────
    #
    # Here rather than in a view so that the one sentence carrying the legal
    # distinction has one definition. A view that interpolates its own wording can
    # drift into "your balance" without anybody noticing in review.

    # Who actually owes this money, which is not always Fuime.
    #
    # On a family venture Fuime is the seller of record and the payer: Fuime owes
    # the operator and Fuime pays them on the cadence. On a school venture the
    # money sits in the SCHOOL's Stripe account, the school settles with the
    # student directly, and Fuime is not the rail at all — see
    # `PayoutRequest::PERSONAL_TRANSFER` and `PayoutService#approve_personal_transfer!`.
    #
    # Saying "Fuime owes you" on that second path would name the wrong debtor and
    # promise a payment Fuime does not make. Two specs caught exactly this.
    def payer_is_school?
      event.shares_payment_account?
    end

    def owed_sentence
      if amount_owed_cents.zero? && !in_arrears?
        return payer_is_school? ? "You haven't earned anything yet." : "Fuime doesn't owe you anything yet."
      end

      if in_arrears?
        return "Your sales have been refunded or disputed by more than you've been paid, " \
               "so #{format_cents(arrears_cents)} will be taken off your next payouts."
      end

      if payer_is_school?
        # No date promised, deliberately: the school decides when it pays, and
        # Fuime cannot commit somebody else to a Friday.
        "#{event.name} has earned and not yet spent #{format_cents(amount_owed_cents)}. " \
          "Ask the school to pay it out to you."
      else
        "Fuime owes you #{format_cents(amount_owed_cents)}, paid on #{next_payout_on.strftime('%A %-d %B')}."
      end
    end

    # The standing clarification about what this page is showing. Deliberately says
    # what the money is NOT.
    def disclosure
      if payer_is_school?
        return "This is what #{event.name} has earned through the school's payment " \
               "account, less fees. It is a record of what you're owed — it is not a " \
               "bank balance, not a deposit, and it is not held for you on account."
      end

      "Fuime is the seller of record for your sales, so payments arrive in Fuime's " \
        "account and Fuime pays you on a fixed schedule. This figure is what Fuime " \
        "owes you — it is not a bank balance, not a deposit, and it is not held for " \
        "you on account."
    end

    private

    # Sum of settled lines whose Fuime ledger key starts with `prefix`.
    #
    # The key is embedded in the memo as "[key]" by VentureLedger.settled_memo, so
    # this matches on that rather than on memo prose.
    #
    # `sanitize_sql_like` is not optional: every key prefix here contains
    # underscores, and `_` is a single-character wildcard in SQL LIKE. Unescaped,
    # "fuime_fee_" would also match "fuimeXfeeY" — harmless today only by luck.
    def settled_sum(prefix)
      escaped = ActiveRecord::Base.sanitize_sql_like(prefix)

      event.canonical_transactions
           .where("canonical_transactions.memo LIKE ?", "%[#{escaped}%")
           .sum(:amount_cents)
    end

    def format_cents(cents)
      ApplicationController.helpers.render_money(cents)
    end

  end
end
