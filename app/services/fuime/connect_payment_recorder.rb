# frozen_string_literal: true

# Fuime: turn a direct charge on a venture's own Stripe account into ledger lines.
#
# This is the money-in path for the architecture Fuime actually ships (CLAUDE.md
# L1): the guardian owns the connected account, Stripe holds and settles the
# funds, and Fuime's cut arrives as a Connect `application_fee_amount`. Fuime is
# never in the flow of funds — but it still owns the *ledger*, which is the
# product, so every one of those movements has to land on the venture's page.
#
# Sibling of Fuime::PaymentWebhookHandler, which does the same job for the
# retired pooled-account simulator. Three differences, all deliberate:
#
#   1. VENTURE RESOLUTION. The pooled path trusts `fuime_event_id` in metadata.
#      Here the venture comes from the connected account the event arrived from
#      (`event.account` -> StripeConnectedAccount -> Event). That is strictly
#      better: metadata is something Fuime wrote and a Checkout session can be
#      created without it, whereas the account field is Stripe's own statement of
#      whose account the money moved through.
#
#   2. THE FEE IS OBSERVED, NOT COMPUTED. The pooled path had to calculate Fuime's
#      cut and post it, because in that model Fuime received the gross and owed
#      the venture the rest. Here Stripe has already deducted
#      `application_fee_amount` before the money reaches the venture's balance, so
#      the ledger records what Stripe *did*. No rate is applied at this layer at
#      all, which means a plan change can never retroactively disagree with a
#      posted line.
#
#   3. THE FEE COMES BACK ONLY WHEN STRIPE SAYS IT DID. See #handle_fee_refunded.
#
# Idempotency and the ledger key scheme both live in Fuime::VentureLedger; see
# its header for why the keys are shared with the pooled path rather than
# namespaced per endpoint.
module Fuime
  class ConnectPaymentRecorder
    # `application_fee.refunded` is included here even though application fees
    # belong to the platform rather than to the connected account, because Stripe
    # has delivered it to platform endpoints and connected-account endpoints at
    # different times and the object carries an `account` field either way.
    # Accepting it on both dispatchers is safe precisely because the ledger keys
    # are shared: whichever endpoint sees it first posts the line, and the other
    # is a no-op.
    HANDLED_TYPES = %w[
      payment_intent.succeeded
      charge.refunded
      charge.dispute.created
      application_fee.refunded
    ].freeze

    def initialize(event:)
      @stripe_event = event
    end

    def handle
      return nil unless HANDLED_TYPES.include?(@stripe_event.type)

      case @stripe_event.type
      when "payment_intent.succeeded"
        intent = @stripe_event.data.object
        record_payment(object: intent, amount_cents: intent.amount_received)
      when "charge.refunded"
        charge = @stripe_event.data.object
        record_reversal(object: charge, amount_cents: charge.amount_refunded, kind: :refund)
      when "charge.dispute.created"
        dispute = @stripe_event.data.object
        record_reversal(
          object: dispute,
          amount_cents: dispute.amount,
          kind: :dispute,
          payment_intent_id: dispute.payment_intent
        )
      when "application_fee.refunded"
        handle_fee_refunded
      end
    end

    private

    # The connected account this event came from. Connected-account events carry
    # it at the top level of the event, not in the object.
    def stripe_account_id
      @stripe_event.account
    end

    # Venture lookup via the local mirror of the connected account.
    #
    # A missing mirror is logged rather than raised, matching
    # ConnectWebhookHandler: Stripe legitimately delivers events for accounts a
    # platform created and abandoned, and replaying old events after a database
    # restore hits this honestly. Raising would make Stripe retry forever.
    def venture_for_account
      if stripe_account_id.blank?
        Rails.logger.warn(
          "[Fuime] #{@stripe_event.type} arrived with no connected account; cannot map to a venture"
        )
        return nil
      end

      record = ::StripeConnectedAccount.find_by(stripe_id: stripe_account_id)
      if record.blank?
        Rails.logger.info(
          "[Fuime] #{@stripe_event.type} for unknown connected account #{stripe_account_id}"
        )
        return nil
      end

      record.event
    end

    def record_payment(object:, amount_cents:)
      amount_cents = amount_cents.to_i
      return nil if amount_cents <= 0

      venture = venture_for_account
      return nil if venture.blank?

      ledger = VentureLedger.new(event: venture)

      ActiveRecord::Base.transaction do
        raw = ledger.post!(
          key: VentureLedger.payment_key(object.id),
          amount_cents: amount_cents,
          memo: memo_for(object, venture),
          date: posted_date(object)
        )

        record_platform_fee(ledger:, object:, venture:, gross_cents: amount_cents)
        record_processing_fee(ledger:, object:, venture:, gross_cents: amount_cents)

        raw
      end
    end

    # Stripe's own processing fee, so the ledger reconciles to what actually lands.
    #
    # Without this the ledger overstated every venture's balance by roughly 2.9% + 30¢
    # per sale: the gross and Fuime's cut were posted, but Stripe's cut was invisible
    # even though it is deducted from the same balance.
    #
    # ── Why `fee_details` and not `balance_transaction.fee` ─────────────────
    #
    # On a direct charge the balance transaction's `fee` is the TOTAL deducted from the
    # connected account, which INCLUDES the application fee. Posting that total
    # alongside #record_platform_fee would charge a family for Fuime's cut twice.
    # `fee_details` breaks it down by `type`, so summing only the `stripe_fee` entries
    # gives Stripe's portion alone.
    #
    # ── Why a failure here raises ──────────────────────────────────────────
    #
    # This needs an API call the webhook payload cannot supply (the payload carries a
    # balance-transaction ID, not the object). If that call fails, raising lets Stripe
    # retry the whole webhook — and because every ledger key is shared and idempotent,
    # the retry re-posts nothing for the payment and simply tries the fee again. Swallowing
    # the error would instead leave the balance permanently overstated with only a log
    # line to show for it.
    def record_processing_fee(ledger:, object:, venture:, gross_cents:)
      key = VentureLedger.processing_fee_key(object.id)
      return nil if VentureLedger.find_row(key).present?

      fee_cents = processing_fee_cents(object)

      # nil means "could not determine", which is different from zero. Zero is a real
      # answer for a charge Stripe did not take a fee on, and posting nothing is correct.
      return nil if fee_cents.nil? || fee_cents.zero?

      # A tripwire for a malformed payload rather than an expected branch: Stripe would
      # never take more in fees than the payment itself.
      fee_cents = [fee_cents, gross_cents].min

      ledger.post!(
        key: key,
        amount_cents: -fee_cents,
        memo: "Stripe processing fee",
        date: posted_date(object)
      )
    end

    # Stripe's portion of the fees on this charge, in cents. nil if it cannot be
    # established, which the caller treats as a retryable condition.
    def processing_fee_cents(intent)
      charge_id = intent.respond_to?(:latest_charge) ? intent.latest_charge : nil
      if charge_id.blank?
        Rails.logger.info(
          "[Fuime] payment #{intent.id} has no latest_charge; no processing fee recorded"
        )
        return nil
      end

      charge = Stripe::Charge.retrieve(
        { id: charge_id, expand: ["balance_transaction"] },
        connected_account_request_options
      )

      details = Array(StripeHash.deep(charge).dig(:balance_transaction, :fee_details))
      if details.empty?
        Rails.logger.info(
          "[Fuime] charge #{charge_id} has no fee_details yet; no processing fee recorded"
        )
        return nil
      end

      details
        .select { |d| d[:type].to_s == "stripe_fee" }
        .sum { |d| d[:amount].to_i }
    end

    # The charge lives on the connected account, so reading it needs that context.
    def connected_account_request_options
      { api_key: StripeService.secret_key, stripe_account: stripe_account_id }
    end

    # Fuime's cut, as its own negative line, taken from what Stripe actually
    # deducted.
    #
    # Nil or zero is a legitimate and expected outcome, not a missing value: the
    # Founders plan is 0%, so a venture on it has no application fee and must not
    # get a phantom line. That is also why nothing here falls back to computing a
    # rate — a computed fallback is how the pooled path once charged a 0%-plan
    # venture anyway.
    def record_platform_fee(ledger:, object:, venture:, gross_cents:)
      fee_cents = object.respond_to?(:application_fee_amount) ? object.application_fee_amount.to_i : 0
      return nil if fee_cents <= 0

      # Stripe would never take a fee larger than the payment, so this is a
      # tripwire for a malformed payload rather than an expected branch.
      fee_cents = [fee_cents, gross_cents].min

      ledger.post!(
        key: VentureLedger.fee_key(object.id),
        amount_cents: -fee_cents,
        memo: "Fuime platform fee",
        date: posted_date(object)
      )
    end

    # A refund or chargeback, as a negative line against the venture the original
    # payment was booked to.
    #
    # Booked via the ORIGINAL payment's ledger mapping rather than via the
    # connected account, so a reversal can never land on a different venture than
    # the payment it reverses even if the account mirror changed in between.
    def record_reversal(object:, amount_cents:, kind:, payment_intent_id: nil)
      amount_cents = amount_cents.to_i
      return nil if amount_cents <= 0

      intent_id = payment_intent_id.presence ||
                  (object.respond_to?(:payment_intent) ? object.payment_intent : nil)

      if intent_id.blank?
        Rails.logger.warn("[Fuime] #{kind} #{object.id} has no payment_intent; cannot map to a venture")
        return nil
      end

      original = VentureLedger.find_row(VentureLedger.payment_key(intent_id))
      if original.blank?
        Rails.logger.warn(
          "[Fuime] #{kind} #{object.id} references unrecorded payment #{intent_id}; ignoring"
        )
        return nil
      end

      venture = VentureLedger.event_for_row(original)
      if venture.blank?
        Rails.logger.warn(
          "[Fuime] #{kind} #{object.id}: original payment #{intent_id} has no venture mapping"
        )
        return nil
      end

      # Reverse only what has not already been reversed. A charge can be refunded
      # in increments, and `amount_refunded` is CUMULATIVE, so posting it verbatim
      # on the second refund event would claw back more than the payment.
      outstanding = original.amount_cents - VentureLedger.reversed_cents_for(intent_id)
      reversal_cents = [amount_cents, outstanding].min

      if reversal_cents <= 0
        Rails.logger.info("[Fuime] #{kind} #{object.id}: payment #{intent_id} already fully reversed")
        return nil
      end

      VentureLedger.new(event: venture).post!(
        key: VentureLedger.reversal_key(
          intent_id:, kind:, object_id: object.id, amount_cents:
        ),
        amount_cents: -reversal_cents,
        memo: kind == :dispute ? "Disputed payment (chargeback)" : "Refunded payment",
        date: posted_date(object)
      )
    end

    # Fuime giving its cut back, posted ONLY on Stripe's word that it happened.
    #
    # This is the one place this class deliberately behaves differently from the
    # pooled handler, and the reason is that in the pooled model Fuime held the
    # gross and could decide to hand the fee back, whereas here the application fee
    # is a separate Stripe object that is NOT returned when a charge is refunded
    # unless the refund was created with `refund_application_fee: true`.
    #
    # So rebating proportionally on `charge.refunded` — which is what the pooled
    # path does — would print a credit into a teenager's ledger for money that is
    # still sitting in Fuime's account. A ledger that reconciles is the entire
    # value proposition, so the rebate waits for `application_fee.refunded`.
    #
    # NOTE FOR THE REFUND-CREATION PATH, WHICH DOES NOT EXIST YET: whether families
    # get the fee back on a refund is now a policy decision made at refund time, by
    # passing `refund_application_fee`. Choosing not to pass it means Fuime keeps
    # its cut on a sale the family had to unwind.
    def handle_fee_refunded
      fee = @stripe_event.data.object
      refunded_cents = fee.amount_refunded.to_i
      return nil if refunded_cents <= 0

      charge_id = fee.respond_to?(:charge) ? fee.charge : nil
      intent_id = intent_id_for_fee(fee, charge_id)
      if intent_id.blank?
        Rails.logger.warn(
          "[Fuime] application_fee.refunded #{fee.id} cannot be traced to a recorded payment; ignoring"
        )
        return nil
      end

      fee_row = VentureLedger.find_row(VentureLedger.fee_key(intent_id))
      if fee_row.blank?
        Rails.logger.warn(
          "[Fuime] application_fee.refunded #{fee.id}: no fee line recorded for payment #{intent_id}"
        )
        return nil
      end

      venture = VentureLedger.event_for_row(fee_row)
      return nil if venture.blank?

      # Cap at whatever fee is still outstanding, so a sequence of partial fee
      # refunds can never credit back more than was charged.
      original_fee = fee_row.amount_cents.abs
      remaining = original_fee - VentureLedger.fee_rebated_cents_for(intent_id)
      rebate = [refunded_cents, remaining].min
      return nil if rebate <= 0

      VentureLedger.new(event: venture).post!(
        key: VentureLedger.fee_rebate_key(
          intent_id:, object_id: fee.id, reversal_cents: refunded_cents
        ),
        amount_cents: rebate,
        memo: "Fuime platform fee refunded",
        date: posted_date(fee)
      )
    end

    # An ApplicationFee names the charge it was taken from, not the PaymentIntent
    # the ledger is keyed on. `originating_transaction` is present on some fee
    # objects and is the intent; otherwise the charge id is tried directly, which
    # covers ledger rows keyed from a charge rather than an intent.
    def intent_id_for_fee(fee, charge_id)
      candidate = fee.respond_to?(:originating_transaction) ? fee.originating_transaction : nil
      return candidate if candidate.present? && VentureLedger.find_row(VentureLedger.fee_key(candidate))

      return charge_id if charge_id.present? && VentureLedger.find_row(VentureLedger.fee_key(charge_id))

      candidate.presence || charge_id
    end

    def posted_date(object)
      created = object.respond_to?(:created) ? object.created : nil
      created.present? ? Time.at(created).to_date : Date.current
    end

    def memo_for(object, venture)
      description = object.respond_to?(:description) ? object.description : nil
      description.presence || "Payment to #{venture.name}"
    end

  end
end
