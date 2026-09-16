# frozen_string_literal: true

module Fuime
  # Fuime: the morning digest. See Fuime::OpsDigestMailer for what is in it and
  # why it sends on quiet days too.
  class OpsDigestJob < ApplicationJob
    queue_as :low

    def perform
      ::Fuime::OpsDigestMailer.daily.deliver_now
    end

  end
end
