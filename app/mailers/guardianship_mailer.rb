# frozen_string_literal: true

class GuardianshipMailer < ApplicationMailer
  def invite(guardianship:)
    @guardianship = guardianship
    @minor = guardianship.minor
    @guardian = guardianship.guardian
    @accept_url = guardianship_url(guardianship.invite_token)

    mail(
      to: @guardian.email,
      subject: "#{@minor.name || 'Your child'} needs you to sign their Fuime account"
    )
  end

  def accepted(guardianship:)
    @guardianship = guardianship
    @minor = guardianship.minor
    @guardian = guardianship.guardian

    mail(
      to: @minor.email,
      subject: "#{@guardian.name || 'Your guardian'} accepted your Fuime invitation!"
    )
  end
end
