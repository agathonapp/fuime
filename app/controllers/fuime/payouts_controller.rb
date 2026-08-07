# frozen_string_literal: true

# Fuime: the screen where a teen asks for their money and a guardian decides.
#
# ── The authorization shape ─────────────────────────────────────────────────
#
# The mirror image of Fuime::PaymentSetupsController. There, the guardian acts and
# the teen only watches. Here BOTH act, on different verbs, and keeping them apart
# is the whole point:
#
#   #index    both — the teen sees the balance, the adult sees the decision
#   #create   the TEEN (a member) asks
#   #approve  the RESPONSIBLE ADULT alone decides, because they own the account and funds
#   #reject   the RESPONSIBLE ADULT alone
#   #settle   a school MANAGER confirms the school has actually paid the student
#
# `decide_payout?` deliberately excludes members, so a teen cannot approve their
# own request, and PayoutRequest re-validates the same rule at the record level.
# Two layers because this is the single control that makes "the parent owns the
# money" true rather than decorative (CLAUDE.md L2).
#
# ── Who the responsible adult is ────────────────────────────────────────────
#
# A guardian on a family venture; a manager (guide or business office) on one inside
# a school programme, where no guardian exists by design. EventPolicy makes that
# substitution; this controller does not know the difference.
#
# ── Why #settle exists on only one of the two paths ─────────────────────────
#
# On a family venture Stripe sends the money the instant it is approved, and
# `payout.paid` is what says it landed — there is nothing for a human to assert. On
# a school venture the balance is in the school's account and Stripe cannot pay a
# student's own bank from it, so approving is an authorisation and the school
# settles it separately. See AddDestinationToPayoutRequests for why Fuime is not the
# rail there.
module Fuime
  class PayoutsController < ApplicationController
    before_action :set_event
    before_action :set_request, only: [:approve, :reject, :settle]

    def index
      authorize @event, :payouts?

      # The account the balance actually sits in — the school's, for a student
      # venture inside a programme.
      @connected_account = @event.payment_account
      # nil means Stripe could not be reached; the view distinguishes that from a
      # genuine zero, because "you have $0" and "we can't tell you right now" are
      # different sentences for a teenager waiting on money.
      @available_cents = service.available_balance_cents
      @pending_request = @event.payout_requests.awaiting_approval.first
      # Approved school transfers the business office still has to pay. Shown
      # separately from history because they are work outstanding, not a record.
      @unsettled_requests = @event.payout_requests.awaiting_settlement.recent_first
      @history = @event.payout_requests.recent_first.limit(25)

      # Which of the two money-out shapes this venture has. Drives the copy, which
      # otherwise told a school student to ask a guardian who does not exist.
      @school_settled = @event.shares_payment_account?

      @can_request = policy(@event).request_payout?
      @can_decide = policy(@event).decide_payout?
      @can_settle = policy(@event).settle_payout?
    end

    def create
      authorize @event, :request_payout?

      service.request!(
        amount_cents: amount_cents_param,
        requested_by: current_user,
        destination_note: destination_note_param
      )

      redirect_to fuime_payouts_path(event_slug: @event.slug),
                  notice: request_sent_notice
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

      redirect_to fuime_payouts_path(event_slug: @event.slug), notice: approved_notice
    rescue Fuime::PayoutService::Error => e
      redirect_to fuime_payouts_path(event_slug: @event.slug), alert: e.message
    rescue ActiveRecord::RecordInvalid => e
      redirect_to fuime_payouts_path(event_slug: @event.slug),
                  alert: e.record.errors.full_messages.to_sentence
    end

    # The school confirming it has actually paid the student. Separate authorization
    # from #approve on purpose — see EventPolicy#settle_payout?.
    def settle
      authorize @event, :settle_payout?

      service.settle!(request: @request, settled_by: current_user)

      redirect_to fuime_payouts_path(event_slug: @event.slug),
                  notice: "Recorded as paid. #{humanized_amount(@request.amount_cents)} " \
                          "has come off this venture's balance."
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

    # Where the student says they want it sent, in their own words. Never bank
    # details — see the migration for why Fuime deliberately has nowhere to put
    # them. Bounded and control-stripped because it ends up in a ledger memo an
    # adult reads.
    MAX_DESTINATION_NOTE_LENGTH = 120

    def destination_note_param
      params[:destination_note].to_s.gsub(/[[:cntrl:]]/, "").strip
                               .truncate(MAX_DESTINATION_NOTE_LENGTH).presence
    end

    # The two paths end differently, so they cannot share one sentence. Telling a
    # school student their request "was sent to your guardian" names a person who
    # does not exist, which is the copy bug that made the wedged state confusing as
    # well as broken.
    def request_sent_notice
      if @event.shares_payment_account?
        "Your request was sent to the school to approve."
      else
        "Your payout request was sent to your guardian to approve."
      end
    end

    def approved_notice
      if @request.personal_transfer?
        "Approved. The school will pay #{humanized_amount(@request.amount_cents)} to " \
        "#{@request.requested_by.first_name} and mark it as paid here once it's gone."
      else
        "Approved. Stripe is sending #{humanized_amount(@request.amount_cents)} " \
        "to your bank account."
      end
    end

    def humanized_amount(cents)
      ActiveSupport::NumberHelper.number_to_currency(cents.to_i / 100.0)
    end

  end
end
