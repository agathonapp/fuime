# frozen_string_literal: true

# == Schema Information
#
# Table name: fuime_oncall_responders
#
#  id                         :bigint           not null, primary key
#  active                     :boolean          default(TRUE), not null
#  email                      :string
#  escalation_position        :integer          default(1), not null
#  name                       :string           not null
#  phone_number               :string
#  push_credential_ciphertext :text
#  push_kind                  :string
#  push_url                   :string
#  receives_digest            :boolean          default(TRUE), not null
#  receives_pages             :boolean          default(TRUE), not null
#  created_at                 :datetime         not null
#  updated_at                 :datetime         not null
#  user_id                    :bigint
#
# Indexes
#
#  idx_on_active_escalation_position_a5877b0ccb  (active,escalation_position)
#  index_fuime_oncall_responders_on_user_id      (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (user_id => users.id)
#
module Fuime
  module Oncall
    # Fuime: a human who can be reached, and the order they are reached in.
    #
    # See the migration header for why this is a table. The short version: alert
    # routing used to live in an environment variable that had to be set
    # identically on two Render services, was set on neither, and could not be
    # inspected from inside the app.
    #
    # ── The channels, and which of them is actually a page ──────────────────
    #
    # Only one of these reliably wakes somebody, and it is worth being blunt
    # about which:
    #
    #   email  — not a page. It is the record and the digest. Treat its arrival
    #            time as "sometime tomorrow morning".
    #   push   — a page IF the relay supports a priority that overrides Do Not
    #            Disturb (ntfy priority 5, Pushover emergency). Without that it
    #            is a notification, which a sleeping phone discards silently.
    #   sms    — usually audible, but a text tone is a text tone.
    #   voice  — the only channel that is designed to be hard to ignore, which is
    #            why sev-1 uses it and nothing else does.
    #
    # A responder with no push, no phone and only an email is not on call. The
    # admin page says so in those words rather than letting the roster look
    # populated while nothing on it can reach anyone.
    class Responder < ApplicationRecord
      self.table_name = "fuime_oncall_responders"

      belongs_to :user, optional: true
      has_many :incident_notifications, class_name: "Fuime::IncidentNotification", dependent: :nullify,
                                        inverse_of: :responder

      # A credential, so it is encrypted at rest like every other one in this app
      # (Fuime::ApiKey#token, Fuime::WebhookEndpoint#secret).
      has_encrypted :push_credential

      # The payload shape, not the transport — all four are one HTTPS POST. They
      # differ in how they spell "make a noise", and that is the field that
      # decides whether a 3am page works.
      PUSH_KINDS = %w[ntfy pushover slack generic].freeze

      validates :name, presence: true
      validates :push_kind, inclusion: { in: PUSH_KINDS }, allow_blank: true
      validates :escalation_position, numericality: { greater_than_or_equal_to: 1 }
      validates :email, format: { with: URI::MailTo::EMAIL_REGEXP }, allow_blank: true
      validate :reachable_somehow

      scope :active, -> { where(active: true) }
      scope :by_escalation, -> { order(:escalation_position, :id) }
      scope :paging, -> { active.where(receives_pages: true).by_escalation }
      scope :digesting, -> { active.where(receives_digest: true).by_escalation }

      normalizes :email, with: ->(e) { e.to_s.strip.downcase.presence }
      normalizes :phone_number, with: ->(p) { p.to_s.strip.presence }

      # Whether this relay is authenticated, which decides how much a page is
      # allowed to say (see Fuime::Incident#page_text).
      #
      # A bare ntfy.sh topic is the case this exists for: it is a URL with no
      # credential, and anybody who guesses the topic name receives every alert
      # Fuime sends. Pushover and Slack webhooks both carry a secret in the
      # request, so a page over those can name the thing that broke.
      def push_private?
        return false if push_url.blank?

        case push_kind
        when "pushover", "slack" then true
        when "ntfy"              then push_credential.present?
        else                          push_credential.present?
        end
      end

      def push_configured? = push_url.present? && push_kind.present?
      def sms_configured?  = phone_number.present?
      def email_configured? = email.present?

      # Whether this row can wake somebody who is asleep, as opposed to merely
      # leaving them a message. The roster page renders this, because a roster
      # of unreachable people is the failure this whole subsystem exists to stop.
      def pageable? = push_configured? || sms_configured?

      # Channels this responder gets for a given severity, most urgent first.
      #
      # Severity gates the channel rather than the recipient: escalating by
      # adding MORE PEOPLE to a sev-3 is how a team learns to mute the tool.
      # A sev-3 is a line in tomorrow's digest; a sev-1 rings the phone.
      def channels_for(severity)
        case severity.to_s
        when "sev1" then [(:push if push_configured?), (:sms if sms_configured?), (:voice if sms_configured?), (:email if email_configured?)].compact
        when "sev2" then [(:push if push_configured?), (:sms if sms_configured?), (:email if email_configured?)].compact
        else             [(:email if email_configured?)].compact
        end
      end

      # For display. The roster is a page an admin opens casually and may screen
      # share; a full mobile number does not need to be on it to be useful.
      def redacted_phone
        return nil if phone_number.blank?

        digits = phone_number.gsub(/\D/, "")
        return "••••" if digits.length < 4

        "••••••#{digits.last(4)}"
      end

      def redacted_push
        return nil if push_url.blank?

        uri = begin
          URI.parse(push_url)
        rescue URI::InvalidURIError
          return "#{push_kind} (unparseable URL)"
        end
        "#{push_kind} · #{uri.host}"
      end

      def to_s = name

      private

      # A responder row that reaches nobody is worse than an absent one: it makes
      # the roster look staffed. This is the validation that stops somebody
      # adding a name and a title and believing they are now covered.
      def reachable_somehow
        return if email.present? || phone_number.present? || push_url.present?

        errors.add(:base, "needs at least one of an email, a phone number, or a push URL — a responder nobody can reach is not on call")
      end

    end
  end
end
