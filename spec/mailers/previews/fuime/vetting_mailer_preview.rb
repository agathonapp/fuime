# frozen_string_literal: true

# Fuime: /rails/mailers/fuime/vetting_mailer — the two vetting notices, rendered
# against whatever venture is handy in the development database. Both read
# Event#accepts_payments? at render time, so to see the "you can publish now"
# branch pick a venture that actually can.
module Fuime
  class VettingMailerPreview < ActionMailer::Preview
    def approved
      Fuime::VettingMailer.approved(event:)
    end

    def reinstated
      Fuime::VettingMailer.reinstated(event:)
    end

    private

    # An approved venture with a manager, so the message has a recipient and the
    # "back on sale" branch has a chance of being true. Falls back to any event
    # rather than raising, so the preview index still renders on a thin database.
    def event
      Event.operator_vetting_approved
           .joins(:organizer_positions)
           .order(id: :desc)
           .first || Event.last
    end

  end
end
