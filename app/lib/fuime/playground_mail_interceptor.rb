# frozen_string_literal: true

module Fuime
  # Fuime: no mail addressed to a demo persona ever leaves the building.
  #
  # The playground runs on the production deploy with live Stripe keys, and the
  # family setup wizard sends real mail — a parent naming a teen enqueues a
  # join link. A demo driven in front of a room must not be able to put a
  # message in a stranger's inbox because somebody typed a plausible address on
  # stage.
  #
  # Two layers, deliberately. The wizard refuses a non-`@fuime.test` address
  # from a persona at the point of entry (a clear error, on the screen, while
  # somebody is watching); this is the backstop for every path that does not
  # ask — a queued job, a rake task, a mailer somebody adds later.
  #
  # An interceptor rather than a condition in each mailer: there is one place
  # to get it right, and a new mailer is covered without anybody remembering.
  # Only messages where EVERY recipient is a persona are dropped, so a mail
  # that happens to copy a real address is still delivered rather than silently
  # lost.
  class PlaygroundMailInterceptor
    def self.delivering_email(message)
      recipients = Array(message.to) + Array(message.cc) + Array(message.bcc)
      return if recipients.empty?
      return unless recipients.all? { |address| ::Fuime::Playground.persona?(address) }

      message.perform_deliveries = false
      Rails.logger.info("[Fuime] playground mail suppressed to #{recipients.join(", ")}: #{message.subject}")
    end

  end
end
