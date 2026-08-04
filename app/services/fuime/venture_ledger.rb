# frozen_string_literal: true

# Fuime: the one place a venture's ledger line gets written.
#
# Extracted from Fuime::PaymentWebhookHandler when the Stripe Connect money-in
# path was added. Both paths post the same *kind* of thing (an outside party sent
# money to a venture; Fuime took a cut) and differ only in how the venture is
# identified and where the fee number comes from. Keeping two copies of the
# posting logic would mean two copies of the idempotency rules, and money code
# that is subtly different in two places is money code that is wrong in one of
# them.
#
# ── Why the ledger keys live HERE and not in the handlers ────────────────────
#
# This is the load-bearing decision in this file. A key identifies a Stripe
# object, NOT a delivery of that object, and NOT the endpoint it arrived on.
#
# Direct charges on a connected account are delivered to Connect webhook
# endpoints, and platform charges to platform endpoints, so in a correct Stripe
# configuration a given payment_intent reaches exactly one handler. But webhook
# endpoint configuration is a dashboard checkbox, and the failure is silent: tick
# "listen to connected accounts" on the platform endpoint too and every payment
# arrives twice. If each handler namespaced its own keys (`fuime_...` vs
# `fuime_ca_...`) that misconfiguration would post every sale to a teenager's
# ledger TWICE, and the ledger is the product. Sharing one key per Stripe object
# makes the second delivery a no-op instead.
#
# So: same Stripe object id => same key => at most one ledger line, forever,
# regardless of which endpoint saw it or how many times Stripe retried.
#
# ── Why RawPendingDonationTransaction ───────────────────────────────────────
#
# It is the narrowest legitimate "money in from an outside party" entry point
# into HCB's ledger pipeline, and CLAUDE.md Rule 3 forbids modifying the pipeline
# internals. Donation is the correct analogue structurally even though nothing
# here is a donation. See PaymentWebhookHandler's header for the full chain.
module Fuime
  class VentureLedger
    # ── Key scheme ──────────────────────────────────────────────────────────
    #
    # Module functions rather than instance methods: reversal bookkeeping has to
    # look up rows belonging to a payment before it knows which venture that
    # payment belongs to, so the keys cannot depend on having an instance.

    # The payment itself. Keyed on the PaymentIntent id.
    def self.payment_key(object_id)
      "fuime_#{object_id}"
    end

    # Fuime's cut of that payment.
    def self.fee_key(object_id)
      "fuime_fee_#{object_id}"
    end

    # Stripe's own processing fee (~2.9% + 30¢), which is deducted from the venture's
    # balance alongside Fuime's cut. Separate key from #fee_key because they are two
    # different companies taking two different amounts, and a family reconciling their
    # books needs to see which is which.
    def self.processing_fee_key(object_id)
      "fuime_stripefee_#{object_id}"
    end

    # Reversals are keyed "fuime_rev_<intent>_<kind>_<object>_<amount>", so every
    # reversal of one payment shares a prefix and can be summed by prefix without
    # joining back through the ledger — and without any risk of picking up a
    # reversal that belongs to a different payment to the same venture.
    def self.reversal_key_prefix(intent_id)
      "fuime_rev_#{intent_id}_"
    end

    def self.reversal_key(intent_id:, kind:, object_id:, amount_cents:)
      "#{reversal_key_prefix(intent_id)}#{kind}_#{object_id}_#{amount_cents}"
    end

    def self.fee_rebate_key_prefix(intent_id)
      "fuime_feerev_#{intent_id}_"
    end

    # Money leaving the venture's Stripe balance for the family's bank. Keyed on
    # the Stripe payout id rather than on the PayoutRequest, because a payout can
    # legitimately exist with no Fuime request behind it (see
    # Fuime::ConnectPayoutRecorder) and the balance still moved.
    def self.payout_key(payout_id)
      "fuime_payout_#{payout_id}"
    end

    # Funds returning after a payout failed or was cancelled.
    def self.payout_reversal_key(payout_id)
      "fuime_payoutrev_#{payout_id}"
    end

    # A card purchase (or a refund of one). Keyed on the Stripe Issuing Transaction,
    # which is the settled object — authorizations are not posted, because an
    # authorization that never captures is not a transaction and would leave a
    # phantom expense on a teenager's books.
    #
    # Unlike a payout, card spend IS a deductible business expense and is
    # deliberately NOT excluded from Fuime::TaxTrackerService.
    def self.card_transaction_key(transaction_id)
      "fuime_card_#{transaction_id}"
    end

    def self.fee_rebate_key(intent_id:, object_id:, reversal_cents:)
      "#{fee_rebate_key_prefix(intent_id)}#{object_id}_#{reversal_cents}"
    end

    def self.find_row(key)
      ::RawPendingDonationTransaction.find_by(donation_transaction_id: key)
    end

    # Total already reversed against a payment, as a positive number.
    def self.reversed_cents_for(intent_id)
      sum_by_prefix(reversal_key_prefix(intent_id)).abs
    end

    # Total fee already given back for a payment, as a positive number.
    def self.fee_rebated_cents_for(intent_id)
      sum_by_prefix(fee_rebate_key_prefix(intent_id))
    end

    def self.sum_by_prefix(prefix)
      ::RawPendingDonationTransaction
        .where("donation_transaction_id LIKE ?", "#{ActiveRecord::Base.sanitize_sql_like(prefix)}%")
        .sum(:amount_cents)
    end

    # Which venture a previously-posted row belongs to. Used by reversal handling,
    # which knows the original payment but must book the reversal against whatever
    # venture that payment was mapped to at the time.
    def self.event_for_row(raw)
      cpt = ::CanonicalPendingTransaction.find_by(raw_pending_donation_transaction_id: raw.id)
      return nil unless cpt

      ::CanonicalPendingEventMapping.find_by(canonical_pending_transaction_id: cpt.id)&.event
    end

    def initialize(event:)
      @event = event
    end

    # Post exactly one ledger line, or return the line that already exists.
    #
    # Not wrapped in its own transaction: callers post a payment and its fee
    # together and need them to commit or roll back as a unit, so the transaction
    # boundary belongs to the caller.
    #
    # `fronted: false` always, and this is not a knob. In HCB `fronted` means the
    # platform advances an org spendable credit against money that has not
    # settled — a balance-sheet decision backed by Hack Club's reserves. Fuime has
    # no reserves and never holds the funds at all; Stripe settlement is T+2 with
    # refund and chargeback risk after that. Fronting here would let a teenager
    # spend money that does not exist yet and that Fuime could not cover.
    def post!(key:, amount_cents:, memo:, date:)
      existing = self.class.find_row(key)
      if existing
        Rails.logger.info("[Fuime] ledger key #{key} already posted; skipping")
        return existing
      end

      raw = ::RawPendingDonationTransaction.create!(
        donation_transaction_id: key,
        amount_cents: amount_cents.to_i,
        date_posted: date
      )

      cpt = ::CanonicalPendingTransaction.create!(
        date: raw.date,
        memo: memo,
        amount_cents: raw.amount_cents,
        raw_pending_donation_transaction_id: raw.id,
        fronted: false
      )

      ::CanonicalPendingEventMapping.create!(
        canonical_pending_transaction_id: cpt.id,
        event_id: @event.id
      )

      Rails.logger.info(
        "[Fuime] ledger #{key} for #{@event.name}: " \
        "#{format('%+.2f', raw.amount_cents / 100.0)} (cpt=#{cpt.id})"
      )

      raw
    end

  end
end
