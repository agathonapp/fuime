# frozen_string_literal: true

# Fuime: move money from a school's subledger into a student's venture.
#
# The mirror image of Fuime::PayoutService, and deliberately much simpler, because
# nothing leaves the Stripe account. The school and every venture beneath it share
# one account (Event#payment_account), so an award is two ledger lines that cancel:
# the school's balance falls, the student's rises, the total is unchanged, and Stripe
# is never called. Fuime is not in the flow of funds because no funds flow.
#
# ── The one rule that matters ────────────────────────────────────────────────
#
# The school must have the money. Fuime::PayoutService caps a student's withdrawal at
# `min(stripe_available, venture_ledger_balance)`, so an award the school cannot fund
# would hand a student a balance backed by *other students'* sales — and they could
# withdraw it. Refusing an unfunded award is what keeps the pool backing the sum of
# its parts, and it is checked here rather than in the model because it depends on a
# balance that changes between reads.
#
# ── Why both lines are settled, and posted together ─────────────────────────
#
# Settled, not pending: the money is already available in the school's balance, and
# there is no Stripe event to wait for. A pending credit would also be invisible to
# `Event#balance_v2_cents`, which excludes pending incoming money — so the student
# would be awarded $100 they could not see or spend. See
# Fuime::VentureLedger#post_settled!.
#
# Together, in one transaction: a half-posted award either invents money or destroys
# it. Both sides share a key prefix so a crash between them resumes rather than
# double-posting, and `find_settled_row` makes the retry a no-op on whichever side
# already landed.
module Fuime
  class SchoolAwardService
    class Error < StandardError; end
    class NotASchoolVenture < Error; end
    class SchoolUnderfunded < Error; end

    # Memos both contain "school award" on purpose: Fuime::TaxTrackerService excludes
    # non-revenue movements by memo substring, and an award is not a sale. It is a
    # capital contribution into the business and personal award income to the student,
    # so it must not touch the venture's Schedule C estimate on either side.
    CREDIT_MEMO_PREFIX = "School award from"
    DEBIT_MEMO_PREFIX = "School award to"

    def initialize(venture:)
      @venture = venture
    end

    # The school whose account holds this venture's money, or nil.
    def school
      @school ||= @venture.payment_account&.event
    end

    # What the school has left to award, in cents.
    #
    # The school's own ledger balance, floored at zero. Not Stripe's balance: that is
    # the whole programme's, most of which is students' own sales revenue and none of
    # which is the school's to give away.
    def available_to_award_cents
      return 0 if school.blank?

      [school.balance_v2_cents, 0].max
    end

    def grant!(amount_cents:, awarded_to:, awarded_by:, reference: nil, awarded_on: nil)
      amount_cents = amount_cents.to_i

      unless @venture.shares_payment_account?
        raise NotASchoolVenture,
              "#{@venture.name} isn't part of a school programme, so a school can't fund it."
      end

      available = available_to_award_cents
      if amount_cents > available
        raise SchoolUnderfunded,
              "#{school.name} has #{format_cents(available)} available to award, " \
              "which is less than the #{format_cents(amount_cents)} requested. " \
              "Add funds to the programme's payment account first."
      end

      award = nil

      ActiveRecord::Base.transaction do
        award = SchoolAward.create!(
          event: @venture,
          school_event: school,
          awarded_to:,
          awarded_by:,
          amount_cents:,
          reference: reference.presence,
          awarded_on: awarded_on.presence || Date.current
        )

        post_pair!(
          award:,
          amount_cents:,
          debit_key: VentureLedger.award_key(award.id, "out"),
          credit_key: VentureLedger.award_key(award.id, "in"),
          debit_memo: "#{DEBIT_MEMO_PREFIX} #{awarded_to.first_name}",
          credit_memo: "#{CREDIT_MEMO_PREFIX} #{school.name}",
          date: award.awarded_on
        )

        Rails.logger.info(
          "[Fuime] school award #{award.id}: #{format_cents(amount_cents)} from " \
          "event #{school.id} to event #{@venture.id} for user #{awarded_to.id}, " \
          "granted by user #{awarded_by.id}"
        )
      end

      award
    end

    # Take an award back, by posting the opposite pair.
    #
    # Not a destroy, and not a check that the student still has the money: the award
    # did happen, and if they have already spent it the venture goes negative, which
    # is the truth and is the same shape as a chargeback. Erasing the original lines
    # would misstate what the balance did and when.
    def void!(award:, voided_by:, reason: nil)
      raise Error, "This award has already been voided." if award.voided?

      ActiveRecord::Base.transaction do
        award.update!(voided_at: Time.current, voided_by:, void_reason: reason.presence)

        post_pair!(
          award:,
          amount_cents: award.amount_cents,
          # Reversed: the money goes back to the school.
          debit_key: VentureLedger.award_void_key(award.id, "out"),
          credit_key: VentureLedger.award_void_key(award.id, "in"),
          debit_memo: "School award returned by #{award.awarded_to.first_name}",
          credit_memo: "School award reversed",
          date: Date.current,
          debit_event: @venture,
          credit_event: school
        )

        Rails.logger.info(
          "[Fuime] school award #{award.id} voided by user #{voided_by.id}"
        )
      end

      award
    end

    private

    # The two halves of one movement. Debit first, so a failure to credit leaves
    # money parked rather than duplicated.
    def post_pair!(award:, amount_cents:, debit_key:, credit_key:, debit_memo:, credit_memo:, date:,
                   debit_event: nil, credit_event: nil)
      debit_event ||= school
      credit_event ||= @venture

      VentureLedger.new(event: debit_event).post_settled!(
        key: debit_key, amount_cents: -amount_cents, memo: debit_memo, date:
      )

      VentureLedger.new(event: credit_event).post_settled!(
        key: credit_key, amount_cents: amount_cents, memo: credit_memo, date:
      )
    end

    def format_cents(cents)
      ActiveSupport::NumberHelper.number_to_currency(cents.to_i / 100.0)
    end

  end
end
