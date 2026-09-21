# frozen_string_literal: true

module Fuime
  # Fuime: one attempt to reach one human, and what the far end said about it.
  #
  # See the migration header. This exists because three separate alerting paths
  # in this codebase have failed by reporting success while reaching nobody, and
  # the only defence against a fourth is a record that can be read before the
  # outage rather than after it.
  #
  # `delivered` here means the relay accepted the message, not that a person
  # heard it — no push service will tell you whether the phone was face-down in
  # another room. The honest end-to-end check is the acknowledgement on the
  # incident itself, which is why one-tap ack exists.
  class IncidentNotification < ApplicationRecord
    self.table_name = "fuime_incident_notifications"

    belongs_to :incident, class_name: "Fuime::Incident", inverse_of: :notifications
    belongs_to :responder, class_name: "Fuime::Oncall::Responder", optional: true,
                           inverse_of: :incident_notifications

    CHANNELS = %w[push sms voice email].freeze

    enum :status, { sent: 0, delivered: 1, failed: 2 }, prefix: true

    validates :channel, inclusion: { in: CHANNELS }
    validates :attempted_at, presence: true

    scope :recent, -> { order(attempted_at: :desc) }
    scope :failures, -> { where(status: :failed) }

    def succeeded? = status_delivered?

  end
end
