# frozen_string_literal: true

# Fuime: Tax Tracker service
#
# Computes an ESTIMATE of a business's net income for the year and compares it
# to the IRS self-employment filing threshold.
#
# IMPORTANT — this is an estimate, not tax advice, and every caller must present
# it that way. Known limitations, all of which affect the number:
#
#   * Income is classified by heuristic (see #income_cents). A ledger is not a
#     chart of accounts; owner deposits, transfers, and corrections are excluded
#     on a best-effort basis only.
#   * Stripe processing fees are deducted only where they appear as ledger
#     lines. Fees withheld before settlement may not appear at all.
#   * State income tax, sales tax, and 1099-K reporting are not modelled.
#   * Quarterly estimated payments are surfaced as a warning but not computed.
#
# A CPA has NOT yet reviewed these calculations
# (docs/fuime/PRODUCTION_READINESS.md §1.6).
module Fuime
  class TaxTrackerService
    # A taxpayer owes self-employment tax once NET EARNINGS reach $400.
    # Net earnings are net profit x 92.35% (the deduction for the employer-
    # equivalent half of SE tax) — IRS Schedule SE. Comparing raw net profit to
    # $400, as this previously did, told businesses between $400 and ~$433 that
    # they owed when they may not.
    SELF_EMPLOYMENT_THRESHOLD_CENTS = 400_00
    NET_EARNINGS_MULTIPLIER = BigDecimal("0.9235")

    # Net profit at which net earnings reach the threshold: 400 / 0.9235 ≈ $433.14
    NET_PROFIT_FILING_THRESHOLD_CENTS =
      (SELF_EMPLOYMENT_THRESHOLD_CENTS / NET_EARNINGS_MULTIPLIER).ceil

    attr_reader :event, :year

    def initialize(event:, year: nil)
      @event = event
      @year = year || Date.current.year
    end

    # --- Period ---------------------------------------------------------------

    def period_start
      Date.new(year, 1, 1)
    end

    def period_end
      Date.new(year, 12, 31)
    end

    # --- Core figures ---------------------------------------------------------

    # Business revenue for the year.
    #
    # Only positive lines that look like actual customer revenue count. A raw
    # "every positive line" sum counted owner deposits, transfers between a
    # teen's own accounts, and refund reversals as taxable income.
    def income_cents
      @income_cents ||= taxable_transactions
                        .where("amount_cents > 0")
                        .sum(:amount_cents)
    end

    # Deductible business expenses for the year, as a positive number.
    def expenses_cents
      @expenses_cents ||= taxable_transactions
                          .where("amount_cents < 0")
                          .sum(:amount_cents)
                          .abs
    end

    # Net profit (Schedule C bottom line, approximately).
    def net_income_cents
      @net_income_cents ||= income_cents - expenses_cents
    end

    # Net EARNINGS from self-employment — the figure the $400 test applies to.
    def net_earnings_cents
      return 0 if net_income_cents <= 0

      (net_income_cents * NET_EARNINGS_MULTIPLIER).floor
    end

    # --- Threshold ------------------------------------------------------------

    def over_threshold?
      net_earnings_cents >= SELF_EMPLOYMENT_THRESHOLD_CENTS
    end

    # Progress toward the threshold (0.0 to 1.0+), measured on net earnings so
    # the bar and the verdict can never disagree.
    def threshold_progress
      return 0.0 if net_earnings_cents <= 0

      net_earnings_cents.to_f / SELF_EMPLOYMENT_THRESHOLD_CENTS
    end

    def threshold_percentage
      [(threshold_progress * 100).round, 100].min
    end

    # Remaining net PROFIT before the filing threshold is reached.
    def cents_until_threshold
      [NET_PROFIT_FILING_THRESHOLD_CENTS - net_income_cents, 0].max
    end

    # --- Presentation ---------------------------------------------------------

    # Deliberately hedged: Fuime is not a tax preparer and must not state
    # obligations as fact.
    def status_message
      if net_income_cents < 0
        "Your business shows a net loss this year, so you likely won't owe " \
          "self-employment tax. A loss may still be worth reporting — check with a tax professional."
      elsif over_threshold?
        "Your estimated net earnings are above the $400 IRS self-employment " \
          "threshold, so you'll likely need to file. Share the year-end packet " \
          "below with a parent or guardian and a tax professional."
      else
        remaining = cents_until_threshold / 100.0
        "You're under the $400 IRS filing threshold based on your Fuime ledger. " \
          "About $#{'%.2f' % remaining} of additional profit would reach it — we're watching it for you."
      end
    end

    # Teens crossing the threshold usually need to make quarterly estimated
    # payments, which is more urgent than the April filing and easy to miss.
    def quarterly_estimates_warning
      return nil unless over_threshold?

      "Because you're over the threshold, you may also need to make quarterly " \
        "estimated tax payments rather than paying once a year. Ask a tax " \
        "professional which applies to you."
    end

    def disclaimer
      "This is an automated estimate based only on the transactions recorded in " \
        "your Fuime ledger. It is not tax advice, and it may not reflect all of " \
        "your income, deductions, or state requirements. Please review it with a " \
        "parent or guardian and a qualified tax professional."
    end

    # --- Packet ---------------------------------------------------------------

    def year_end_packet
      {
        business_name: event.name,
        year: year,
        total_income: income_cents / 100.0,
        total_expenses: expenses_cents / 100.0,
        net_income: net_income_cents / 100.0,
        net_earnings: net_earnings_cents / 100.0,
        threshold: SELF_EMPLOYMENT_THRESHOLD_CENTS / 100.0,
        net_profit_filing_threshold: NET_PROFIT_FILING_THRESHOLD_CENTS / 100.0,
        over_threshold: over_threshold?,
        estimate_only: true,
        disclaimer: disclaimer,
        generated_at: Time.current.iso8601
      }
    end

    private

    # Ledger lines that plausibly represent business income or expense.
    #
    # Heuristic and deliberately conservative on the income side: anything we
    # can identify as a non-revenue inflow is excluded, because overstating a
    # teenager's taxable income is the more harmful error.
    def taxable_transactions
      scope = event.canonical_transactions.where(date: period_start..period_end)

      excluded = EXCLUDED_MEMO_PATTERNS.map { |p| "%#{ActiveRecord::Base.sanitize_sql_like(p)}%" }
      excluded.each do |pattern|
        scope = scope.where.not("LOWER(canonical_transactions.memo) LIKE ?", pattern)
      end

      scope
    end

    # Memo fragments that indicate a non-revenue movement. Matched
    # case-insensitively as substrings.
    #
    # This is a stopgap. The durable fix is to classify transactions explicitly
    # at ingestion rather than pattern-match free text after the fact.
    EXCLUDED_MEMO_PATTERNS = [
      "transfer",
      "disbursement",
      "reimbursement",
      "refunded payment",
      "disputed payment",
      "owner deposit",
      "initial balance",
      "correction",
      # The rebate of Fuime's fee on a refunded payment. It is a reversal of an
      # expense, not revenue — counting it as income would inflate the tax
      # figure shown to a teen's family. Must precede "adjustment" in intent:
      # the fee CHARGE (memo "Fuime platform fee (4%)") is deliberately NOT
      # excluded, because it is a genuine deductible business expense.
      "platform fee refunded",
      # Money moving from the venture's Stripe balance to the family's own bank
      # account. Neither income nor a deductible expense — the business already
      # earned it (and it was already counted as income when the sale posted), and
      # sending it to the owner's bank does not spend it on anything. Counting a
      # payout as an expense would understate a teenager's taxable income, which
      # is the direction of error that gets a family in trouble.
      "payout",
      # Money a school moved into a student's venture — Alpha School's "$100 per A",
      # and the reversal of one. Excluded on BOTH sides, which is why every award memo
      # contains this phrase (see Fuime::SchoolAwardService).
      #
      # Only sales belong in this figure. An award is not revenue the business earned:
      # to the venture it is a capital contribution, which never appears on Schedule C
      # at all, and counting it would inflate the profit a family is told to pay
      # self-employment tax on. The school's own debit is excluded for the mirror
      # reason — it did not buy the school anything.
      #
      # The student's PERSONAL exposure is real but belongs nowhere near this
      # calculation: cash for grades is a taxable prize under IRC § 74, not a
      # qualified scholarship under § 117, and at six A's the school crosses the $600
      # 1099-MISC threshold. That is the school's filing obligation against the
      # student's own return, not the venture's business income, and mixing the two
      # would produce a number wrong for both.
      "school award",
      "adjustment",
    ].freeze

  end
end
