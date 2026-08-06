# frozen_string_literal: true

# Fuime: turns a venture's PENDING ledger lines into settled ones once Stripe has
# actually made the money available.
#
# ── Why this exists ──────────────────────────────────────────────────────────
#
# Fuime::ConnectPaymentRecorder posts a CanonicalPendingTransaction when a
# payment succeeds, and VentureLedger deliberately posts it `fronted: false` —
# Fuime has no reserves and never holds the funds, so nothing may count toward a
# balance before Stripe settles it. Correct, but it left the other half missing:
# nothing ever created the SETTLED line, so a venture that took a payment showed
# $0 forever. Found during the first Stripe pass (docs/fuime/STRIPE_PASS.md),
# where a real $25 charge produced cpt#3 and a balance of $0.00.
#
# ── When is Connect money "settled"? ─────────────────────────────────────────
#
# When the charge's balance transaction reports status "available" on the
# venture's own connected account — Stripe's word for "these funds are the
# account holder's to pay out". There is no per-charge Stripe webhook for that
# moment, so this is a sweep on a schedule rather than an event handler.
#
# ── How the settled line is written (Rule 3) ─────────────────────────────────
#
# The ledger pipeline's internals stay untouched. Settled lines enter through
# RawCsvTransactionService::Create — the same entry db/seeds.rb uses — then the
# engine's own Hashed and Canonical imports produce the CanonicalTransaction,
# which is mapped to the venture and linked to its pending twin through
# upstream's CanonicalPendingTransactionService::Settle. The unique indexes on
# canonical_pending_settled_mappings (upstream #14360) make a double-settle
# raise instead of silently double-counting.
#
# Idempotency: the raw CSV row's memo embeds the ledger key, and the sweep
# refuses to create a second raw row with the same memo — so a crash between
# "raw created" and "settled mapping created" resumes instead of duplicating.
#
# Scope: the three payment-group keys (payment, Fuime fee, Stripe processing
# fee), and refund reversal lines — added after refunds were exercised for real
# (re_3U1EHWJvQ1BSjJCo…, docs/fuime/STRIPE_PASS.md). A refund line settles when
# every refund balance transaction on its PaymentIntent reports "available";
# per-refund mapping is deliberately not attempted because the recorder clamps
# cumulative amounts, so one ledger line does not correspond 1:1 to one refund
# object. Dispute-kind reversals remain excluded — disputes have never been
# exercised, and settling them by construction would be guessing.
module Fuime
  class ConnectSettlementSweep
    UNIQUE_BANK_IDENTIFIER = "FUIMECONNECT"

    # Payment-group keys: fuime_{pi}, fuime_fee_{pi}, fuime_stripefee_{pi}.
    PAYMENT_GROUP_KEY = /\Afuime_(?:fee_|stripefee_)?(pi_\w+)\z/

    # Refund reversal keys: fuime_rev_{pi}_refund_{object}_{amount}. The kind is
    # matched literally so dispute-kind keys fall through to "not swept".
    REFUND_REVERSAL_KEY = /\Afuime_rev_(pi_\w+)_refund_/

    def self.sweep_all
      StripeConnectedAccount.where.not(stripe_id: nil).find_each do |account|
        new(event: account.event).sweep!
      rescue Stripe::StripeError => e
        # One venture's Stripe hiccup must not stop the sweep for every other
        # venture; the next run retries this one from scratch.
        Rails.logger.error("[Fuime] settlement sweep failed for event #{account.event_id}: #{e.class}")
      end
    end

    def initialize(event:)
      @event = event
    end

    def sweep!
      settled = 0

      groups = unsettled_groups

      groups[:payments].each do |intent_id, pendings|
        next unless available?(intent_id)

        pendings.each do |cpt|
          settle_one!(cpt)
          settled += 1
        end
      end

      groups[:refunds].each do |intent_id, pendings|
        next unless refunds_available?(intent_id)

        pendings.each do |cpt|
          settle_one!(cpt)
          settled += 1
        end
      end

      settled
    end

    private

    def account
      @account ||= @event.stripe_connected_account
    end

    # This venture's Fuime-keyed pendings that have no settled twin yet, grouped
    # by the PaymentIntent they came from so one Stripe lookup covers the whole
    # group (payment + both fee lines settle together — they are one charge).
    def unsettled_groups
      cpts = ::CanonicalPendingTransaction
             .joins(:canonical_pending_event_mapping)
             .joins(:raw_pending_donation_transaction)
             .where(canonical_pending_event_mappings: { event_id: @event.id })
             .where("raw_pending_donation_transactions.donation_transaction_id LIKE 'fuime\\_%'")
             .where.missing(:canonical_pending_settled_mapping)

      groups = { payments: Hash.new { |h, k| h[k] = [] }, refunds: Hash.new { |h, k| h[k] = [] } }
      cpts.each do |cpt|
        key = cpt.raw_pending_donation_transaction.donation_transaction_id
        if (match = PAYMENT_GROUP_KEY.match(key))
          groups[:payments][match[1]] << cpt
        elsif (match = REFUND_REVERSAL_KEY.match(key))
          groups[:refunds][match[1]] << cpt
        end
      end
      groups
    end

    def refunds_available?(intent_id)
      refunds = Stripe::Refund.list(
        { payment_intent: intent_id, expand: ["data.balance_transaction"] },
        { api_key: StripeService.secret_key, stripe_account: account.stripe_id }
      ).data
      refunds.any? && refunds.all? { |r| r.balance_transaction&.status == "available" }
    end

    def available?(intent_id)
      intent = Stripe::PaymentIntent.retrieve(
        { id: intent_id, expand: ["latest_charge.balance_transaction"] },
        { api_key: StripeService.secret_key, stripe_account: account.stripe_id }
      )
      intent.latest_charge&.balance_transaction&.status == "available"
    end

    def settle_one!(cpt)
      key = cpt.raw_pending_donation_transaction.donation_transaction_id
      memo = "#{cpt.memo} [#{key}]"

      # Reuse an existing raw row rather than creating a duplicate — see the
      # idempotency note in the header.
      raw = ::RawCsvTransaction.find_by(unique_bank_identifier: UNIQUE_BANK_IDENTIFIER, memo:) ||
            ::RawCsvTransactionService::Create.new(
              unique_bank_identifier: UNIQUE_BANK_IDENTIFIER,
              date: Time.current.iso8601(3),
              memo:,
              # RawCsvTransaction monetizes :amount_cents, so `amount` is DOLLARS
              # — passing cents here settles every line at 100x its value, which
              # is how the first spec run posted $2,500 for a $25 sale.
              # BigDecimal, not Float, so odd cents stay exact.
              amount: cpt.amount_cents.to_d / 100
            ).run

      ::TransactionEngine::HashedTransactionService::RawCsvTransaction::Import.new.run
      ::TransactionEngine::CanonicalTransactionService::Import::All.new.run

      hashed = ::HashedTransaction.find_by!(raw_csv_transaction_id: raw.id)
      ct = ::CanonicalTransaction
           .joins(:canonical_hashed_mappings)
           .find_by!(canonical_hashed_mappings: { hashed_transaction_id: hashed.id })

      ::CanonicalEventMapping.find_or_create_by!(canonical_transaction: ct, event: @event)

      ::CanonicalPendingTransactionService::Settle.new(
        canonical_transaction: ct,
        canonical_pending_transaction: cpt
      ).run!

      Rails.logger.info("[Fuime] settled #{key} for #{@event.name}: ct=#{ct.id} cpt=#{cpt.id}")
    end

  end
end
