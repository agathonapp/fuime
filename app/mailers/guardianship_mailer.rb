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

  # TEEN_GROWTH G5: same accept URL as #invite — not a second token. The
  # original email still works; this is a nudge before the 7-day link dies.
  def invite_reminder(guardianship:, stage:)
    @guardianship = guardianship
    @minor = guardianship.minor
    @guardian = guardianship.guardian
    @accept_url = guardianship_url(guardianship.invite_token)
    @minor_name = @minor.name.presence || "A young founder"
    @support_email = OPERATIONS_EMAIL
    @stage = stage.to_sym
    @expires_at = guardianship.invite_sent_at + Guardianship::INVITE_VALID_FOR if guardianship.invite_sent_at

    subject = if @stage == :day6
                "Last reminder: #{@minor_name}'s Fuime invite expires #{expiry_phrase}"
              else
                "Reminder: #{@minor_name} is still waiting for you on Fuime"
              end

    mail(
      to: @guardian.email,
      reply_to: OPERATIONS_EMAIL,
      subject:
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

  private

  def expiry_phrase
    return "soon" if @expires_at.blank?

    "on #{I18n.l(@expires_at.to_date, format: :long)}"
  end

end
