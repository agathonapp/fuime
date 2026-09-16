# frozen_string_literal: true

module Fuime
  # Fuime: keep the dispute case file in step with Stripe, and give the money
  # back when a dispute is won.
  #
  # Called from Fuime::PaymentWebhookHandler for the three `charge.dispute.*`
  # events. The handler still owns the ledger reversal on `created`; this owns
  # everything that happens to the case afterwards.
  #
  # ── The bug this closes, which is the reason it exists ──────────────────────
  #
  # `charge.dispute.created` debits the operator. Nothing handled
  # `charge.dispute.closed`, so when Fuime WON a chargeback — Stripe returns the
  # money, the buyer's claim failed — the operator stayed debited forever. The
  # pending reversal is deliberately excluded from the settlement sweep
  # (Fuime::ConnectSettlementSweep: "settling them by construction would be
  # guessing"), so it sits unsettled, and `Event#pending_outgoing_balance_v2_cents`
  # counts unsettled outgoing against the payable. Permanently. A teenager whose
  # customer lost a chargeback never got their money back.
  #
  # ── How the money comes back ────────────────────────────────────────────────
  #
  # Not by posting an offsetting credit. A credit would be pending INCOMING,
  # which is excluded from the balance on purpose (Fuime does not front unsettled
  # money) and — being dispute-keyed — would never settle either, so the operator
  # would watch a phantom "still coming" line forever, which is exactly the
  # arrears bug the fee rebate already caused once.
  #
  # Instead the reversal is **declined**: `CanonicalPendingDeclinedMapping` is
  # upstream HCB's own mechanism for a pending line that turned out not to
  # happen, and `CanonicalPendingTransaction.unsettled` — which every balance
  # method goes through — excludes declined rows. So the debit stops counting,
  # the ledger keeps the row and its history, and no new money is invented.
  # A won dispute is precisely "this debit turned out not to happen".
  #
  # The fee rebate posted alongside it is declined for the same reason: Fuime's
  # cut was given back because the sale was reversed, and the sale is no longer
  # reversed.
  class DisputeRecorder
    # Stripe sends `dispute.amount` in the charge currency's minor unit.
    def self.record(stripe_dispute:, event:, sale: nil)
      new(stripe_dispute:, event:, sale:).record
    end

    def initialize(stripe_dispute:, event:, sale: nil)
      @stripe_dispute = stripe_dispute
      @event = event
      @sale = sale
    end

    # Idempotent in both directions: a re-delivered `created` updates the row it
    # already wrote, and a re-delivered `closed` reinstates at most once.
    def record
      dispute = upsert!
      return dispute if dispute.nil?

      reinstate_if_won!(dispute)
      notify(dispute)
      dispute
    end

    private

    attr_reader :stripe_dispute, :event, :sale

    def upsert!
      intent_id = stripe_dispute.payment_intent
      if intent_id.blank?
        Rails.logger.warn("[Fuime] dispute #{stripe_dispute.id} has no payment_intent; not recording a case")
        return nil
      end

      dispute = ::Fuime::Dispute.find_or_initialize_by(stripe_dispute_id: stripe_dispute.id)
      @status_before = dispute.status

      dispute.event ||= event
      dispute.sale ||= sale || ::Fuime::Sale.find_by(stripe_payment_intent_id: intent_id)
      dispute.stripe_payment_intent_id = intent_id
      dispute.stripe_charge_id = stripe_dispute.try(:charge)
      dispute.amount_cents = stripe_dispute.amount.to_i
      dispute.currency = stripe_dispute.try(:currency).presence || "usd"
      dispute.reason = stripe_dispute.try(:reason)
      dispute.status = stripe_dispute.status.to_s
      dispute.evidence_due_at = evidence_due_at
      dispute.opened_at ||= timestamp(stripe_dispute.try(:created)) || Time.current
      dispute.closed_at = Time.current if !dispute.open? && dispute.closed_at.nil?
      dispute.save!
      dispute
    rescue ActiveRecord::RecordNotUnique
      # Two deliveries of the same event racing. The other one wrote it.
      ::Fuime::Dispute.find_by(stripe_dispute_id: stripe_dispute.id)
    end

    # `evidence_details.due_by` is a unix timestamp and is absent on early
    # warnings, which have no evidence to submit.
    def evidence_due_at
      details = stripe_dispute.try(:evidence_details)
      return nil if details.nil?

      timestamp(details.try(:due_by))
    end

    def timestamp(value)
      value.present? ? Time.at(value.to_i) : nil
    end

    def reinstate_if_won!(dispute)
      return unless dispute.won?
      return if dispute.reinstated?

      declined = 0
      ActiveRecord::Base.transaction(requires_new: true) do
        declined += decline_rows(::Fuime::VentureLedger.reversal_kind_prefix(dispute.stripe_payment_intent_id, :dispute))
        declined += decline_rows(fee_rebate_prefix_for(dispute))
        dispute.update!(reinstated_at: Time.current)
      end

      Rails.logger.info(
        "[Fuime] dispute #{dispute.stripe_dispute_id} won; declined #{declined} reversal line(s) " \
        "for #{dispute.stripe_payment_intent_id}"
      )
    end

    # A dispute's fee rebate is keyed on the DISPUTE's id, not the intent's kind,
    # so it cannot be matched by kind the way the reversal can — but every rebate
    # for this payment shares the intent prefix, and the dispute's own object id
    # is in the key. Match on that, so a rebate belonging to a separate refund of
    # the same payment is left exactly where it is.
    def fee_rebate_prefix_for(dispute)
      "#{::Fuime::VentureLedger.fee_rebate_key_prefix(dispute.stripe_payment_intent_id)}#{dispute.stripe_dispute_id}_"
    end

    def decline_rows(prefix)
      raws = ::RawPendingDonationTransaction.where(
        "donation_transaction_id LIKE ?", "#{ActiveRecord::Base.sanitize_sql_like(prefix)}%"
      )
      count = 0
      raws.find_each do |raw|
        cpt = ::CanonicalPendingTransaction.find_by(raw_pending_donation_transaction_id: raw.id)
        next if cpt.nil?
        next if ::CanonicalPendingDeclinedMapping.exists?(canonical_pending_transaction_id: cpt.id)

        ::CanonicalPendingDeclinedMapping.create!(canonical_pending_transaction: cpt)
        count += 1
      end
      count
    end

    # Only on a change of status. Stripe re-delivers, and `dispute.updated` fires
    # for things that are none of our business (evidence we ourselves submitted);
    # an alert that arrives three times is an alert people stop reading.
    def notify(dispute)
      return if dispute.status == @status_before

      # Immediately, at any hour: the deadline is the card network's, not ours.
      ::Fuime::DisputeMailer.with(dispute:).ops_alert.deliver_later

      notify_operator(dispute)
    rescue => e
      # The case file and the ledger are the point. A mailer that cannot enqueue
      # must not roll back the record of a chargeback.
      Rails.error.report(e, handled: true, context: { fuime_dispute_id: dispute.id })
    end

    # The founder hears once, when a real dispute opens — the moment their
    # payable moved. Not on an early warning, which may never become a
    # chargeback and would have them worrying about nothing; not on the close,
    # because the ops alert already went to the person who can act, and a second
    # mail saying "we lost" is a notification that only takes something away.
    #
    # L7: most recipients are minors, so this waits for Fuime::MinorMailWindow.
    # It is transactional — it is the explanation for a number on their own page
    # — and there is nothing for them to do at 3 a.m. about it.
    def notify_operator(dispute)
      return unless @status_before.nil?
      return if dispute.early_warning?

      ::Fuime::DisputeMailer.with(dispute:)
                            .operator_notice
                            .deliver_later(wait_until: ::Fuime::MinorMailWindow.earliest_send_time)
    end

  end
end
