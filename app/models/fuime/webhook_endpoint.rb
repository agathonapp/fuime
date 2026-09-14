# frozen_string_literal: true

# == Schema Information
#
# Table name: fuime_webhook_endpoints
#
#  id                :bigint           not null, primary key
#  description       :string
#  disabled_at       :datetime
#  enabled           :boolean          default(TRUE), not null
#  last_delivered_at :datetime
#  secret_ciphertext :text             not null
#  url               :string           not null
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#  event_id          :bigint           not null
#
# Indexes
#
#  index_fuime_webhook_endpoints_on_event_id  (event_id)
#
# Foreign Keys
#
#  fk_rails_...  (event_id => events.id)
#
module Fuime
  # Fuime: where a venture wants to be told about its own sales.
  #
  # See the migration for why this and WebhookDelivery are separate tables.
  class WebhookEndpoint < ApplicationRecord
    self.table_name = "fuime_webhook_endpoints"

    # A founder's own server is the destination, so the secret is theirs to
    # verify with. Encrypted at rest like Fuime::ApiKey's token; anyone who can
    # read it can forge sales into their system.
    #
    # Backed by `secret_ciphertext` — Lockbox's convention, and the one ApiKey
    # already follows. Naming the column `encrypted_secret` instead left the
    # model with no writer at all.
    has_encrypted :secret

    belongs_to :event
    has_many :deliveries, class_name: "Fuime::WebhookDelivery",
                          foreign_key: :fuime_webhook_endpoint_id,
                          dependent: :destroy, inverse_of: :endpoint

    # A cap, for the same reason Fuime::ApiKey has one: unbounded fan-out of a
    # minor's sale data to arbitrary hosts is a data-egress surface, not a
    # feature. Paddle's equivalent limit is 10 active destinations.
    MAX_ENDPOINTS_PER_EVENT = 5

    SECRET_PREFIX = "fuime_whsec_"
    SECRET_BYTES = 32

    validates :url, presence: true
    validate :url_must_be_https_and_external
    validate :must_not_exceed_endpoint_limit, on: :create

    scope :enabled, -> { where(enabled: true) }

    before_validation :assign_secret, on: :create

    def self.generate_secret = "#{SECRET_PREFIX}#{SecureRandom.urlsafe_base64(SECRET_BYTES)}"

    def disable!(reason: nil)
      update!(enabled: false, disabled_at: Time.current)
      Rails.logger.info("[Fuime] disabled webhook endpoint #{id}#{": #{reason}" if reason}")
    end

    private

    def assign_secret
      self.secret ||= self.class.generate_secret
    end

    # ── Why this validation is not cosmetic ──────────────────────────────────
    #
    # A webhook URL is a server-side fetch to an address a user supplies, which
    # is the textbook SSRF shape: `http://169.254.169.254/` reads cloud instance
    # metadata, `http://localhost:6379/` talks to Redis, and a private-range
    # address reaches whatever else is inside the network. Fuime would be making
    # those requests on the user's behalf, from inside its own perimeter.
    #
    # HTTPS is required separately: a sale payload names a venture and an amount,
    # and sending it in clear text over someone's coffee-shop wifi is a
    # disclosure Fuime chose to make.
    #
    # Note this is a validation, NOT the only control — DNS can be repointed at a
    # private address after the record is saved, so Fuime::WebhookDeliverer
    # re-checks the resolved address at delivery time. This check exists to give
    # a founder an error they can read; that one exists to be correct.
    def url_must_be_https_and_external
      return if url.blank?

      parsed = begin
        URI.parse(url)
      rescue URI::InvalidURIError
        nil
      end

      if parsed.blank? || parsed.host.blank?
        errors.add(:url, "needs to be a full address, like https://example.com/hooks")
        return
      end

      errors.add(:url, "has to start with https://") unless parsed.scheme == "https"

      host = parsed.host.downcase
      if host == "localhost" || host.end_with?(".localhost") || host.end_with?(".internal")
        errors.add(:url, "can't point at a private address")
      end

      return unless (ip = resolve_literal(host))

      errors.add(:url, "can't point at a private address") unless public_address?(ip)
    end

    # Only literal IPs are checked here. A hostname's DNS is checked at delivery
    # time, where it cannot be changed underneath the check.
    def resolve_literal(host)
      IPAddr.new(host)
    rescue IPAddr::InvalidAddressError
      nil
    end

    def public_address?(ip)
      !(ip.loopback? || ip.private? || ip.link_local?)
    end

    def must_not_exceed_endpoint_limit
      return if event.blank?

      if self.class.where(event_id:).count >= MAX_ENDPOINTS_PER_EVENT
        errors.add(:base, "You can have up to #{MAX_ENDPOINTS_PER_EVENT} webhook endpoints.")
      end
    end

  end
end
