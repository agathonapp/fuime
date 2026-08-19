# frozen_string_literal: true

# Fuime: what one operator gets paid in one run, and — when the answer is nothing —
# which sentence explains why.
#
# Split out of Fuime::PayoutBatchBuilder rather than living inside it because this
# is the arithmetic somebody will one day have to defend to an operator, to a
# founder deciding whether the dials are right, or to an examiner asking how Fuime
# decides what it owes. It is testable on its own, it performs no writes, and
# nothing here knows a batch exists.
#
# ── The four numbers, in the order they apply ───────────────────────────────
#
#   payable   what Fuime owes at all       PayablesLedger#net_payable_cents
#   aged      …that has sat long enough    settled lines dated <= cutoff
#   committed …not already promised        pending + approved requests
#   reserve   …less the rolling reserve    % of trailing gross
#
# Then the cap, then the floor. Each step can only reduce the figure, which is the
# property that matters: there is no ordering of these rules that pays an operator
# more than Fuime owes them.
#
# ── Why `aged` is a MIN and not a substitution ──────────────────────────────
#
# The hold period wants "money that settled at least N days ago". The obvious
# implementation sums ledger lines dated on or before the cutoff — but that
# excludes recent DEDUCTIONS as well as recent income. An operator who took $500
# on 1 August and was refunded $400 on 14 August would, on a 7-day hold on 15
# August, show $500 aged and be paid $500 they no longer have.
#
# So the aged figure is not used as the payable. It is used as a CEILING on it:
#
#   eligible = min(what is owed now, what had settled by the cutoff)
#
# Recent deductions bite immediately through the first term; recent income cannot
# inflate the answer through the second. Same shape as
# Fuime::PayoutService#available_balance_cents' pooled-account cap, and for the
# same reason — when two sources both bound a figure, take both.
module Fuime
  class PayableAssessment
    # A payout line that should exist, or a documented reason there is none.
    #
    # `skip_reason` is prose rather than a symbol because every one of these is
    # shown to somebody: on the batch review page to the admin approving the run,
    # and in the batch's own record afterwards. A run where 40 of 50 operators
    # were skipped is either correct or a bug, and the difference is only legible
    # if each skip says which.
    Result = Struct.new(
      :event,
      :payable_cents,
      :aged_cents,
      :committed_cents,
      :trailing_gross_cents,
      :reserve_target_cents,
      :eligible_cents,
      :amount_cents,
      :capped,
      :skip_reason,
      keyword_init: true
    ) do
      def payable?
        skip_reason.blank?
      end

      # What was withheld on this line, as a positive number. The reserve, plus
      # anything the cap held back — both are money owed and not paid this week,
      # and an operator reading their payout wants one figure for that.
      def withheld_cents
        return 0 unless payable?

        [eligible_cents - amount_cents, 0].max
      end

      def capped?
        capped.present?
      end
    end

    attr_reader :event, :policy, :period_end

    def initialize(event:, policy:, period_end:)
      @event = event
      @policy = policy
      @period_end = period_end.to_date
    end

    def call
      # Returned before any of the money queries run. An operator Fuime does not
      # pay has no meaningful reserve target or aged balance, and computing four
      # sums per skipped venture is the difference between a batch that generates
      # in seconds and one that does not.
      if structural_skip_reason
        return Result.new(
          event:,
          payable_cents: 0, aged_cents: 0, committed_cents: 0,
          trailing_gross_cents: 0, reserve_target_cents: 0,
          eligible_cents: 0, amount_cents: 0, capped: false,
          skip_reason: structural_skip_reason
        )
      end

      eligible = [payable_cents, aged_cents].min - committed_cents - reserve_target_cents

      if eligible < policy.minimum_cents
        return result(eligible_cents: eligible, amount_cents: 0, capped: false,
                      skip_reason: below_floor_reason(eligible))
      end

      amount = [eligible, policy.maximum_cents].min

      result(eligible_cents: eligible, amount_cents: amount, capped: amount < eligible)
    end

    private

    # Reasons that have nothing to do with the arithmetic — the operator is not
    # somebody Fuime pays at all this week.
    #
    # Memoised including the nil, because `call` asks twice and each check is a
    # query.
    def structural_skip_reason
      return @structural_skip_reason if defined?(@structural_skip_reason)

      @structural_skip_reason = compute_structural_skip_reason
    end

    def compute_structural_skip_reason
      # A venture inside a school programme is paid BY THE SCHOOL, out of the
      # school's own Stripe account, through PayoutRequest::PERSONAL_TRANSFER.
      # Fuime is the system of record there and not the payer, so including one in
      # a Fuime payout run would promise money Fuime does not send — the exact
      # wrong-debtor bug PayablesLedger#payer_is_school? exists to prevent.
      return "Paid by the school, not by Fuime." if event.shares_payment_account?

      # Vetting binds always (see the 2026-08-14 handoff). An operator nobody has
      # approved should not have taken money in the first place; if they somehow
      # have, a payout run is not the place that gets discovered quietly.
      unless event.operator_vetting_approved?
        return "Not approved to trade (#{event.operator_vetting_status.humanize.downcase})."
      end

      return "Payments are frozen on this venture." if event.financially_frozen?

      # Under merchant-of-record Fuime owes this operator money and needs
      # somewhere to send it. Generating a line for a venture with no verified
      # destination would put an amount in an approved run that nobody can
      # actually pay — and the batch's whole value is that a human reads it and
      # every line on it is actionable.
      #
      # Only under MoR: on the Connect path the money is already in the family's
      # own Stripe account and the destination is Stripe's business, not Fuime's.
      if ::Fuime::Features.merchant_of_record? && event.fuime_payout_methods.usable.none?
        return "No payout destination set up yet."
      end

      # THE guardian gate under merchant-of-record (L2).
      #
      # It used to sit in Fuime::OperatorEligibility, blocking a minor from
      # selling at all. It was moved here on 2026-08-16 — read that class's
      # #umbrella_scope_blockers for the full argument, including what the move
      # costs. The short version: under MoR a teenager selling incurs no
      # obligation and holds no account, so the adult is not needed yet; a
      # teenager being PAID has a payee, a tax consequence and a debt that can run
      # negative, so the adult is needed now.
      #
      # Deliberately the last structural check, so a venture missing both a parent
      # and a destination is told about the destination first — that is the one
      # the operator can fix themselves, and a run that reports the unfixable
      # blocker first reads as a wall.
      #
      # Checked per operator rather than via Event#has_overseeing_guardian?, which
      # is satisfied by ONE guardian even when a second co-founder has none. Money
      # is about to be sent on behalf of every one of them.
      if ::Fuime::Features.merchant_of_record?
        unguarded = event.users.select { |u| u.minor_or_unknown_age? && !u.has_active_guardian? }

        if unguarded.any? && !event.institutionally_sponsored?
          return "Needs a parent or guardian on the account before money can be sent " \
                 "(#{unguarded.map(&:name).join(', ')})."
        end
      end

      nil
    end

    # Which term pushed this operator under the floor.
    #
    # Each branch asks the same question of a different term: would this operator
    # have cleared the minimum but for THIS deduction? That is a stronger test than
    # "is this term non-zero", which would name the reserve on an operator who is
    # simply owed nothing. Ordered by what the reader can act on — waiting out a
    # hold is a different sentence from a reserve that will not move this week.
    def below_floor_reason(eligible)
      return "Nothing owed." if payable_cents <= 0

      if aged_cents < payable_cents
        return "Recent sales haven't cleared the #{policy.hold_days}-day hold yet."
      end

      if reserve_target_cents.positive? && (eligible + reserve_target_cents) >= policy.minimum_cents
        return "Held as reserve (#{format_cents(reserve_target_cents)} of trailing sales)."
      end

      if committed_cents.positive? && (eligible + committed_cents) >= policy.minimum_cents
        return "Already committed to an earlier run (#{format_cents(committed_cents)})."
      end

      "Below the #{format_cents(policy.minimum_cents)} minimum — rolls into the next run."
    end

    # What Fuime owes, full stop. Can be negative; the arithmetic above handles it
    # and `below_floor_reason` names it.
    def payable_cents
      @payable_cents ||= payables.net_payable_cents
    end

    # Settled money as at the cutoff. Clamped at zero: a negative aged figure means
    # the operator's early ledger is underwater, which the `min` would then treat
    # as a ceiling below zero — correct, but "eligible = -$40" reads as a debt to
    # collect rather than an absence of money to send. The debt is real and lives
    # in `payable_cents`; this term only ever caps.
    def aged_cents
      @aged_cents ||= [
        event.canonical_transactions
             .where(canonical_transactions: { date: ..policy.eligibility_cutoff(period_end) })
             .sum(:amount_cents),
        0
      ].max
    end

    # Money already promised in a run that has not paid out.
    #
    # `pending` and `approved` only. A `paid` line has had its ledger debit posted
    # by Fuime::PayoutBatch#mark_paid!, so it is already reflected in
    # `payable_cents` and counting it here would deduct it twice. A `failed` line
    # is money that did not go and is still owed, so it is deliberately not
    # committed to anything.
    def committed_cents
      @committed_cents ||= event.payout_requests
                                .where(aasm_state: %w[pending approved])
                                .sum(:amount_cents)
    end

    # Gross customer money attributed to this operator inside the reserve window.
    #
    # Gross rather than net: the reserve covers the risk that a SALE is reversed,
    # and a customer disputing a $100 charge takes $100 back regardless of what
    # Fuime's cut of it was.
    def trailing_gross_cents
      @trailing_gross_cents ||= PayablesLedger.settled_sum_for(
        event:,
        prefix: PayablesLedger::GROSS_SALE_PREFIX,
        on_or_after: policy.reserve_window_start(period_end),
        on_or_before: period_end
      )
    end

    def reserve_target_cents
      @reserve_target_cents ||= policy.reserve_target_cents(trailing_gross_cents)
    end

    def payables
      @payables ||= PayablesLedger.new(event:)
    end

    # An arithmetic outcome — paid or skipped — reported with every figure that
    # produced it. A skip here still carries the numbers, because "skipped" without
    # them is exactly the un-auditable answer this class exists to not give.
    def result(eligible_cents:, amount_cents:, capped:, skip_reason: nil)
      Result.new(
        event:,
        payable_cents:,
        aged_cents:,
        committed_cents:,
        trailing_gross_cents:,
        reserve_target_cents:,
        eligible_cents:,
        amount_cents:,
        capped:,
        skip_reason:
      )
    end

    def format_cents(cents)
      ActiveSupport::NumberHelper.number_to_currency(cents.to_i / 100.0)
    end

  end
end
