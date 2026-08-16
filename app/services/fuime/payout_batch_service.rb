# frozen_string_literal: true

# Fuime: generate a weekly payout run, put it in front of a human, and record the
# money going out.
#
# The counterpart to Fuime::PayoutService, which handles the Connect world where a
# teen asks and a guardian decides. Here nobody asks: the schedule generates the
# run, an admin reviews it, and the operator's only involvement is being paid.
# That difference is the product's compliance posture rather than a UX choice — an
# operator who cannot choose when they are paid does not hold a balance on demand
# (CLAUDE.md L1/L5, and Fuime::PayablesLedger's header).
#
# ── Division of labour ──────────────────────────────────────────────────────
#
#   Fuime::PayoutPolicy        the dials
#   Fuime::PayableAssessment   what one operator is owed, and why
#   Fuime::PayoutBatch         the record and its state machine
#   this class                 the run: candidate selection, writes, the ledger
#
# ── Why generation is idempotent on the period ──────────────────────────────
#
# A weekly job, a retry, an admin clicking "generate" while the job is running:
# all three produce a second call for the same period, and a second batch would
# mean an operator paid twice for one week. The unique index on `period_end`
# (live batches only) is the real guarantee; the lookup here is what turns a
# race into a no-op instead of an exception.
module Fuime
  class PayoutBatchService
    class Error < StandardError; end
    class NotPermitted < Error; end
    class WrongState < Error; end

    # Ventures Fuime could conceivably owe money to.
    #
    # Deliberately wide: everything not hidden and not a demo, with the real
    # filtering done per-venture by Fuime::PayableAssessment so that each exclusion
    # comes with a stated reason rather than being invisible in a scope. At launch
    # scale (tens of operators) the cost of assessing an ineligible venture is one
    # cheap predicate; if that stops being true the structural skips move into this
    # scope and the reasons move into the batch notes wholesale.
    def self.candidates
      ::Event.not_hidden.not_demo_mode
    end

    # Generate the draft run for a period, or return the one already there.
    #
    # `period_end` is the cutoff for what the run may consider; `payout_on` is when
    # it is meant to go out, defaulting to the next payout weekday. Both are
    # parameters rather than derived so a run can be generated for last week after
    # a missed job without lying about which week it settles.
    def generate!(period_end: Date.current, payout_on: nil, generated_by: nil)
      ::Fuime::Features.merchant_of_record!

      period_end = period_end.to_date
      existing = ::Fuime::PayoutBatch.live.find_by(period_end:)
      return existing if existing

      policy = ::Fuime::PayoutPolicy.current
      assessments = assess_all(policy:, period_end:)
      payable = assessments.select(&:payable?)

      ::Fuime::PayoutBatch.transaction do
        batch = ::Fuime::PayoutBatch.create!(
          period_start: previous_period_end(period_end) + 1,
          period_end:,
          payout_on: payout_on&.to_date || default_payout_on(period_end),
          notes: skip_summary(assessments),
          **policy.attributes_for_batch
        )

        payable.each { |assessment| create_line!(batch:, assessment:) }

        Rails.logger.info(
          "[Fuime] payout batch #{batch.id} generated for period ending #{period_end}: " \
          "#{payable.size} line(s), #{assessments.size - payable.size} skipped" \
          "#{" by user #{generated_by.id}" if generated_by}"
        )

        batch
      end
    rescue ActiveRecord::RecordNotUnique
      # Lost the race to a concurrent generator. Its batch is the batch.
      ::Fuime::PayoutBatch.live.find_by(period_end:)
    end

    # A human has read the run and says yes. No money moves here — see
    # Fuime::PayoutBatch's header.
    def approve!(batch:, approver:)
      raise WrongState, "This run has already been #{batch.aasm_state}." unless batch.draft?
      raise NotPermitted, "Only a Fuime admin can approve a payout run." unless approver&.admin?

      ::Fuime::PayoutBatch.transaction do
        batch.approved_by = approver
        batch.approved_at = Time.current
        batch.approve!
        batch.save!

        # The lines follow the run. Each carries the approver so a line read on its
        # own still says who released it, which is what somebody auditing one
        # operator's payment history actually opens.
        batch.payout_requests.where(aasm_state: "pending").find_each do |request|
          request.approved_by = approver
          request.approved_at = Time.current
          request.approve!
          request.save!
        end

        batch
      end
    end

    # The transfers have gone out, and the ledger follows them.
    #
    # The only place a batch line debits an operator's ledger. Keyed per line
    # through Fuime::VentureLedger, so a retry after a partial failure resumes
    # rather than double-posting — the same idempotency the school-settlement path
    # relies on.
    def mark_paid!(batch:, paid_by:)
      raise WrongState, "Only an approved run can be marked as paid." unless batch.approved?
      raise NotPermitted, "Only a Fuime admin can mark a payout run as paid." unless paid_by&.admin?

      ::Fuime::PayoutBatch.transaction do
        batch.paid_by = paid_by
        batch.paid_at = Time.current
        batch.mark_paid!
        batch.save!

        batch.payout_requests.where(aasm_state: "approved").find_each do |request|
          post_ledger_debit!(request)
          request.paid_at = Time.current
          request.mark_paid!
          request.save!
        end

        Rails.logger.info(
          "[Fuime] payout batch #{batch.id} marked paid by user #{paid_by.id}: " \
          "#{batch.operator_count} line(s)"
        )

        batch
      end
    end

    # Stop a run. Its lines are rejected rather than deleted, because a line that
    # existed and was pulled is a fact somebody may need to explain, and a deleted
    # row explains nothing.
    def cancel!(batch:, cancelled_by:, reason: nil)
      raise WrongState, "This run has already been #{batch.aasm_state}." if batch.paid? || batch.cancelled?
      raise NotPermitted, "Only a Fuime admin can cancel a payout run." unless cancelled_by&.admin?

      ::Fuime::PayoutBatch.transaction do
        batch.cancelled_at = Time.current
        batch.cancellation_reason = reason.presence
        batch.cancel!
        batch.save!

        batch.payout_requests.where(aasm_state: %w[pending approved]).find_each do |request|
          request.rejected_at = Time.current
          request.rejection_reason = reason.presence || "The payout run was cancelled."
          # #cancel_from_run rather than #reject: a line on an approved run is
          # `approved`, and #reject cannot leave that state by design. See the
          # AASM block in PayoutRequest for why the two are separate events.
          request.cancel_from_run!
          request.save!
        end

        batch
      end
    end

    private

    def assess_all(policy:, period_end:)
      self.class.candidates.map do |event|
        ::Fuime::PayableAssessment.new(event:, policy:, period_end:).call
      end
    end

    def create_line!(batch:, assessment:)
      ::PayoutRequest.create!(
        event: assessment.event,
        payout_batch: batch,
        requested_by: nil,
        amount_cents: assessment.amount_cents,
        eligible_cents: assessment.eligible_cents,
        reserve_held_cents: assessment.reserve_target_cents,
        destination: ::PayoutRequest::FUIME_VENDOR_PAYMENT
      )
    end

    # `post_settled!`, not `post!`, and the distinction is load-bearing.
    #
    # A pending line is money in transit that something will later promote —
    # Fuime::ConnectSettlementSweep does that for Stripe charges when Stripe says
    # the funds are available. There is no such event here: Fuime paid its own
    # vendor from its own money, a human has asserted it went, and no third party
    # will ever tell Fuime anything more about it.
    #
    # Posted pending it would sit unsettled forever — the sweep matches only
    # payment and refund key shapes, so it would never look at this one — and the
    # debit would live in Fuime::PayablesLedger#committed_cents permanently,
    # telling an operator their paid money was still "committed". A spec asserts
    # the paid-out figure moves, which is what caught this.
    def post_ledger_debit!(request)
      ::Fuime::VentureLedger.new(event: request.event).post_settled!(
        key: ::Fuime::VentureLedger.batch_payout_key(request.id),
        amount_cents: -request.amount_cents,
        memo: "Fuime payout — #{request.payout_batch.payout_on.strftime('%-d %b %Y')}",
        date: Date.current
      )
    end

    # The period a run covers starts the day after the previous run's cutoff, so
    # consecutive runs tile the calendar with no gap and no overlap. With no
    # previous run it is one payout interval back, which is the honest answer for a
    # first run: everything up to the cutoff, however long that has been accruing.
    def previous_period_end(period_end)
      ::Fuime::PayoutBatch.live
                          .where(period_end: ...period_end)
                          .maximum(:period_end) || (period_end - 7)
    end

    def default_payout_on(period_end)
      ::Fuime::PayablesLedger.next_payout_on(from: period_end)
    end

    # Why the operators who are not in this run are not in it.
    #
    # Written onto the batch rather than dropped, because "38 operators, 6 lines"
    # is either correct or a serious bug and a reviewer cannot tell which without
    # the reasons. Grouped and counted rather than listed per venture: the shape of
    # the skips is the signal, and a wall of names is not read.
    def skip_summary(assessments)
      skipped = assessments.reject(&:payable?)
      return "All #{assessments.size} venture(s) assessed produced a payable line." if skipped.empty?

      counts = skipped.group_by(&:skip_reason).transform_values(&:size)
      lines = counts.sort_by { |_reason, count| -count }
                    .map { |reason, count| "#{count} × #{reason}" }

      "#{skipped.size} of #{assessments.size} venture(s) produced no line:\n" + lines.join("\n")
    end

  end
end
