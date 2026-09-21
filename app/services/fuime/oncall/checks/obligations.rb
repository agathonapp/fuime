# frozen_string_literal: true

module Fuime
  module Oncall
    module Checks
      # Fuime: deadlines that are owed to somebody outside the company.
      #
      # Every other check in this set is about the product being broken. This one
      # is about the product working perfectly while Fuime quietly fails an
      # obligation, which is the more expensive of the two and has no symptom at
      # all until the deadline passes.
      #
      #   * A chargeback is **lost by default** if Fuime does not respond by the
      #     evidence deadline. Under merchant-of-record the dispute is against
      #     Fuime LLC, so Fuime pays it — and the teenager has already been
      #     debited. Missing one is a direct cash loss plus a dispute-rate
      #     problem with the card networks.
      #   * A COPPA deletion request has a 30-day response window that Fuime
      #     promised a parent in writing on the guardian page. It is the one
      #     deadline in the app with a statutory number behind it.
      #
      # ── Why this pages before the deadline rather than after ───────────────
      #
      # An incident raised the day a dispute is due is useless: assembling
      # evidence takes longer than that. WARNING_WINDOW is the point at which
      # there is still time to act, which is the only point at which an alert
      # about a deadline has any value.
      class Obligations < Check
        DISPUTE_WARNING_WINDOW = 3.days
        DATA_REQUEST_WARNING_WINDOW = 7.days

        def call
          findings = []
          now = Time.current

          overdue_disputes = ::Fuime::Dispute.actionable.select(&:overdue?)
          if overdue_disputes.any?
            findings << finding(
              key: "obligations.disputes_overdue",
              title: "#{overdue_disputes.size} chargeback #{'deadline'.pluralize(overdue_disputes.size)} already passed",
              # Sev-1: the money is gone the moment the deadline passes and
              # there is no appeal. Of everything in this file it is the only
              # one where another night of delay changes the outcome.
              severity: :sev1,
              count: overdue_disputes.size,
              total_cents: overdue_disputes.sum(&:amount_cents),
              cases: overdue_disputes.first(5).map { |d| { id: d.stripe_dispute_id, due: d.evidence_due_at&.iso8601 } }
            )
          end

          due_soon = ::Fuime::Dispute.actionable.reject(&:overdue?).select do |dispute|
            dispute.evidence_due_at.present? && dispute.evidence_due_at <= now + DISPUTE_WARNING_WINDOW
          end
          if due_soon.any?
            findings << finding(
              key: "obligations.disputes_due_soon",
              title: "#{due_soon.size} chargeback #{'deadline'.pluralize(due_soon.size)} within #{DISPUTE_WARNING_WINDOW.inspect}",
              severity: :sev2,
              count: due_soon.size,
              total_cents: due_soon.sum(&:amount_cents),
              cases: due_soon.first(5).map { |d| { id: d.stripe_dispute_id, due: d.evidence_due_at&.iso8601 } }
            )
          end

          requests = ::Fuime::DataRequest.needs_action.to_a
          overdue_requests = requests.select(&:overdue?)
          if overdue_requests.any?
            findings << finding(
              key: "obligations.data_requests_overdue",
              title: "#{overdue_requests.size} parent deletion #{'request'.pluralize(overdue_requests.size)} past the 30-day window",
              severity: :sev1,
              count: overdue_requests.size,
              oldest_requested_at: overdue_requests.map(&:requested_at).min&.iso8601
            )
          end

          due_requests = (requests - overdue_requests).select { |r| r.due_at <= now + DATA_REQUEST_WARNING_WINDOW }
          if due_requests.any?
            findings << finding(
              key: "obligations.data_requests_due_soon",
              title: "#{due_requests.size} parent deletion #{'request'.pluralize(due_requests.size)} due within #{DATA_REQUEST_WARNING_WINDOW.inspect}",
              severity: :sev2,
              count: due_requests.size,
              next_due_at: due_requests.map(&:due_at).min&.iso8601
            )
          end

          findings
        end

      end
    end
  end
end
