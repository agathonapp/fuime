# frozen_string_literal: true

class Event
  class ApplicationReminderJob < ApplicationJob
    queue_as :low
    def perform(application, tip_number)
      return unless application.draft? && !application.archived?

      # Fuime: a founder who abandoned one draft and started a business anyway
      # should not be chased about the abandoned one. `/setup` resumes the newest
      # draft and the wizard is a first-venture flow, so the second draft of
      # somebody who already has a venture is not a stalled signup.
      return if application.user.events.any?

      Event::ApplicationMailer.with(application:, tip_number:).incomplete.deliver_later
    end

  end

end
