# frozen_string_literal: true

# Fuime: keep the local mirror of a venture's Stripe account in step with Stripe.
#
# Separate from Fuime::PaymentWebhookHandler because these are a different class
# of event arriving on a different endpoint. Connected-account events carry a
# top-level `account` field naming the connected account they came from; platform
# events do not. That field, not metadata, is the reliable join — a
# `account.updated` event has no Fuime metadata on it at all.
#
# Why this matters more than it looks: without it, a guardian finishes onboarding,
# Stripe verifies them ten minutes later, and Fuime never finds out. The venture's
# storefront stays dark and nobody can explain why. `account.updated` is the only
# signal that arrives when verification completes asynchronously, which is the
# normal case.
#
# ── Two kinds of event, one endpoint ────────────────────────────────────────
#
# Stripe delivers both account-lifecycle events and the venture's actual PAYMENTS
# to this same connected-account endpoint, so this class is the dispatcher for
# both. The money half is delegated to Fuime::ConnectPaymentRecorder rather than
# handled here, because ledger writes and account-mirror writes have nothing in
# common beyond arriving together and are worth failing independently.
#
# Deliberately NOT dispatched here: Fuime::PaymentWebhookHandler. It resolves the
# venture from `fuime_event_id` metadata, which Fuime::PaymentLinkService still
# writes onto direct charges, so running it on this endpoint would post the same
# payment through a second code path — with the fee COMPUTED from the plan rather
# than read from what Stripe actually deducted. The shared ledger keys mean only
# one of the two would win, and which one is a race. The pooled handler stays on
# the platform endpoint where its metadata assumption holds.
module Fuime
  class ConnectWebhookHandler
    HANDLED_TYPES = %w[
      account.updated
      account.application.deauthorized
    ].freeze

    def initialize(event:)
      @event = event
    end

    def handle
      # Money events first: a venture's ledger is the product, and the account
      # mirror is metadata about it.
      return ConnectPaymentRecorder.new(event: @event).handle if payment_event?
      return ConnectPayoutRecorder.new(event: @event).handle if payout_event?
      return ConnectCardRecorder.new(event: @event).handle if card_event?

      return unless HANDLED_TYPES.include?(@event.type)

      case @event.type
      when "account.updated"
        handle_account_updated
      when "account.application.deauthorized"
        handle_deauthorized
      end
    end

    private

    def payment_event?
      ConnectPaymentRecorder::HANDLED_TYPES.include?(@event.type)
    end

    def payout_event?
      ConnectPayoutRecorder::HANDLED_TYPES.include?(@event.type)
    end

    def card_event?
      ConnectCardRecorder::HANDLED_TYPES.include?(@event.type)
    end

    def handle_account_updated
      # The Account object is the event payload itself, so no follow-up API call
      # is needed — which also means no risk of making one without the
      # `stripe_account` context that connected-account resources require.
      account = @event.data.object
      record = StripeConnectedAccount.find_by(stripe_id: account.id)

      if record.blank?
        # Not an error worth alerting on: Stripe delivers events for accounts a
        # platform may have created and abandoned, and replaying old events after
        # a database restore hits this legitimately. Logged so it is visible if it
        # starts happening in volume.
        Rails.logger.info("[Fuime] account.updated for unknown connected account #{account.id}")
        return
      end

      was_ready = record.ready_for_payments?
      record.sync_from_stripe!(account)

      # Worth a log line at the moment a venture's ability to trade changes:
      # this is the transition that support questions are about, and it is
      # otherwise invisible.
      if was_ready != record.ready_for_payments?
        Rails.logger.info(
          "[Fuime] connected account #{account.id} (event #{record.event_id}) " \
          "payments #{record.ready_for_payments? ? 'ENABLED' : 'DISABLED'}"
        )
      end

      mark_verification_accepted(record)
    end

    # Stripe verifies identity information ASYNCHRONOUSLY, so a successful
    # Fuime::RequirementCollectionService#submit! only means Stripe received the
    # details. This is where it becomes "Stripe accepted them", and the distinction is
    # the difference between telling a family they are verified and telling them the
    # truth.
    #
    # Keyed on requirements clearing rather than on any acceptance field, because Stripe
    # exposes no "we accepted your submission" flag — an empty `currently_due` with
    # nothing pending verification IS the acceptance.
    def mark_verification_accepted(record)
      return if record.requirements_outstanding?
      return if record.requirements_pending_verification.any?

      pending = ::GuardianVerification
                .where(event_id: record.event_id, accepted_at: nil)
                .recent_first
                .first
      return if pending.blank?

      pending.update!(accepted_at: Time.current)

      Rails.logger.info(
        "[Fuime] guardian verification #{pending.id} accepted by Stripe " \
        "(event #{record.event_id}, method #{pending.verification_method})"
      )
    end

    # The guardian disconnected Fuime from their Stripe account. Their account
    # continues to exist and belong to them — Fuime simply loses access, so the
    # local mirror must stop claiming the venture can be paid.
    #
    # Deliberately does NOT delete the row: the venture's payment history refers
    # to it, and destroying the record to represent "we lost access" would erase
    # the evidence of what happened.
    def handle_deauthorized
      connected_account_id = @event.account
      record = StripeConnectedAccount.find_by(stripe_id: connected_account_id)
      return if record.blank?

      record.update!(
        charges_enabled: false,
        payouts_enabled: false,
        capabilities: {},
        disabled_reason: "deauthorized",
        stripe_synced_at: Time.current
      )

      Rails.logger.warn(
        "[Fuime] connected account #{connected_account_id} deauthorized Fuime " \
        "(event #{record.event_id})"
      )
    end

  end
end
