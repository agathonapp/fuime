# frozen_string_literal: true

# Fuime: post a school's top-up to its ledger, on Stripe's word.
#
# The third money-in recorder, after Fuime::ConnectPaymentRecorder (sales) and
# Fuime::ConnectPayoutRecorder (money out). Same shape, same discipline: the webhook
# is Stripe stating what it did, and in any disagreement the balance follows Stripe.
#
# ── Why the ledger line waits for `topup.succeeded` ─────────────────────────
#
# A top-up is an ACH pull and takes days. `topup.created` means Stripe accepted the
# instruction; `topup.succeeded` means the money is in the balance. Only the second
# one is worth a ledger line, for a reason with teeth:
# Fuime::SchoolAwardService#available_to_award_cents spends against
# `Event#balance_v2_cents`. Posting at creation would let a school award money still
# in transit, and Fuime::PayoutService caps a student's withdrawal against the same
# balance — so a bounced top-up would mean one student had already withdrawn another
# student's revenue. Credit only what has landed.
#
# There is no pending ledger line either. `balance_v2_cents` excludes pending INCOMING
# money by design (see Fuime::SchoolAwardService), so a pending credit would be
# invisible to the only question anyone asks of it. In-flight top-ups are shown from
# the SchoolFunding row instead, which is honest about what they are.
#
# ── Top-ups Fuime did not create ────────────────────────────────────────────
#
# A business office can add funds from the Stripe Dashboard, and Stripe fires these
# same events when they do. So the ledger write does not require a SchoolFunding row
# to exist — it creates one. Fuime::ConnectPayoutRecorder documents the same principle
# for payouts; it matters more here, because whether a Stripe-liability connected
# account may create top-ups through the API is UNVERIFIED (see
# Fuime::SchoolFundingService). If it turns out it may not, the Dashboard remains a
# working path and this recorder is what makes the ledger agree with it. That is why
# the recorder, not the button, is the feature.
module Fuime
  class ConnectFundingRecorder
    HANDLED_TYPES = %w[
      topup.created
      topup.succeeded
      topup.failed
      topup.canceled
      topup.reversed
    ].freeze

    # Pinned by Fuime::TaxTrackerService::EXCLUDED_MEMO_PATTERNS. A school moving its
    # own money between its own accounts is not income; changing this string without
    # changing that list would put a school's transfers into a Schedule C estimate.
    MEMO = "Funds added from bank account"

    def initialize(event:)
      @stripe_event = event
    end

    def handle
      return nil unless HANDLED_TYPES.include?(@stripe_event.type)

      topup = @stripe_event.data.object

      case @stripe_event.type
      when "topup.created"
        track(topup, status: "pending")
      when "topup.succeeded"
        record_credit(topup)
      when "topup.failed", "topup.canceled"
        mark_unsuccessful(topup)
      when "topup.reversed"
        record_reversal(topup)
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

    # Find the local row for this top-up, or build one. A top-up created in the Stripe
    # Dashboard has no row yet, and a top-up Fuime created has one with no Stripe id
    # until the API answers — so the id is claimed here on first sight of the webhook.
    def track(topup, status:)
      return nil if venture.blank?

      amount_cents = topup.amount.to_i
      return nil if amount_cents <= 0

      funding = ::SchoolFunding.find_by(stripe_topup_id: topup.id)
      funding ||= ::SchoolFunding.new(
        event: venture,
        amount_cents:,
        stripe_topup_id: topup.id
      )

      # Never walk a status backwards. Stripe does not guarantee webhook ordering, and
      # a `topup.created` arriving after its `topup.succeeded` would otherwise unwind a
      # landed top-up back to pending — leaving the ledger credited and the row saying
      # the money had not arrived.
      return funding if funding.persisted? && funding.succeeded? && status == "pending"

      funding.status = status
      # Set here rather than by a follow-up update, because the DB constraint
      # `school_fundings_succeeded_is_evidenced` requires succeeded rows to carry
      # their evidence — and it is right to: a row claiming money landed without a
      # timestamp saying when is the shape of the bug this whole feature avoids.
      # (The constraint caught this being written the other way round.)
      funding.succeeded_at ||= Time.current if status == "succeeded"
      funding.save!
      funding
    end

    # The money is in the school's Stripe balance. Post it, once.
    #
    # Settled rather than pending, because by the time this event fires the funds are
    # available — the distinction Fuime::VentureLedger#post_settled! exists for.
    def record_credit(topup)
      return nil if venture.blank?

      amount_cents = topup.amount.to_i
      return nil if amount_cents <= 0

      track(topup, status: "succeeded")

      VentureLedger.new(event: venture).post_settled!(
        key: VentureLedger.funding_key(topup.id),
        amount_cents:,
        memo: MEMO,
        date: posted_date(topup)
      )
    end

    def mark_unsuccessful(topup)
      status = @stripe_event.type == "topup.canceled" ? "canceled" : "failed"
      funding = track(topup, status:)
      return nil if funding.blank?

      funding.update!(
        failure_code: topup.try(:failure_code),
        failure_message: failure_message_for(topup)
      )

      Rails.logger.warn(
        "[Fuime] school funding #{funding.id} #{status}: #{topup.id} " \
        "(#{funding.failure_code || 'no code'})"
      )

      funding
    end

    # Stripe pulled the money back out after it had landed — an ACH return arriving
    # after settlement. Rare, and the one case where a school's balance can go down
    # without anyone spending anything.
    #
    # Only reverses a credit that was actually posted, for the same reason
    # Fuime::ConnectPayoutRecorder checks before crediting a failed payout back:
    # reversing a line that was never written would invent a debit.
    def record_reversal(topup)
      return nil if venture.blank?

      amount_cents = topup.amount.to_i
      return nil if amount_cents <= 0

      if VentureLedger.find_settled_row(VentureLedger.funding_key(topup.id), MEMO).blank?
        Rails.logger.info(
          "[Fuime] topup.reversed #{topup.id}: no credit was recorded, nothing to reverse"
        )
        return nil
      end

      funding = track(topup, status: "failed")
      funding&.update!(failure_message: "This top-up was returned by the bank after it had cleared.")

      VentureLedger.new(event: venture).post_settled!(
        key: "#{VentureLedger.funding_key(topup.id)}_rev",
        amount_cents: -amount_cents,
        memo: "Funds added — returned by bank",
        date: posted_date(topup)
      )
    end

    def failure_message_for(topup)
      message = topup.try(:failure_message)
      return message if message.present?

      return "Stripe cancelled this top-up." if @stripe_event.type == "topup.canceled"

      "The bank account on file could not be debited for this top-up."
    end

    def posted_date(topup)
      created = topup.try(:created)
      created.present? ? Time.at(created).to_date : Date.current
    end

  end
end
