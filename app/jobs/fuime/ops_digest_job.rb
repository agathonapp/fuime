# frozen_string_literal: true

module Fuime
  # Fuime: the morning digest. See Fuime::OpsDigestMailer for what is in it and
  # why it sends on quiet days too.
  class OpsDigestJob < ApplicationJob
    queue_as :low

    # Off unless FUIME_OPS_DIGEST is set (2026-11-21): the owner asked for the
    # on-call emails to stop. The queues it summarised are all on the admin
    # dashboard. Re-enable with FUIME_OPS_DIGEST=true on the worker service.
    def self.enabled?
      ActiveModel::Type::Boolean.new.cast(ENV["FUIME_OPS_DIGEST"].presence) == true
    end

    def perform
      return unless self.class.enabled?

      ::Fuime::OpsDigestMailer.daily.deliver_now
    end

  end
end
