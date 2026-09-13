# frozen_string_literal: true

module Fuime
  # Fuime: the one email a parent-first teen gets.
  #
  # Their parent set the family up before they had heard of Fuime, so this is
  # the first thing they ever see from us. It has to do three jobs in one
  # message: say who did this and that it is legitimate, say what is already
  # done (their parent has signed — the part that usually holds a teen up), and
  # get them into their own account without a second round trip through a login
  # code.
  #
  # ── The link ────────────────────────────────────────────────────────────
  #
  # The join URL carries a signed id (Fuime::FamilyInviteService) and is minted
  # HERE, inside the mailer, on purpose. It signs its holder in as the minor,
  # so it must exist in exactly one place — this message — and never in a view,
  # a flash, the session, a log line, or anywhere the parent could read it. A
  # parent holding their teen's sign-in link could act as them.
  #
  # ── L7 ──────────────────────────────────────────────────────────────────
  #
  # The recipient is a minor, so: transactional only, no reminders (the parent
  # resends by hand from their guardian page), and nothing between midnight and
  # 6 a.m. — callers schedule it with
  # `deliver_later(wait_until: Fuime::MinorMailWindow.earliest_send_time)`.
  class FamilyMailer < ApplicationMailer
    def teen_join(guardianship:)
      @guardianship = guardianship
      @minor = guardianship.minor
      @guardian = guardianship.guardian
      @guardian_name = @guardian.name.presence || "Your parent or guardian"
      @guardian_first_name = @guardian.first_name.presence || @guardian_name
      @greeting_name = @minor.preferred_name.presence || @minor.first_name.presence

      # A teen who already had an account is not being invited to sign up; they
      # are being told an adult joined theirs. Same link either way — it still
      # signs them in — but the message must not tell somebody with a running
      # venture to "finish setting up".
      @existing_account = !@minor.onboarding?

      @join_url = family_invite_url(::Fuime::FamilyInviteService.generate_token(user: @minor))

      mail(
        to: @minor.email,
        reply_to: OPERATIONS_EMAIL,
        subject: "#{@guardian_name} set up Fuime for you — finish in two minutes"
      ) do |format|
        format.html
        format.text
      end
    end

  end
end
