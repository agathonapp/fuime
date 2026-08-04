# frozen_string_literal: true

# Fuime: put card spend on the venture's ledger.
#
# This is the half of the card feature that is actually the product. A card that
# works is a commodity; a card whose every purchase lands categorised on the
# business's books, ready for a receipt, is the bookkeeping story Fuime is selling.
#
# ── Why only `issuing_transaction.created` ──────────────────────────────────
#
# Stripe emits authorizations (`issuing_authorization.*`) before transactions. An
# authorization is a hold, not a purchase: it can expire, be reversed, or capture for
# a different amount than it reserved (a fuel pump reserving $100 and capturing $40 is
# the classic case). Posting authorizations would put phantom expenses on a
# teenager's books and understate their profit until something reconciled them.
#
# The Transaction object is the settled fact, so that is what the ledger records.
# The cost of that choice is honest and worth naming: the ledger lags a purchase by
# up to a couple of days, so a teen who just tapped their card will not see it
# immediately.
#
# ── Card spend is an EXPENSE, unlike a payout ───────────────────────────────
#
# A payout moves already-earned money to the family's own bank and is excluded from
# Fuime::TaxTrackerService for that reason. A card purchase genuinely spends money on
# the business, so it is a deductible expense and is deliberately NOT excluded. The
# memo is worded to avoid every pattern in `EXCLUDED_MEMO_PATTERNS` — in particular it
# must not contain "transfer" or "payout" — and a spec pins that.
module Fuime
  class ConnectCardRecorder
    HANDLED_TYPES = %w[issuing_transaction.created].freeze

    # Stripe Issuing transaction types. A capture is money leaving; a refund is money
    # coming back to the card.
    CAPTURE = "capture"
    REFUND = "refund"

    def initialize(event:)
      @stripe_event = event
    end

    def handle
      return nil unless HANDLED_TYPES.include?(@stripe_event.type)

      transaction = @stripe_event.data.object
      record_transaction(transaction)
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
          Rails.logger.info("[Fuime] #{@stripe_event.type} for unknown account #{account_id}") if record.blank?
          record&.event
        end
      end
    end

    def record_transaction(transaction)
      return nil if venture.blank?

      # Sign is derived from `type`, not from `amount`. Stripe reports Issuing
      # transaction amounts as negative for a capture, but relying on that means a
      # sign convention change silently inverts a teenager's expenses into income.
      # `amount.abs` plus an explicit type decision cannot flip.
      cents = transaction.amount.to_i.abs
      return nil if cents.zero?

      signed_cents =
        case transaction.type
        when CAPTURE then -cents
        when REFUND then cents
        else
          Rails.logger.info(
            "[Fuime] issuing transaction #{transaction.id} has unhandled type " \
            "#{transaction.type.inspect}; not posted"
          )
          return nil
        end

      VentureLedger.new(event: venture).post!(
        key: VentureLedger.card_transaction_key(transaction.id),
        amount_cents: signed_cents,
        memo: memo_for(transaction),
        date: posted_date(transaction)
      )
    end

    # "Card purchase — Acme Supplies", or the refund equivalent.
    #
    # The merchant name is the whole value of this line to a teenager doing their
    # books, so it comes first after the label. Worded to avoid every
    # TaxTrackerService exclusion pattern: card spend must stay countable as a
    # deductible expense.
    def memo_for(transaction)
      # Deeply converted: `to_h` is shallow and nested StripeObjects have no `dig`.
      merchant = StripeHash.deep(transaction).dig(:merchant_data, :name).presence
      label = transaction.type == REFUND ? "Card refund" : "Card purchase"

      merchant.present? ? "#{label} — #{merchant}" : label
    end

    def posted_date(transaction)
      created = transaction.respond_to?(:created) ? transaction.created : nil
      created.present? ? Time.at(created).to_date : Date.current
    end

  end
end
