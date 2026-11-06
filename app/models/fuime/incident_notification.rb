# frozen_string_literal: true

# == Schema Information
#
# Table name: fuime_incident_notifications
#
#  id              :bigint           not null, primary key
#  attempted_at    :datetime         not null
#  channel         :string           not null
#  error           :text
#  response_code   :string
#  status          :integer          default(0), not null
#  target_redacted :string
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  incident_id     :bigint           not null
#  responder_id    :bigint
#
# Indexes
#
#  idx_on_incident_id_attempted_at_acf1592728          (incident_id,attempted_at)
#  index_fuime_incident_notifications_on_responder_id  (responder_id)
#
# Foreign Keys
#
#  fk_rails_...  (incident_id => fuime_incidents.id)
#  fk_rails_...  (responder_id => fuime_oncall_responders.id)
#
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
