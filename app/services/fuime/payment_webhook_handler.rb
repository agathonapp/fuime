# frozen_string_literal: true

# Fuime: Handle Stripe webhook events for incoming payments.
#
# Payments are taken on one pooled Fuime platform Stripe account; the paying
# business is identified by `fuime_event_id` in the Checkout/PaymentIntent
# metadata. This handler feeds those payments into HCB's EXISTING ledger
# pipeline rather than reimplementing any of it (CLAUDE.md Rule 3):
#
#   RawPendingDonationTransaction   <- narrowest legitimate "money in" source
#     -> CanonicalPendingTransaction (creates HcbCode + ledger item on commit)
#       -> CanonicalPendingEventMapping (assigns it to the business)
#
# Donation is the correct analogue: an outside party sending money into an
# org. We do not touch the pipeline internals — only its public entry points.
#
# Idempotency: keyed on the Stripe object id. Replaying the same webhook does
# not double-post, which Stripe relies on since it retries on any non-2xx.
module Fuime
  class PaymentWebhookHandler
    class MissingEventError < StandardError; end

    def initialize(event:)
      @stripe_event = event
    end

    def handle
      case @stripe_event.type
      # A Checkout payment fires BOTH checkout.session.completed and
      # payment_intent.succeeded, with different object ids. Keying idempotency
      # on the object id therefore posted the same payment to the ledger twice.
      # We handle payment_intent.succeeded only — it is the event that fires for
      # every payment (Checkout, Payment Link, or direct PaymentIntent) and
      # carries the settled amount.
      when "payment_intent.succeeded"
        record_payment(
          object: @stripe_event.data.object,
          amount_cents: @stripe_event.data.object.amount_received
        )
      when "checkout.session.completed"
        Rails.logger.info(
          "[Fuime] Ignoring checkout.session.completed for #{@stripe_event.data.object.id}; " \
          "the payment is recorded from payment_intent.succeeded"
        )
        nil
      # The failure half of the lifecycle. Without these, a refunded or disputed
      # payment stays on a teen's ledger as income and inflates the tax number
      # Fuime shows their family.
      when "charge.refunded"
        record_reversal(
          object: @stripe_event.data.object,
          amount_cents: @stripe_event.data.object.amount_refunded,
          kind: :refund
        )
      when "charge.dispute.created"
        dispute = @stripe_event.data.object
        record_reversal(
          object: dispute,
          amount_cents: dispute.amount,
          kind: :dispute,
          payment_intent_id: dispute.payment_intent
        )
      else
        Rails.logger.info("[Fuime] Ignoring webhook event: #{@stripe_event.type}")
        nil
      end
    end

    private

    def record_payment(object:, amount_cents:)
      metadata = object.metadata
      event_id = metadata && metadata["fuime_event_id"]
      return nil if event_id.blank?
      return nil if amount_cents.to_i <= 0

      event = ::Event.find_by(id: event_id)
      unless event
        Rails.logger.warn("[Fuime] Webhook references unknown event_id=#{event_id}")
        return nil
      end

      # One ledger line per Stripe object, no matter how often Stripe retries.
      transaction_key = "fuime_#{object.id}"

      existing = ::RawPendingDonationTransaction.find_by(donation_transaction_id: transaction_key)
      if existing
        Rails.logger.info("[Fuime] Webhook #{object.id} already recorded; skipping")
        return existing
      end

      ActiveRecord::Base.transaction do
        raw = ::RawPendingDonationTransaction.create!(
          donation_transaction_id: transaction_key,
          amount_cents: amount_cents.to_i,
          date_posted: Time.at(object.created).to_date
        )

        cpt = ::CanonicalPendingTransaction.create!(
          date: raw.date,
          memo: memo_for(object, event),
          amount_cents: raw.amount_cents,
          raw_pending_donation_transaction_id: raw.id,
          # NOT fronted. In HCB, `fronted` means the platform advances the org
          # spendable credit against money that hasn't settled — a balance-sheet
          # decision backed by Hack Club's reserves. Fuime has no reserves, and
          # Stripe settlement is T+2 with refund and chargeback risk after that,
          # so fronting here would let a teen spend money Fuime does not hold.
          fronted: false
        )

        ::CanonicalPendingEventMapping.create!(
          canonical_pending_transaction_id: cpt.id,
          event_id: event.id
        )

        Rails.logger.info(
          "[Fuime] Recorded payment #{object.id} for #{event.name}: " \
          "$#{amount_cents.to_i / 100.0} (cpt=#{cpt.id})"
        )

        raw
      end
    end

    # Post a negative ledger line reversing a payment that was refunded or
    # disputed. Booked against the same business as the original payment, which
    # we locate via the originating payment intent.
    #
    # Idempotent on the reversal's own key, so Stripe retries — and the several
    # refund events a partially-refunded charge can emit — don't stack up.
    def record_reversal(object:, amount_cents:, kind:, payment_intent_id: nil)
      amount_cents = amount_cents.to_i
      return nil if amount_cents <= 0

      intent_id = payment_intent_id.presence || (object.respond_to?(:payment_intent) ? object.payment_intent : nil)
      if intent_id.blank?
        Rails.logger.warn("[Fuime] #{kind} #{object.id} has no payment_intent; cannot map to a business")
        return nil
      end

      original = ::RawPendingDonationTransaction.find_by(donation_transaction_id: "fuime_#{intent_id}")
      unless original
        Rails.logger.warn("[Fuime] #{kind} #{object.id} references unrecorded payment #{intent_id}; ignoring")
        return nil
      end

      event = event_for_raw(original)
      unless event
        Rails.logger.warn("[Fuime] #{kind} #{object.id}: original payment #{intent_id} has no event mapping")
        return nil
      end

      # A charge can be refunded in several increments; key on the cumulative
      # refunded amount so each distinct total posts exactly once. The intent id
      # is embedded so all reversals of one payment can be summed by prefix.
      reversal_key = "#{reversal_key_prefix(intent_id)}#{kind}_#{object.id}_#{amount_cents}"

      existing = ::RawPendingDonationTransaction.find_by(donation_transaction_id: reversal_key)
      if existing
        Rails.logger.info("[Fuime] #{kind} #{reversal_key} already recorded; skipping")
        return existing
      end

      # Reverse only what hasn't already been reversed, so a refund following a
      # partial refund doesn't claw back more than the original payment.
      already_reversed = reversed_cents_for(intent_id)
      outstanding = original.amount_cents - already_reversed
      reversal_cents = [amount_cents, outstanding].min

      if reversal_cents <= 0
        Rails.logger.info("[Fuime] #{kind} #{object.id}: payment #{intent_id} already fully reversed")
        return nil
      end

      ActiveRecord::Base.transaction do
        raw = ::RawPendingDonationTransaction.create!(
          donation_transaction_id: reversal_key,
          amount_cents: -reversal_cents,
          date_posted: Time.at(object.created).to_date
        )

        cpt = ::CanonicalPendingTransaction.create!(
          date: raw.date,
          memo: kind == :dispute ? "Disputed payment (chargeback)" : "Refunded payment",
          amount_cents: raw.amount_cents,
          raw_pending_donation_transaction_id: raw.id,
          fronted: false
        )

        ::CanonicalPendingEventMapping.create!(
          canonical_pending_transaction_id: cpt.id,
          event_id: event.id
        )

        Rails.logger.info(
          "[Fuime] Recorded #{kind} #{object.id} for #{event.name}: " \
          "-$#{reversal_cents / 100.0} (cpt=#{cpt.id})"
        )

        raw
      end
    end

    # Reversal rows are keyed "fuime_rev_<intent_id>_<kind>_<obj>_<amount>", so
    # every reversal of a given payment shares a prefix and can be summed
    # directly — no join back through the ledger, and no risk of picking up
    # reversals belonging to a different payment to the same business.
    def reversal_key_prefix(intent_id)
      "fuime_rev_#{intent_id}_"
    end

    # Total already reversed against a payment intent, as a positive number.
    def reversed_cents_for(intent_id)
      ::RawPendingDonationTransaction
        .where("donation_transaction_id LIKE ?", "#{sanitize_like(reversal_key_prefix(intent_id))}%")
        .sum(:amount_cents)
        .abs
    end

    def sanitize_like(str)
      ActiveRecord::Base.sanitize_sql_like(str)
    end

    def event_for_raw(raw)
      cpt = ::CanonicalPendingTransaction.find_by(raw_pending_donation_transaction_id: raw.id)
      return nil unless cpt

      ::CanonicalPendingEventMapping.find_by(canonical_pending_transaction_id: cpt.id)&.event
    end

    def memo_for(object, event)
      description = object.respond_to?(:description) ? object.description : nil
      description.presence || "Payment to #{event.name}"
    end
  end
end
