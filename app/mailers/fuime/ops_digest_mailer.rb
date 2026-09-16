# frozen_string_literal: true

module Fuime
  # Fuime: one email a morning saying what is waiting, and what happened.
  #
  # ── Why this exists next to AdminMailer#reminders ───────────────────────────
  #
  # That one is upstream HCB's and enumerates OPDRs, ACH transfers, Increase
  # checks and reimbursement reports. Every one of those modules is disabled on
  # Fuime, so it has been sending an empty task list every morning at 7am UTC —
  # an alert that is always empty teaches its reader to ignore it, which is worse
  # than no alert. It is left alone rather than rewritten, per Rule 8, so upstream
  # fixes to it still merge.
  #
  # This is the Fuime half: the queues where a human being standing still means a
  # real person is stuck.
  #
  #   * Nobody can sell until an operator is vetted. That queue is directly in
  #     front of every new founder, and at public-launch volume it is the first
  #     thing to fall behind.
  #   * A dispute nobody answers by its deadline is lost by default, and Fuime
  #     pays it (Fuime::Dispute).
  #   * A deletion request has a response window Fuime promised a parent in
  #     writing (Fuime::DataRequest).
  #   * A payout run that is generated and not approved is a week where families
  #     are not paid.
  #
  # ── It sends even when everything is zero, deliberately ─────────────────────
  #
  # An absent email is ambiguous: it means "nothing to do" and "the worker is
  # down" and "the SMTP credential expired" equally well, and the last two are
  # the ones you need to know about on a launch week. A one-line all-clear is
  # cheap and its absence is then informative.
  class OpsDigestMailer < ApplicationMailer
    def daily
      @generated_at = Time.current

      @vetting_waiting = ::Event.not_hidden.operator_vetting_unvetted.count
      @applications_waiting = ::Event::Application.under_review.count
      @stale_guardian_invites = ::Guardianship.stale_pending.count
      @disputes_actionable = ::Fuime::Dispute.actionable.count
      @disputes_overdue = ::Fuime::Dispute.actionable.select(&:overdue?).size
      @deletion_requests = ::Fuime::DataRequest.needs_action.count
      @deletion_overdue = ::Fuime::DataRequest.needs_action.select(&:overdue?).size
      @payout_runs_waiting = ::Fuime::PayoutBatch.awaiting_approval.count + ::Fuime::PayoutBatch.awaiting_payment.count

      # Not a queue — the heartbeat. Zero sales on a launch week is either a
      # quiet day or a broken checkout, and those look identical from every
      # other line in this mail.
      sales = ::Fuime::Sale.where(occurred_at: 24.hours.ago..)
      @sales_count = sales.count
      @sales_cents = sales.sum(:amount_cents)

      @needs_action = @vetting_waiting + @applications_waiting + @disputes_actionable +
                      @deletion_requests + @payout_runs_waiting

      mail(
        to: ApplicationMailer.ops_recipients,
        subject: subject_line
      ) do |format|
        format.html
        format.text
      end
    end

    private

    # The subject carries the whole message, because most mornings it is the only
    # part that gets read. Overdue first: it is the only category with a
    # consequence attached to the delay rather than a preference.
    def subject_line
      overdue = @disputes_overdue + @deletion_overdue
      return "[Fuime] #{overdue} OVERDUE · #{@needs_action} waiting" if overdue.positive?
      return "[Fuime] #{@needs_action} waiting · #{@sales_count} sales" if @needs_action.positive?

      "[Fuime] All clear · #{@sales_count} sales"
    end

  end
end
