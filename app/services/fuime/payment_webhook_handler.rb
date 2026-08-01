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

    def memo_for(object, event)
      description = object.respond_to?(:description) ? object.description : nil
      description.presence || "Payment to #{event.name}"
    end
  end
end
