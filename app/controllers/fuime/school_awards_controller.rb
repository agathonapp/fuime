# frozen_string_literal: true

# Fuime: the school granting money to a student's venture, and everyone seeing it.
#
# ── The authorization shape ─────────────────────────────────────────────────
#
#   #index   both — the student sees what they've been given and their running
#            total toward the school's 1099 threshold; the guide sees the same
#   #create  a school MANAGER only, because it spends the school's own balance
#   #void    a school MANAGER only
#
# No student-initiated verb anywhere, and that asymmetry with
# Fuime::PayoutsController is the point. A payout is a minor asking to move money out
# of an account they do not own, so it needs a request and a decision. An award is the
# account owner moving its own money in, so it needs neither — there is nobody for the
# school to ask.
module Fuime
  class SchoolAwardsController < ApplicationController
    before_action :set_event
    before_action :set_award, only: [:void]

    def index
      authorize @event, :school_awards?

      @school = service.school
      @awards = @event.school_awards.recent_first.limit(50)
      @can_grant = policy(@event).grant_school_award?
      @available_cents = @can_grant ? service.available_to_award_cents : nil

      # Who could receive an award, for the grant form. Members of this venture —
      # the award names who earned it, and SchoolAward validates that.
      @candidates = @can_grant ? @event.users.order(:full_name) : []

      # Per-student totals for the calendar year, so a school sees the 1099 threshold
      # coming rather than discovering it in January. Fuime is not the withholding
      # agent and does not file anything; this is a number, not a filing.
      @reportable = reportable_totals
    end

    def create
      authorize @event, :grant_school_award?

      service.grant!(
        amount_cents: amount_cents_param,
        awarded_to: User.find(params[:awarded_to_id]),
        awarded_by: current_user,
        reference: reference_param
      )

      redirect_to fuime_school_awards_path(event_slug: @event.slug),
                  notice: "Awarded #{humanized_amount(amount_cents_param)} to #{@event.name}."
    rescue Fuime::SchoolAwardService::Error => e
      # Service messages are already written for a school administrator to act on.
      redirect_to fuime_school_awards_path(event_slug: @event.slug), alert: e.message
    rescue ActiveRecord::RecordInvalid => e
      redirect_to fuime_school_awards_path(event_slug: @event.slug),
                  alert: e.record.errors.full_messages.to_sentence
    end

    def void
      authorize @event, :grant_school_award?

      service.void!(award: @award, voided_by: current_user, reason: params[:void_reason])

      redirect_to fuime_school_awards_path(event_slug: @event.slug),
                  notice: "That award has been reversed. #{humanized_amount(@award.amount_cents)} " \
                          "went back to the school."
    rescue Fuime::SchoolAwardService::Error => e
      redirect_to fuime_school_awards_path(event_slug: @event.slug), alert: e.message
    end

    private

    def set_event
      @event = Event.find_by!(slug: params[:event_slug])
    end

    # Scoped through the venture, so a manager of one school cannot void an award
    # belonging to another by guessing an id.
    def set_award
      @award = @event.school_awards.find(params[:id])
    end

    def service
      @service ||= Fuime::SchoolAwardService.new(venture: @event)
    end

    def reportable_totals
      school = service.school
      return {} if school.blank?

      @event.users.index_with do |user|
        SchoolAward.reportable_total_cents(awarded_to: user, school_event: school)
      end
    end

    # Accepts what a person types, matching Fuime::PayoutsController. Anything
    # unparseable becomes 0 and is refused by the model's positivity check, which
    # produces a sentence about the amount rather than a stack trace.
    def amount_cents_param
      @amount_cents_param ||= begin
        raw = params[:amount].to_s.gsub(/[^\d.]/, "")
        raw.blank? ? 0 : (BigDecimal(raw) * 100).round
      rescue ArgumentError
        0
      end
    end

    # The school's own identifier for what justified the award. Bounded and
    # control-stripped because it lands in a record a family can read.
    #
    # NOT a place for grades. The field exists so a school can reconcile against its
    # own gradebook without Fuime ever holding an education record — see
    # CreateSchoolAwards for the FERPA reasoning. The form says so, and the guard spec
    # in spec/models/school_award_spec.rb fails if a grade-shaped column appears.
    MAX_REFERENCE_LENGTH = 60

    def reference_param
      params[:reference].to_s.gsub(/[[:cntrl:]]/, "").strip
                        .truncate(MAX_REFERENCE_LENGTH).presence
    end

    def humanized_amount(cents)
      ActiveSupport::NumberHelper.number_to_currency(cents.to_i / 100.0)
    end

  end
end
