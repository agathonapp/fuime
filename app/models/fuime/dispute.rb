# frozen_string_literal: true

module Fuime
  # Fuime: a chargeback against a merchant-of-record sale, as a thing a person
  # can be assigned rather than a line in a ledger.
  #
  # ── Why this exists at all ──────────────────────────────────────────────────
  #
  # `charge.dispute.created` already reached the ledger before this table: the
  # sale is reversed and Fuime's cut rebated, so the operator's payable drops the
  # moment the chargeback lands. That half was correct and is untouched.
  #
  # What was missing is that **nobody was told**. Under merchant of record the
  # dispute is against Fuime LLC, not against the teenager — Fuime's name is on
  # the buyer's statement, so Fuime is the party the card network expects to
  # respond, and a dispute nobody answers by its deadline is lost by default.
  # Before this table the only record of one was a ledger row reading "Disputed
  # payment (chargeback)" on a page an admin has no reason to open.
  #
  # ── What a row is, and is not ───────────────────────────────────────────────
  #
  # It is the case file: reason code, deadline, outcome. It is **not** money, and
  # nothing may compute a balance or a payable from it — that is
  # Fuime::PayablesLedger reading canonical transactions, and a second source of
  # truth for money is precisely the failure mode Fuime::Sale's header warns
  # about. `amount_cents` here is what Stripe said the dispute was for; what the
  # operator was actually debited is the ledger's business and can differ (the
  # recorder caps a reversal at the outstanding balance).
  class Dispute < ApplicationRecord
    self.table_name = "fuime_disputes"

    belongs_to :event
    belongs_to :sale, class_name: "Fuime::Sale", foreign_key: :fuime_sale_id, optional: true, inverse_of: false

    monetize :amount_cents

    # Stripe's status vocabulary, verbatim. `warning_*` are early-warning
    # notifications (Visa TC40 / Mastercard SAFE) where no money has moved yet;
    # the rest are a real dispute.
    OPEN_STATUSES = %w[warning_needs_response warning_under_review needs_response under_review].freeze
    # Statuses where a human has something to do before a deadline. The queue
    # sorts on these; `under_review` means Stripe has our evidence already.
    ACTIONABLE_STATUSES = %w[warning_needs_response needs_response].freeze
    WON_STATUSES = %w[won warning_closed].freeze
    LOST_STATUSES = %w[lost].freeze

    validates :stripe_dispute_id, presence: true, uniqueness: true
    validates :stripe_payment_intent_id, :status, :opened_at, presence: true

    scope :open_cases, -> { where(status: OPEN_STATUSES) }
    scope :actionable, -> { where(status: ACTIONABLE_STATUSES) }
    scope :closed_cases, -> { where.not(status: OPEN_STATUSES) }
    # Deadline first, nulls last — an early-warning row often has no due date and
    # must not sort above a chargeback that is due tomorrow.
    scope :by_deadline, -> { order(Arel.sql("evidence_due_at IS NULL, evidence_due_at ASC, opened_at DESC")) }

    def open? = OPEN_STATUSES.include?(status)
    def actionable? = ACTIONABLE_STATUSES.include?(status)
    def won? = WON_STATUSES.include?(status)
    def lost? = LOST_STATUSES.include?(status)

    # An early warning is a heads-up from the network, not a debit. Worth showing
    # and worth answering; not worth waking anyone at 2am.
    def early_warning? = status.to_s.start_with?("warning_")

    def reinstated? = reinstated_at.present?

    def hours_until_evidence_due
      return nil if evidence_due_at.blank?

      ((evidence_due_at - Time.current) / 1.hour).floor
    end

    def overdue?
      actionable? && evidence_due_at.present? && evidence_due_at.past?
    end

    # Where a human actually answers it. Fuime has no evidence-submission UI and
    # deliberately does not: the Stripe Dashboard's is better than anything worth
    # building here, and the response is a legal statement by Fuime LLC rather
    # than an app workflow.
    def stripe_dashboard_url
      base = "https://dashboard.stripe.com"
      base += "/test" unless ::StripeService.mode == :live
      "#{base}/payments/#{stripe_payment_intent_id}"
    end

    # Stripe's reason codes are snake_case and go straight into a subject line.
    def reason_label
      reason.presence&.humanize || "Unspecified"
    end

  end
end
