# frozen_string_literal: true

# Fuime: keep the ledger and the payout request in step with what Stripe actually
# did with a payout.
#
# Money out, as against Fuime::ConnectPaymentRecorder's money in. Both write to a
# venture's ledger from connected-account webhooks and share the key scheme in
# Fuime::VentureLedger; they are separate classes because a payout has a local
# record with an approval decision attached to it and a payment does not.
#
# ── When the ledger is debited, and why it is not at approval ────────────────
#
# Stripe debits the connected account's balance when the payout is CREATED, not
# when it lands days later. So the ledger line is written on `payout.created`.
#
# It is written from the webhook rather than from Fuime::PayoutService#approve! on
# purpose: the webhook is Stripe stating what it did, whereas approve! is Fuime
# stating what it asked for. Those diverge exactly when it matters most — a payout
# that Stripe accepted and then reversed, or one created outside Fuime entirely —
# and in a disagreement the balance follows Stripe. `payout.paid` therefore moves
# no money in the ledger; the money left at creation, and "paid" only means it
# reached the bank.
#
# ── Payouts with no Fuime request behind them ───────────────────────────────
#
# The ledger write does NOT depend on finding a PayoutRequest. A guardian owns this
# Stripe account outright and can move their own money without Fuime's involvement;
# Stripe can also create payouts itself. When that happens the balance genuinely
# dropped, and a ledger that ignored it would stop reconciling — which is worse
# than a ledger line whose approval trail says "not requested through Fuime".
module Fuime
  class ConnectPayoutRecorder
    HANDLED_TYPES = %w[
      payout.created
      payout.paid
      payout.failed
      payout.canceled
    ].freeze

    def initialize(event:)
      @stripe_event = event
    end

    def handle
      return nil unless HANDLED_TYPES.include?(@stripe_event.type)

      payout = @stripe_event.data.object

      case @stripe_event.type
      when "payout.created"
        record_debit(payout)
      when "payout.paid"
        mark_request_paid(payout)
      when "payout.failed", "payout.canceled"
        record_return(payout)
      end
    end

    private

    def venture
      @venture ||= begin
        account_id = @stripe_event.account
        if account_id.blank?
          Rails.logger.warn("[Fuime] #{@stripe_event.type} arrived with no connected account")
          nil
        else
          record = ::StripeConnectedAccount.find_by(stripe_id: account_id)
          if record.blank?
            Rails.logger.info(
              "[Fuime] #{@stripe_event.type} for unknown connected account #{account_id}"
            )
          end
          record&.event
        end
      end
    end

    # The local request this payout came from, if any. See the class comment for
    # why absence is normal rather than an error.
    def payout_request(payout)
      ::PayoutRequest.find_by(stripe_payout_id: payout.id)
    end

    # Money left the venture's Stripe balance.
    #
    # The memo deliberately contains the word "payout", which
    # Fuime::TaxTrackerService excludes from both income and expenses. A payout is
    # the family moving their own already-earned money; treating it as a business
    # expense would understate the teen's taxable income.
    def record_debit(payout)
      return nil if venture.blank?

      amount_cents = payout.amount.to_i
      return nil if amount_cents <= 0

      VentureLedger.new(event: venture).post!(
        key: VentureLedger.payout_key(payout.id),
        amount_cents: -amount_cents,
        memo: payout_memo(payout),
        date: posted_date(payout)
      )
    end

    # Stripe confirmed arrival. No ledger movement: the balance was debited at
    # creation, and posting again here would double-count the withdrawal.
    def mark_request_paid(payout)
      request = payout_request(payout)
      if request.blank?
        Rails.logger.info("[Fuime] payout.paid #{payout.id} has no Fuime payout request")
        return nil
      end

      return request if request.paid?

      request.paid_at = Time.current
      request.mark_paid!
      request.save!

      Rails.logger.info(
        "[Fuime] payout request #{request.id} paid: #{payout.id} reached the bank"
      )

      request
    end

    # The payout bounced or was cancelled, so Stripe put the money back.
    #
    # Both the ledger credit and the request state change happen here, and the
    # ledger credit happens even when there is no request — see the class comment.
    def record_return(payout)
      credit_returned_funds(payout)

      request = payout_request(payout)
      return nil if request.blank?

      unless request.failed?
        request.failure_code = payout.respond_to?(:failure_code) ? payout.failure_code : nil
        request.failure_message = failure_message_for(payout)
        request.mark_failed!
        request.save!
      end

      Rails.logger.warn(
        "[Fuime] payout request #{request.id} failed: #{payout.id} " \
        "(#{request.failure_code || 'no code'})"
      )

      request
    end

    def credit_returned_funds(payout)
      return nil if venture.blank?

      amount_cents = payout.amount.to_i
      return nil if amount_cents <= 0

      # Only reverse a debit that was actually posted. Stripe can emit
      # `payout.failed` for a payout whose `payout.created` never reached Fuime,
      # and crediting funds back that were never debited would invent money.
      if VentureLedger.find_row(VentureLedger.payout_key(payout.id)).blank?
        Rails.logger.info(
          "[Fuime] #{@stripe_event.type} #{payout.id}: no debit was recorded, nothing to reverse"
        )
        return nil
      end

      VentureLedger.new(event: venture).post!(
        key: VentureLedger.payout_reversal_key(payout.id),
        amount_cents: amount_cents,
        memo: @stripe_event.type == "payout.canceled" ? "Payout cancelled — funds returned" : "Payout failed — funds returned",
        date: posted_date(payout)
      )
    end

    def payout_memo(payout)
      # "Payout to bank account" rather than naming the bank: Fuime does not store
      # the family's bank details and must not imply it knows them.
      arrival = payout.respond_to?(:arrival_date) ? payout.arrival_date : nil
      return "Payout to bank account" if arrival.blank?

      "Payout to bank account (expected #{Time.at(arrival).to_date.strftime('%b %-d')})"
    end

    def failure_message_for(payout)
      message = payout.respond_to?(:failure_message) ? payout.failure_message : nil
      return message if message.present?

      return "Stripe cancelled this payout." if @stripe_event.type == "payout.canceled"

      "Stripe could not send this payout to the bank account on file."
    end

    def posted_date(payout)
      created = payout.respond_to?(:created) ? payout.created : nil
      created.present? ? Time.at(created).to_date : Date.current
    end

  end
end
