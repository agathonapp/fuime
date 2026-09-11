# frozen_string_literal: true

class GuardianshipMailer < ApplicationMailer
  def invite(guardianship:)
    @guardianship = guardianship
    @minor = guardianship.minor
    @guardian = guardianship.guardian
    @accept_url = guardianship_url(guardianship.invite_token)
    @minor_name = @minor.name.presence || "A young founder"
    @venture_name = venture_name_for(@minor)
    # The body branches on this: under merchant-of-record accepting unblocks
    # PAYOUTS (Event#payout_setup_blockers); under Connect it unblocks
    # ACTIVATION (Event::Application#activation_blockers). Same email, two true
    # versions — never one sentence that is false in one of the worlds.
    @merchant_of_record = ::Fuime::Features.merchant_of_record?
    @support_email = OPERATIONS_EMAIL

    # Keep From on no-reply@<domain> — Resend is documented against that
    # mailbox (docs/fuime/LAUNCH_SPEC.md §3.4). Reply-To is a real inbox so
    # "reply to this email" in the body is not a dead letter, and so filters
    # do not treat a no-reply From with no Reply-To as a spoofed blast.
    #
    # Subject says why NOW (ONBOARDING_PLAN §4.2): the earlier "invited you to
    # be their guardian" read as a social invitation and the one line that
    # moves a parent — they cannot be paid until you sign — was only in the
    # day-3 / day-6 reminders. It still avoids the urgent "sign their account"
    # phrasing the spec guards against.
    mail(
      to: @guardian.email,
      reply_to: OPERATIONS_EMAIL,
      subject: "#{@minor_name} started a business — they need a parent to sign off"
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
    @venture_name = venture_name_for(@minor)
    @merchant_of_record = ::Fuime::Features.merchant_of_record?
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
    # The body branches on this for the same reason #invite does: under
    # merchant-of-record acceptance clears the guardian half of
    # Event#payout_setup_blockers, not activation (that is Fuime's vetting).
    @merchant_of_record = ::Fuime::Features.merchant_of_record?
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

  # The venture the parent is being asked to sign for, or nil when the teen has
  # not named one yet (the templates then say "a business").
  #
  # Most recent Event first — it exists once the application is activated —
  # then the most recent live application, because the invite usually fires
  # from Event::Application#mark_submitted, before any Event exists. No new
  # column: this is read from what the minor already has.
  #
  # GuardianshipsController#venture_name_for applies the same rule for the
  # accept page's heading; keep the two in step.
  def venture_name_for(minor)
    minor.events.order(created_at: :desc).first&.name.presence ||
      minor.applications.not_archived.order(created_at: :desc).first&.name.presence
  end

end
