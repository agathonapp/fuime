# frozen_string_literal: true

# == Schema Information
#
# Table name: fuime_webhook_deliveries
#
#  id                        :bigint           not null, primary key
#  attempts                  :integer          default(0), not null
#  delivered_at              :datetime
#  last_error                :text
#  next_attempt_at           :datetime
#  payload                   :jsonb            not null
#  response_code             :integer
#  status                    :string           default("pending"), not null
#  created_at                :datetime         not null
#  updated_at                :datetime         not null
#  event_id                  :string           not null
#  event_type                :string           not null
#  fuime_webhook_endpoint_id :bigint           not null
#
# Indexes
#
#  index_fuime_deliveries_on_endpoint          (fuime_webhook_endpoint_id)
#  index_fuime_deliveries_on_status_and_due    (status,next_attempt_at)
#  index_fuime_deliveries_unique_per_endpoint  (fuime_webhook_endpoint_id,event_id) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (fuime_webhook_endpoint_id => fuime_webhook_endpoints.id)
#
# Check Constraints
#
#  fuime_webhook_deliveries_status_known  (status::text = ANY (ARRAY['pending'::character varying, 'delivered'::character varying, 'failed'::character varying]::text[]))
#
module Fuime
  # Fuime: one event's fate at one endpoint.
  #
  # Separate from the event itself (see the migration) because one sale
  # delivered to three endpoints has three independent outcomes, and a failing
  # endpoint must not rewrite history for a sale that certainly happened.
  class WebhookDelivery < ApplicationRecord
    self.table_name = "fuime_webhook_deliveries"

    belongs_to :endpoint, class_name: "Fuime::WebhookEndpoint",
                          foreign_key: :fuime_webhook_endpoint_id, inverse_of: :deliveries

    STATUSES = %w[pending delivered failed].freeze

    # ── The retry ladder ─────────────────────────────────────────────────────
    #
    # Five attempts over roughly 24 hours, then failed. Paddle retries 60 times
    # across 3 days; Stripe, 3 days as well. Both are right for a platform whose
    # customers run their own infrastructure at scale.
    #
    # Fuime's receivers are a teenager's Vercel project or a Zapier hook. An
    # endpoint that is still down after a day is not coming back on its own, and
    # 60 attempts against a dead host mostly produces noise and a queue nobody
    # drains. The trade is deliberate and is the kind of thing to revisit with
    # real delivery data rather than by argument.
    BACKOFF = [1.minute, 5.minutes, 30.minutes, 2.hours, 6.hours].freeze
    MAX_ATTEMPTS = BACKOFF.length

    validates :event_id, presence: true
    validates :event_type, presence: true
    validates :status, inclusion: { in: STATUSES }

    scope :due, -> { where(status: "pending").where(next_attempt_at: ..Time.current) }
    scope :undelivered, -> { where(status: "pending") }

    def delivered? = status == "delivered"
    def failed? = status == "failed"

    def record_success!(response_code:)
      update!(status: "delivered", response_code:, delivered_at: Time.current,
              attempts: attempts + 1, next_attempt_at: nil, last_error: nil)
      endpoint.update_column(:last_delivered_at, Time.current)
    end

    # Attempts are counted here rather than by the caller so a retry scheduled
    # from two places cannot disagree about how many are left.
    def record_failure!(error:, response_code: nil)
      next_attempt = attempts + 1
      if next_attempt >= MAX_ATTEMPTS
        update!(status: "failed", attempts: next_attempt, response_code:,
                last_error: error.to_s.truncate(1000), next_attempt_at: nil)
      else
        update!(attempts: next_attempt, response_code:,
                last_error: error.to_s.truncate(1000),
                next_attempt_at: Time.current + BACKOFF[next_attempt])
      end
    end

  end
end
