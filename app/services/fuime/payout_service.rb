# frozen_string_literal: true

# Fuime: move money from a venture's Stripe balance to the family's own bank.
#
# This is the "money out" half of the architecture, and the thing that makes the
# whole no-custody story true end to end: the funds are already sitting in the
# guardian's own connected account, and a payout sends them to the guardian's own
# bank. Fuime is issuing an instruction on the account owner's recorded
# authorisation. At no point does Fuime hold, receive, or direct a stranger's
# money, which is exactly what separates this from the pooled model (CLAUDE.md L1).
#
# ── Why approval re-reads the balance ───────────────────────────────────────
#
# A teen requests $80 on Tuesday. A customer charges back $50 on Wednesday. The
# parent approves on Thursday. If approval trusted the stored amount, Stripe would
# reject the payout for insufficient funds and the family would see a failure with
# no explanation. So the live balance is read again at approval and the request is
# refused, in Fuime, with a sentence a parent can act on.
#
# ── Idempotency ─────────────────────────────────────────────────────────────
#
# Two things guard against sending twice: the AASM transition out of `pending`
# (a second approve raises), and a Stripe idempotency key derived from the request
# id (so even a retried HTTP call that already reached Stripe cannot create a
# second payout). Both, because the first protects against concurrent callers and
# the second against a network timeout on a request Stripe actually processed.
module Fuime
  class PayoutService
    class Error < StandardError; end
    class NotSetUp < Error; end
    class PayoutsDisabled < Error; end
    class InsufficientFunds < Error; end
    class StripeRejected < Error; end

    def initialize(event:)
      @event = event
    end

    # What Stripe says can be paid out right now, in cents.
    #
    # `available` rather than `pending`: pending funds are settled-but-not-yet-
    # released and Stripe will refuse to pay them out, so showing them as
    # withdrawable is the "money arrived and then appeared stuck" failure that
    # StripeConnectedAccount#ready_for_payouts? exists to avoid.
    #
    # Returns 0 rather than raising when payments are not set up, because this
    # feeds a balance display that renders on pages a venture reaches before
    # onboarding.
    def available_balance_cents
      return 0 unless account&.stripe_id.present?

      balance = Stripe::Balance.retrieve({}, request_options)
      usd = Array(balance.available).find { |b| b.currency.to_s == "usd" }
      usd&.amount.to_i
    rescue Stripe::StripeError => e
      # Deliberately not re-raised: a balance we cannot read must not take down
      # the venture's dashboard. Logged, and the caller shows "unavailable".
      Rails.logger.error("[Fuime] could not read balance for event #{@event.id}: #{e.message}")
      nil
    end

    # A teen asks. Validates against the live balance so the request a parent sees
    # was affordable at the moment it was made.
    def request!(amount_cents:, requested_by:)
      ensure_payouts_possible!

      available = available_balance_cents
      if available.nil?
        raise StripeRejected, "Fuime could not check this venture's balance with Stripe. Try again in a moment."
      end

      if amount_cents.to_i > available
        raise InsufficientFunds,
              "This venture has #{format_cents(available)} available to pay out, " \
              "which is less than the #{format_cents(amount_cents)} requested."
      end

      PayoutRequest.create!(
        event: @event,
        requested_by:,
        amount_cents: amount_cents.to_i
      )
    end

    # The guardian says yes, and the money actually moves.
    #
    # The Stripe call happens INSIDE the database transaction on purpose, which is
    # the opposite of the usual advice. The reasoning: if the payout succeeds at
    # Stripe and the local commit then fails, Fuime has sent money it has no record
    # of sending, and the next approval would send it again. Holding the
    # transaction open across the API call means a failure to record is a failure
    # to send. The Stripe idempotency key covers the remaining window where Stripe
    # processed a call whose response we never saw.
    def approve!(request:, approver:)
      raise Error, "This payout request has already been decided." unless request.pending?

      ensure_payouts_possible!

      available = available_balance_cents
      if available.nil?
        raise StripeRejected, "Fuime could not confirm the balance with Stripe, so nothing was sent. Try again shortly."
      end

      if request.amount_cents > available
        raise InsufficientFunds,
              "This venture now has only #{format_cents(available)} available, " \
              "so the #{format_cents(request.amount_cents)} request cannot be sent. " \
              "The balance changed after the request was made."
      end

      ActiveRecord::Base.transaction do
        request.approved_by = approver
        request.approved_at = Time.current
        request.approve!

        payout = create_stripe_payout!(request)
        request.update!(stripe_payout_id: payout.id)

        Rails.logger.info(
          "[Fuime] payout #{payout.id} created for event #{@event.id}: " \
          "#{format_cents(request.amount_cents)} approved by user #{approver.id}"
        )

        request
      end
    end

    def reject!(request:, approver:, reason: nil)
      raise Error, "This payout request has already been decided." unless request.pending?

      request.approved_by = nil
      request.rejected_at = Time.current
      request.rejection_reason = reason.presence
      request.reject!
      request.save!
      request
    end

    private

    def account
      @account ||= @event.stripe_connected_account
    end

    def ensure_payouts_possible!
      raise NotSetUp, "This venture hasn't finished payment setup yet." if account&.stripe_id.blank?

      unless account.ready_for_payouts?
        raise PayoutsDisabled,
              "Stripe can't send money to this venture's bank account yet. #{account.status_description}"
      end
    end

    def create_stripe_payout!(request)
      Stripe::Payout.create(
        {
          amount: request.amount_cents,
          currency: "usd",
          # Shows on the family's bank statement. They did not sign up with Stripe
          # and will not recognise a bare descriptor.
          description: "Fuime payout — #{@event.name}",
          metadata: {
            fuime_event_id: @event.id,
            fuime_payout_request_id: request.id,
            fuime_requested_by_user_id: request.requested_by_id,
            fuime_approved_by_user_id: request.approved_by_id
          }
        },
        request_options.merge(idempotency_key: "fuime_payout_request_#{request.id}")
      )
    rescue Stripe::StripeError => e
      # Rolls back the approval: an approved request with no payout behind it
      # would show a family money as sent that never left.
      raise StripeRejected, stripe_failure_message(e)
    end

    # Stripe's raw messages are written for developers. The two cases a family can
    # actually hit are translated; anything else is passed through rather than
    # mistranslated, with the raw text kept for support.
    def stripe_failure_message(error)
      case error.code
      when "balance_insufficient"
        "Stripe reported not enough available funds to send this payout. " \
        "Money from recent sales can take a couple of days to become available."
      when "payouts_not_allowed"
        "Stripe is not currently allowing payouts from this account. " \
        "The account owner may need to finish verification."
      else
        "Stripe could not send this payout: #{error.message}"
      end
    end

    # See Fuime::ConnectOnboardingService for why the key is always explicit and
    # never taken from the global Stripe.api_key.
    def request_options
      { api_key: StripeService.secret_key, stripe_account: account.stripe_id }
    end

    def format_cents(cents)
      ActiveSupport::NumberHelper.number_to_currency(cents.to_i / 100.0)
    end

  end
end
