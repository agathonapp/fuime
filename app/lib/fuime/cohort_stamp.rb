# frozen_string_literal: true

# Fuime: resolve an event code into a cohort, for any flow that collects one.
#
# `Event::ApplicationsController` has done this inline since cohorts shipped
# (`apply_waitlist_cohort_stamp` / `assign_cohort_from_code`). The family setup
# wizard needs the same two answers and must not reach into that controller, so
# the rules live here and the old controller keeps its own copy untouched —
# the point of the wizard is that it cannot break the flow it runs beside.
#
# The one rule both callers must keep: a cohort is RESOLVED FROM A CODE
# SOMEBODY TYPED, never assigned by id. A cohort auto-approves, activates and
# vets a venture, so a permitted `fuime_cohort_id` would let an applicant admit
# themselves to somebody else's event. `Fuime::Cohort.for_code` returns nil for
# unknown, archived and expired alike, which is the whole gate.
module Fuime
  module CohortStamp
    module_function

    # The cohort a waitlist admit stamped on this user, if it is still admitting.
    #
    # Session first — that stamp was written when they clicked their own invite
    # link (`WaitlistInvitesController#show`) and is scoped to their user id, so
    # a signed-in stranger who opens somebody else's link cannot inherit it.
    # The Redis roster is the fallback for an invitee who signed in with an
    # ordinary login code instead of following the link.
    def from_waitlist(session:, user:)
      code = nil

      stored = session[:waitlist_cohort]
      if stored.is_a?(Hash) && stored["uid"].to_i == user.id
        code = stored["code"].to_s.presence
        session.delete(:waitlist_cohort)
      end

      code ||= ::Fuime::WaitlistRoster.invite_stamp(user.email)&.cohort_code
      return nil if code.blank?

      cohort = ::Fuime::Cohort.for_code(code)
      cohort if cohort&.admitting?
    end

    # A typed code. Returns [cohort_or_nil, outcome] where outcome is
    # :blank (clear whatever was set — somebody pasted the wrong code and needs
    # a way back), :unknown (leave the record alone and tell them), or :ok.
    #
    # An unrecognised code is deliberately not an error that blocks saving: the
    # applicant can always submit without one, and refusing to save a whole
    # application over a typo would be a wall in front of the thing they came
    # to do.
    def from_code(typed)
      code = typed.to_s.strip
      return [nil, :blank] if code.blank?

      cohort = ::Fuime::Cohort.for_code(code)
      return [nil, :unknown] if cohort.nil?

      [cohort, :ok]
    end
  end
end
