# frozen_string_literal: true

module Fuime
  # Fuime: day-3 / day-6 nudges for a still-pending guardian invite.
  #
  # TEEN_GROWTH G5. The invite used to be one email. Under MoR a teen can
  # sell without a parent and cannot get paid until guardianship is active,
  # so a forgotten inbox is a stranded payout. This job is the push; the
  # stale-pending admin queue is the human backstop after the token dies.
  #
  # Refuses accepted, revoked, and expired rows — see
  # Guardianship#send_invite_reminder!. Reuses the current invite token;
  # it does not call #resend_invite!, which would reset the 7-day clock
  # and break the link already sitting in the first email.
  class GuardianInviteReminderJob < ApplicationJob
    queue_as :low

    def perform
      Guardianship.send_due_invite_reminders!
    end

  end
end
