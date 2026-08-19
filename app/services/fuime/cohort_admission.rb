# frozen_string_literal: true

# Fuime: walk one application through the three gates a cohort has already
# answered.
#
#   submitted ──approve──▶ approved ──activate──▶ a venture ──vet──▶ may sell
#
# See CreateFuimeCohorts for why one person answering these in advance is a real
# decision rather than a bypass. This class is only the mechanism.
#
# ── What it deliberately does NOT do ────────────────────────────────────────
#
# It does not make the venture eligible to sell. Vetting is one of the inputs to
# Fuime::OperatorEligibility, not the whole of it: the services-only scope and the
# operator age floor still apply and are still capable of refusing. A cohort can
# say "I vouch for these people"; it cannot say "and the rules do not apply to
# them", and the fact that admission and eligibility are separate objects is what
# keeps that true.
#
# It also never touches the guardian requirement, which under merchant-of-record
# lives at the payout seam (Fuime::PayableAssessment). A cohort admits founders;
# it does not stand in for anybody's parent.
module Fuime
  class CohortAdmission
    # Every outcome is one of these, because the caller is a mailer-adjacent
    # callback on submission and an admin roster, and both need to distinguish
    # "not admitted" from "failed while being admitted".
    Result = Struct.new(:status, :event, :message, keyword_init: true) do
      def admitted? = status == :admitted
    end

    def initialize(application:)
      @application = application
      @cohort = application.fuime_cohort
    end

    # Best-effort by design, and this is the important decision in the class.
    #
    # This runs from the `after` block of `mark_submitted`. A founder who has just
    # pressed Submit must never see an exception because an automatic convenience
    # failed — their application IS submitted, and the three gates it did not pass
    # are exactly the ones a human was doing by hand a week ago. So every failure
    # degrades to "sits in the queue like any other application", which is a state
    # the product already fully supports.
    #
    # Reported rather than swallowed: a cohort silently failing to admit fifty
    # people is a bad Friday, and the roster board reads these.
    def call
      return Result.new(status: :not_in_cohort) if @cohort.nil?

      blocker = @cohort.admission_blocker
      return Result.new(status: :refused, message: blocker) if blocker

      admit!
    rescue => e
      Rails.error.report(e, handled: true, context: {
                           fuime_cohort_id: @cohort&.id,
                           event_application_id: @application.id
                         })
      Rails.logger.error(
        "[Fuime] Cohort admission failed for application #{@application.hashid}: #{e.class}: #{e.message}"
      )
      Result.new(status: :failed, message: e.message)
    end

    private

    def admit!
      # The cap is checked under a row lock, not just in #admission_blocker.
      #
      # Fifty founders submitting in the same few minutes is the ordinary case
      # here, not a pathological one, so an unlocked read-then-write would let a
      # cohort capped at 50 admit 60. The lock is on the cohort row, which is the
      # thing being counted against.
      @cohort.with_lock do
        return Result.new(status: :refused, message: @cohort.admission_blocker) unless @cohort.admitting?

        approve!
        event = activate!
        vet!(event)

        Result.new(status: :admitted, event: event)
      end
    end

    # `mark_submitted`'s own `after` block already advances an application with no
    # contract to `under_review`, so by the time this runs the state is usually
    # `under_review` and occasionally `submitted`. Both are legitimate starting
    # points; anything else means somebody or something else has already acted on
    # this application and automation should not overwrite them.
    def approve!
      @application.mark_under_review! if @application.may_mark_under_review?
      @application.mark_approved! if @application.may_mark_approved?
    end

    # Point of contact is the cohort's creator, which is the same person the
    # vetting decision is recorded against — so a founder with a question about
    # their venture reaches the human who actually vouched for them, rather than
    # whichever admin's name the code happened to run under.
    #
    # `activate_event!` enforces its own preconditions (the free-venture slot, and
    # the guardian requirement on the Connect path). Those are not weakened here:
    # if one refuses, the rescue in #call turns it into an application sitting in
    # the ordinary queue with a reported reason.
    def activate!
      @application.activate_event!(
        risk_level: @cohort.risk_level,
        point_of_contact: @cohort.created_by
      )

      # `reload` because `activate_event!` creates the Event from the other side
      # of the association, so the in-memory `application.event` is still the nil
      # it was read as before the call.
      event = @application.reload.event
      raise "activation produced no venture for #{@application.hashid}" if event.nil?

      # `update_column` for a denormalised pointer: this is a copy of something
      # already true on the application, and putting it through Event's full
      # validation stack would let an unrelated legacy validation on a freshly
      # created venture abort an admission that has otherwise succeeded.
      event.update_column(:fuime_cohort_id, @cohort.id)
      event
    end

    # The note is the cohort's, verbatim — a statement of what happened, not a
    # judgement about this venture. See Fuime::Cohort#vetting_note.
    def vet!(event)
      event.record_vetting_decision!(
        status: :approved,
        by: @cohort.created_by,
        notes: @cohort.vetting_note
      )
    end

  end
end
