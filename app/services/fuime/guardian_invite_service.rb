# frozen_string_literal: true

# Fuime: create a guardianship invite for a minor, from anywhere.
#
# Extracted from the inline logic in GuardianshipsController#create so the
# application flow can send the invite automatically. Since #44 deferred the
# guardian ask to activation, the funnel is: teen applies now, parent accepts
# whenever — and the application form already collects the parent's email
# (cosigner_email), so making the teen re-type it on a separate page was pure
# friction. Submission now triggers the same invite the manual page sends.
#
# Deliberately BEST-EFFORT at the call site: a failed invite must never block
# an application submission (the teen can still invite manually from
# /guardian/new), so callers in after-hooks rescue and log rather than raise.
#
# The controller keeps its own inline copy for now — refactoring a proven,
# user-facing flow to delegate here is a follow-up, not a rider on this change.
module Fuime
  class GuardianInviteService
    class InvalidInvite < StandardError; end

    def initialize(minor:, guardian_email:)
      @minor = minor
      @guardian_email = guardian_email.to_s.strip.downcase
    end

    # Returns the Guardianship (new or already-existing), or raises
    # InvalidInvite with a human-readable reason.
    def run!
      raise InvalidInvite, "guardian email is blank" if @guardian_email.blank?
      raise InvalidInvite, "a minor cannot be their own guardian" if @guardian_email == @minor.email

      guardian = User.find_by(email: @guardian_email) ||
                 User.create!(email: @guardian_email)

      # Idempotent: an invite (or an active guardianship) for this pair already
      # exists — re-sending on every submission edit would spam the parent.
      existing = Guardianship.find_by(minor: @minor, guardian:)
      return existing if existing

      guardianship = Guardianship.create!(minor: @minor, guardian:)
      GuardianshipMailer.invite(guardianship:).deliver_later
      guardianship
    rescue ActiveRecord::RecordInvalid => e
      raise InvalidInvite, e.record.errors.full_messages.to_sentence
    end

  end
end
