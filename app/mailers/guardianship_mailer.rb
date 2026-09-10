# frozen_string_literal: true

class GuardianshipMailer < ApplicationMailer
  def invite(guardianship:)
    @guardianship = guardianship
    @minor = guardianship.minor
    @guardian = guardianship.guardian
    @accept_url = guardianship_url(guardianship.invite_token)
    @minor_name = @minor.name.presence || "A young founder"
    @support_email = OPERATIONS_EMAIL

    # Keep From on no-reply@<domain> — Resend is documented against that
    # mailbox (docs/fuime/LAUNCH_SPEC.md §3.4). Reply-To is a real inbox so
    # "reply to this email" in the body is not a dead letter, and so filters
    # do not treat a no-reply From with no Reply-To as a spoofed blast.
    mail(
      to: @guardian.email,
      reply_to: OPERATIONS_EMAIL,
      subject: "#{@minor_name} invited you to be their guardian on Fuime"
    ) do |format|
      format.html
      format.text
    end
  end

  def accepted(guardianship:)
    @guardianship = guardianship
    @minor = guardianship.minor
    @guardian = guardianship.guardian
    @guardian_name = @guardian.name.presence || "Your guardian"
    @support_email = OPERATIONS_EMAIL

    mail(
      to: @minor.email,
      reply_to: OPERATIONS_EMAIL,
      subject: "#{@guardian_name} accepted your Fuime guardian invitation"
    ) do |format|
      format.html
      format.text
    end
  end

end
