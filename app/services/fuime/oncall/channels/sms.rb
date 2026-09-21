# frozen_string_literal: true

module Fuime
  module Oncall
    module Channels
      # Fuime: a text message, over the Twilio credentials this app already has.
      #
      # SMS sits between push and voice in how hard it is to ignore: reliably
      # delivered, usually audible, and completely silent on a phone in Do Not
      # Disturb. It is the right channel for a sev-2 — something is wrong and you
      # should look when you next pick up your phone — and the wrong one for a
      # sev-1, which is why sev-1 adds a voice call rather than sending a second
      # text.
      #
      # ── Same content rule as push ─────────────────────────────────────────
      #
      # A carrier is a third party and a text sits unlocked on a lock screen, so
      # the body is the non-identifying summary. Treated as a public relay for
      # that reason, never `private: true`.
      class Sms
        Result = Struct.new(:ok, :code, :error, keyword_init: true)

        def initialize(responder:, incident:)
          @responder = responder
          @incident = incident
        end

        def self.configured?
          Credentials.fetch(:TWILIO, :ACCOUNT_SID).present? &&
            Credentials.fetch(:TWILIO, :AUTH_TOKEN).present? &&
            Credentials.fetch(:TWILIO, :PHONE_NUMBER).present?
        end

        def deliver!
          unless self.class.configured?
            return Result.new(ok: false, error: "Twilio is not configured (TWILIO__ACCOUNT_SID / __AUTH_TOKEN / __PHONE_NUMBER)")
          end

          message = client.messages.create(
            from: Credentials.fetch(:TWILIO, :PHONE_NUMBER),
            to: @responder.phone_number,
            body: body
          )
          Result.new(ok: true, code: message.status)
        rescue => e
          Result.new(ok: false, error: "#{e.class}: #{e.message}".truncate(300))
        end

        private

        def body
          "#{@incident.page_title(private: false)}\n#{@incident.page_text(private: false)}"
        end

        def client
          Twilio::REST::Client.new(
            Credentials.fetch(:TWILIO, :ACCOUNT_SID),
            Credentials.fetch(:TWILIO, :AUTH_TOKEN)
          )
        end

      end
    end
  end
end
