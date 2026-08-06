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

    # Money a school paid a student directly, out of the balance held in the school's
    # own Stripe account.
    #
    # The only Fuime ledger key that is NOT derived from a Stripe object id, and the
    # reason is structural rather than an oversight: on this path Stripe never moves
    # anything, so there is no object to key on. The PayoutRequest is the authority
    # for the fact and for the approval behind it, which makes its id the right key —
    # and it keeps the same guarantee as every other key here, that one real-world
    # movement produces at most one ledger line no matter how many times somebody
    # clicks "mark as paid".
    def self.personal_transfer_key(payout_request_id)
      "fuime_schoolpaid_#{payout_request_id}"
    end

    # A school adding its own money to its own Stripe balance, so it has something to
    # award. Keyed on the Stripe Topup id for the same reason payouts key on the payout:
    # a top-up can be created from the Stripe Dashboard with no Fuime row behind it, and
    # the balance moved either way.
    #
    # The memo deliberately contains neither "school award" nor "payout", so
    # Fuime::TaxTrackerService's memo exclusions do not catch it — but see
    # Fuime::ConnectFundingRecorder for why it must still be excluded from income. A
    # school moving its own money between two of its own accounts has not earned
    # anything.
    def self.funding_key(topup_id)
      "fuime_funding_#{topup_id}"
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

    # Money a school moved from its own subledger to a student's, or back.
    #
    # Two keys per award, because the award IS two ledger lines — the school's balance
    # falls and the student's rises by the same amount — and each needs its own
    # idempotency key. Reattribution inside one Stripe account is only safe while those
    # two are inseparable, which is why they share a prefix and post in one transaction.
    def self.award_key(award_id, side)
      "fuime_award_#{award_id}_#{side}"
    end

    # A voided award, reversing both sides. Keyed separately rather than by deleting the
    # original lines: the money did move, a school then took it back, and a ledger that
    # erased the first half would misstate what a student's balance did and when.
    def self.award_void_key(award_id, side)
      "fuime_awardvoid_#{award_id}_#{side}"
    end

    # ── Settled lines, for money that was never in transit ──────────────────
    #
    # `#post!` writes a PENDING line, which is right for a Stripe charge: the money
    # exists but Stripe has not released it, and Fuime::ConnectSettlementSweep promotes
    # it days later when Stripe says "available".
    #
    # A school award has no such phase. The money is already in the school's available
    # balance — the award only changes which subledger it belongs to, and no Stripe call
    # happens at all. Posting it pending would mean a student awarded $100 could not
    # spend it until a sweep with nothing to wait for ran, and `Event#balance_v2_cents`
    # deliberately excludes pending INCOMING money, so the award would be invisible in
    # exactly the figure Fuime::PayoutService's cap reads.
    #
    # So this writes the settled line directly, through the same entry point the sweep's
    # final step uses. Rule 3 holds: the pipeline's internals are untouched and it is
    # only being fed.
    #
    # Idempotency works as the sweep's does — the key is embedded in the memo and a
    # matching raw row is reused rather than duplicated — so a crash between an award's
    # two sides resumes instead of double-posting one of them.
    UNIQUE_BANK_IDENTIFIER = "FUIMEINTERNAL"

    def self.settled_memo(key, memo)
      "#{memo} [#{key}]"
    end

    def self.find_settled_row(key, memo)
      ::RawCsvTransaction.find_by(
        unique_bank_identifier: UNIQUE_BANK_IDENTIFIER,
        memo: settled_memo(key, memo)
      )
    end

    def initialize(event:)
      @event = event
    end

    # Post one settled line for this event, or return the transaction already there.
    #
    # Returns the CanonicalTransaction. Not wrapped in its own DB transaction, for the
    # same reason as #post!: an award's two sides must commit or roll back together, so
    # the boundary belongs to the caller.
    def post_settled!(key:, amount_cents:, memo:, date:)
      full_memo = self.class.settled_memo(key, memo)

      raw = self.class.find_settled_row(key, memo) ||
            ::RawCsvTransactionService::Create.new(
              unique_bank_identifier: UNIQUE_BANK_IDENTIFIER,
              date: date.to_time.iso8601(3),
              memo: full_memo,
              # RawCsvTransaction monetizes :amount_cents, so `amount` is DOLLARS.
              # Passing cents posts every line at 100x — the bug the settlement sweep's
              # comment records paying for once already. BigDecimal so odd cents stay
              # exact, and negatives are legitimate here (the school's side is a debit).
              amount: amount_cents.to_d / 100
            ).run

      ::TransactionEngine::HashedTransactionService::RawCsvTransaction::Import.new.run
      ::TransactionEngine::CanonicalTransactionService::Import::All.new.run

      hashed = ::HashedTransaction.find_by!(raw_csv_transaction_id: raw.id)
      ct = ::CanonicalTransaction
           .joins(:canonical_hashed_mappings)
           .find_by!(canonical_hashed_mappings: { hashed_transaction_id: hashed.id })

      ::CanonicalEventMapping.find_or_create_by!(canonical_transaction: ct, event: @event)

      Rails.logger.info(
        "[Fuime] settled ledger #{key} for #{@event.name}: " \
        "#{format('%+.2f', ct.amount_cents / 100.0)} (ct=#{ct.id})"
      )

      ct
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
