# frozen_string_literal: true

# Fuime: stand a venture up the moment a founder submits.
#
# HCB's approve → activate pair is a fiscal-sponsorship gate: Hack Club takes
# custody of donated funds, so a human has to say yes twice before an Event
# exists. Fuime's real publish gate is operator vetting. An unvetted venture
# already cannot take payment (`Event#selling_blockers`). Parking the founder
# on "Waiting on Fuime" until an admin clicks those two HCB buttons is a
# leftover, not a control.
#
#   submitted ──approve──▶ approved ──activate──▶ a venture
#                                                  └── still unvetted; cannot publish
#
# ── What it deliberately does NOT do ────────────────────────────────────────
#
# It does not vet. CohortAdmission may, because a named organiser already
# vouched. A solo submitter has not been vouched for. Vetting stays a human
# decision (`PLATFORM_REVIEW.md`); this class only stops using approve/activate
# as a waiting room.
#
# It does not touch the guardian requirement. Under merchant-of-record that
# lives at payout (`Fuime::PayableAssessment`). Under Connect,
# `Event::Application#activation_blockers` still refuses a guardianless minor,
# and this class reports that rather than weakening it.
module Fuime
  class FounderAdmission
    Result = Struct.new(:status, :event, :message, keyword_init: true) do
      def admitted? = status == :admitted
    end

    def initialize(application:)
      @application = application
    end

    # Best-effort, same reason as CohortAdmission: Submit must never 500
    # because an automatic convenience failed. The application IS submitted.
    def call
      return Result.new(status: :already_has_venture, event: @application.event) if @application.event.present?

      admit!
    rescue => e
      Rails.error.report(e, handled: true, context: {
                           event_application_id: @application.id
                         })
      Rails.logger.error(
        "[Fuime] Founder admission failed for application #{@application.hashid}: #{e.class}: #{e.message}"
      )
      Result.new(status: :failed, message: e.message)
    end

    private

    def admit!
      blockers = @application.activation_blockers
      if blockers.any?
        return Result.new(status: :blocked, message: blockers.to_sentence)
      end

      approve!
      event = activate!

      Result.new(status: :admitted, event: event)
    end

    def approve!
      @application.mark_under_review! if @application.may_mark_under_review?
      @application.mark_approved! if @application.may_mark_approved?
    end

    # The applicant is the point of contact. There is no staff member who
    # vouched — that is the whole point of self-serve — and
    # `activate_event!` needs someone to send the manager invite from.
    # Sending it as the founder, to the founder, is a self-invite that
    # `#accept` already handles.
    def activate!
      @application.activate_event!(
        risk_level: :zero,
        point_of_contact: @application.user
      )

      event = @application.reload.event
      raise "activation produced no venture for #{@application.hashid}" if event.nil?

      event
    end
  end
end
