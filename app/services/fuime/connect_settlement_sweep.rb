# frozen_string_literal: true

# Fuime: turns a venture's PENDING ledger lines into settled ones once Stripe has
# actually made the money available.
#
# ── Why this exists ──────────────────────────────────────────────────────────
#
# The money-in recorder posts a CanonicalPendingTransaction when a payment
# succeeds — Fuime::ConnectPaymentRecorder under Connect, and
# Fuime::PaymentWebhookHandler under merchant-of-record — and VentureLedger
# deliberately posts it `fronted: false` —
# Fuime has no reserves and never holds the funds, so nothing may count toward a
# balance before Stripe settles it. Correct, but it left the other half missing:
# nothing ever created the SETTLED line, so a venture that took a payment showed
# $0 forever. Found during the first Stripe pass (docs/fuime/STRIPE_PASS.md),
# where a real $25 charge produced cpt#3 and a balance of $0.00.
#
# ── When is the money "settled"? ─────────────────────────────────────────────
#
# When the charge's balance transaction reports status "available" — Stripe's word
# for "these funds are the account holder's to pay out". There is no per-charge
# Stripe webhook for that moment, so this is a sweep on a schedule rather than an
# event handler.
#
# WHOSE balance transaction depends on which model is running, and the class name
# is now half a lie: under Connect it is the venture's own connected account, and
# under merchant-of-record it is FUIME's platform balance, because the charge was
# Fuime's own sale. See #stripe_options. The name is kept because renaming a class
# referenced by a scheduled job, its spec and two docs is a worse trade than a
# paragraph explaining it.
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

    # Fuime: which ventures to sweep, and why the answer changed under MoR.
    #
    # This used to iterate StripeConnectedAccount, which was the right driver while
    # every payment lived on a guardian-owned account: no account, no charges, no
    # work. Under merchant-of-record NO venture has a connected account — charges
    # are on Fuime's own platform balance — so that query returns zero rows and the
    # scheduled job did nothing at all, silently. Sales stayed pending forever,
    # `PayablesLedger#gross_sales_cents` stayed $0, and the weekly payout run would
    # have generated $0 for every operator. Found 2026-08-20 against a real
    # test-mode charge, one day before the first live sales.
    #
    # Driving off the unsettled lines themselves is correct under both models and
    # cannot drift out of sync with either: a venture needs sweeping exactly when it
    # has a Fuime-keyed pending line with no settled twin. It also self-limits — a
    # venture with nothing outstanding is never visited, which is most of them.
    def self.sweep_all
      events_with_unsettled_lines.find_each do |event|
        new(event:).sweep!
      rescue Stripe::StripeError => e
        # One venture's Stripe hiccup must not stop the sweep for every other
        # venture; the next run retries this one from scratch.
        Rails.logger.error("[Fuime] settlement sweep failed for event #{event.id}: #{e.class}")
      end
    end

    def self.events_with_unsettled_lines
      ::Event.where(
        id: ::CanonicalPendingTransaction
              .joins(:canonical_pending_event_mapping)
              .joins(:raw_pending_donation_transaction)
              .where("raw_pending_donation_transactions.donation_transaction_id LIKE 'fuime\\_%'")
              .where.missing(:canonical_pending_settled_mapping)
              .select("canonical_pending_event_mappings.event_id")
      )
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
      # The charge lives on whichever account took it, which for a school student
      # venture is the school's. See Event#payment_account.
      @account ||= @event.payment_account
    end

    # Which Stripe account to ask about a charge — the one that took it.
    #
    # Under merchant-of-record that is Fuime's own platform account, so there is no
    # `stripe_account:` at all: omitting it IS the request for the platform. Under
    # Connect it is the venture's (or its school's) connected account.
    #
    # Keyed on the flag rather than on `account.present?`, deliberately. A venture
    # onboarded before the MoR cutover still has a connected account row, but its
    # charges since the cutover landed on the platform — so presence of an account
    # is not evidence of where the money is, and guessing from it would send the
    # lookup to an account where the PaymentIntent does not exist.
    #
    # Raises rather than falling back when Connect is on and no account exists:
    # that combination previously surfaced as `NoMethodError: undefined method
    # 'stripe_id' for nil` from inside a Stripe call, which is a confusing way to
    # learn that a venture was never onboarded.
    def stripe_options
      return { api_key: StripeService.secret_key } if ::Fuime::Features.merchant_of_record?

      unless account&.stripe_id
        raise ArgumentError, "Event #{@event.id} has no Stripe account to settle against"
      end

      { api_key: StripeService.secret_key, stripe_account: account.stripe_id }
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
        stripe_options
      ).data
      refunds.any? && refunds.all? { |r| r.balance_transaction&.status == "available" }
    end

    def available?(intent_id)
      intent = Stripe::PaymentIntent.retrieve(
        { id: intent_id, expand: ["latest_charge.balance_transaction"] },
        stripe_options
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
