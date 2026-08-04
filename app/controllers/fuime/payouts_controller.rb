# frozen_string_literal: true

# Fuime: the screen where a teen asks for their money and a guardian decides.
#
# ── The authorization shape ─────────────────────────────────────────────────
#
# The mirror image of Fuime::PaymentSetupsController. There, the guardian acts and
# the teen only watches. Here BOTH act, on different verbs, and keeping them apart
# is the whole point:
#
#   #index    both — the teen sees the balance, the guardian sees the decision
#   #create   the TEEN (a member) asks
#   #approve  the GUARDIAN alone decides, because they own the account and funds
#   #reject   the GUARDIAN alone
#
# `decide_payout?` deliberately excludes members, so a teen cannot approve their
# own request, and PayoutRequest re-validates the same rule at the record level.
# Two layers because this is the single control that makes "the parent owns the
# money" true rather than decorative (CLAUDE.md L2).
module Fuime
  class PayoutsController < ApplicationController
    before_action :set_event
    before_action :set_request, only: [:approve, :reject]

    def index
      authorize @event, :payouts?

      @connected_account = @event.stripe_connected_account
      # nil means Stripe could not be reached; the view distinguishes that from a
      # genuine zero, because "you have $0" and "we can't tell you right now" are
      # different sentences for a teenager waiting on money.
      @available_cents = service.available_balance_cents
      @pending_request = @event.payout_requests.awaiting_approval.first
      @history = @event.payout_requests.recent_first.limit(25)

      @can_request = policy(@event).request_payout?
      @can_decide = policy(@event).decide_payout?
    end

    def create
      authorize @event, :request_payout?

      service.request!(
        amount_cents: amount_cents_param,
        requested_by: current_user
      )

      redirect_to fuime_payouts_path(event_slug: @event.slug),
                  notice: "Your payout request was sent to your guardian to approve."
    rescue Fuime::PayoutService::Error => e
      # Service errors are already written for a family to read, so they are
      # surfaced verbatim rather than replaced with a generic message.
      redirect_to fuime_payouts_path(event_slug: @event.slug), alert: e.message
    rescue ActiveRecord::RecordInvalid => e
      redirect_to fuime_payouts_path(event_slug: @event.slug),
                  alert: e.record.errors.full_messages.to_sentence
    end

    def approve
      authorize @event, :decide_payout?

      service.approve!(request: @request, approver: current_user)

      redirect_to fuime_payouts_path(event_slug: @event.slug),
                  notice: "Approved. Stripe is sending #{humanized_amount(@request.amount_cents)} " \
                          "to your bank account."
    rescue Fuime::PayoutService::Error => e
      redirect_to fuime_payouts_path(event_slug: @event.slug), alert: e.message
    rescue ActiveRecord::RecordInvalid => e
      redirect_to fuime_payouts_path(event_slug: @event.slug),
                  alert: e.record.errors.full_messages.to_sentence
    end

    def reject
      authorize @event, :decide_payout?

      service.reject!(
        request: @request,
        approver: current_user,
        reason: params[:rejection_reason]
      )

      redirect_to fuime_payouts_path(event_slug: @event.slug),
                  notice: "You've declined this payout request."
    rescue Fuime::PayoutService::Error => e
      redirect_to fuime_payouts_path(event_slug: @event.slug), alert: e.message
    end

    private

    def set_event
      @event = Event.find_by!(slug: params[:event_slug])
    end

    # Scoped through the venture, not found globally: a bare
    # `PayoutRequest.find(params[:id])` would let a guardian of one venture act on
    # another venture's request by id, since `decide_payout?` is checked against
    # @event rather than against the request.
    def set_request
      @request = @event.payout_requests.find(params[:id])
    end

    def service
      @service ||= Fuime::PayoutService.new(event: @event)
    end

    # Accepts what a person types — "40", "40.00", "$40.00", "1,240.50" — because
    # the alternative is a teenager being told their input is invalid for having a
    # dollar sign in it. Anything unparseable becomes 0 and is refused by the
    # model's minimum, which produces a sentence about the amount rather than a
    # stack trace.
    def amount_cents_param
      raw = params[:amount].to_s.gsub(/[^\d.]/, "")
      return 0 if raw.blank?

      (BigDecimal(raw) * 100).round
    rescue ArgumentError
      0
    end

    def humanized_amount(cents)
      ActiveSupport::NumberHelper.number_to_currency(cents.to_i / 100.0)
    end

  end
end
