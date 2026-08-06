# frozen_string_literal: true

# Fuime: a school adding its own money to its own Stripe balance.
#
# Manager-only on both verbs, and deliberately invisible to students — see
# EventPolicy#fund_school?. This is the treasury page, not a student-facing one, and
# the balance it shows on a shared account is every sibling venture's revenue too.
#
# ── Why #create can succeed and still show a warning ────────────────────────
#
# Whether a Stripe-liability connected account may create top-ups through the API is
# unverified (Fuime::SchoolFundingService says so at length). When Stripe refuses, the
# service raises with the Stripe Dashboard fallback named in the message, because that
# path genuinely still works — Fuime::ConnectFundingRecorder posts the ledger credit
# from the webhook whether or not Fuime started the top-up. So a refusal here is a
# redirect with an actionable alert, not an error page.
module Fuime
  class SchoolFundingsController < ApplicationController
    before_action :set_event

    def index
      authorize @event, :fund_school?

      @fundings = @event.school_fundings.recent_first.limit(50)
      @balance_cents = @event.balance_v2_cents
      @in_flight_cents = @event.school_fundings.in_flight.sum(:amount_cents)
      @total_funded_cents = SchoolFunding.total_succeeded_cents(event: @event)
    end

    def create
      authorize @event, :fund_school?

      funding = service.fund!(
        amount_cents: amount_cents_param,
        requested_by: current_user
      )

      redirect_to fuime_school_fundings_path(event_slug: @event.slug),
                  notice: "Started a #{humanized_amount(funding.amount_cents)} top-up. " \
                          "It usually takes a few business days to clear, and the balance " \
                          "updates when it does."
    rescue Fuime::SchoolFundingService::Error => e
      # Service messages are already written for a business office to act on, and the
      # refusal message names the Dashboard fallback.
      redirect_to fuime_school_fundings_path(event_slug: @event.slug), alert: e.message
    end

    private

    def service
      @service ||= Fuime::SchoolFundingService.new(event: @event)
    end

    def set_event
      @event = Event.friendly.find(params[:event_slug])
    end

    # Dollars in the form, cents in the domain. Parsed permissively because a business
    # office will paste "1,500.00" and a form that rejects that is a form that gets
    # worked around.
    def amount_cents_param
      raw = params[:amount].to_s.gsub(/[$,\s]/, "")
      (raw.to_d * 100).round
    rescue ArgumentError
      0
    end

    def humanized_amount(cents)
      ActionController::Base.helpers.number_to_currency(cents / 100.0)
    end

  end
end
