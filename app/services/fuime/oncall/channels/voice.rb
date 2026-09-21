# frozen_string_literal: true

module Fuime
  module Oncall
    module Channels
      # Fuime: a phone call, for sev-1 only.
      #
      # ── Why a call and not a third notification ───────────────────────────
      #
      # A ringing phone is the only consumer channel designed to be difficult to
      # ignore, and it is the only one a person can whitelist through Do Not
      # Disturb per-contact (iOS Emergency Bypass, Android priority contacts)
      # WITHOUT opening the floodgates to everything else. Push and SMS can only
      # be allowed in as a class.
      #
      # That property is also why this is reserved for sev-1 and why sev-1 is
      # defined as narrowly as it is in Fuime::Incident: a channel that is used
      # for things that turn out not to matter stops being whitelisted, and then
      # nothing can wake anybody.
      #
      # ── The message is spoken twice, on purpose ───────────────────────────
      #
      # Somebody answering a call at 3am misses the first few words of it every
      # time. The repeat costs one second of Twilio time and is the difference
      # between "something about Fuime" and knowing what broke.
      class Voice
        Result = Struct.new(:ok, :code, :error, keyword_init: true)

        def initialize(responder:, incident:)
          @responder = responder
          @incident = incident
        end

        def self.configured? = Channels::Sms.configured?

        def deliver!
          return Result.new(ok: false, error: "Twilio is not configured") unless self.class.configured?

          call = client.calls.create(
            from: Credentials.fetch(:TWILIO, :PHONE_NUMBER),
            to: @responder.phone_number,
            twiml: twiml
          )
          Result.new(ok: true, code: call.status)
        rescue => e
          Result.new(ok: false, error: "#{e.class}: #{e.message}".truncate(300))
        end

        private

        # Spoken aloud, so it is written to be heard rather than read: no ids, no
        # punctuation that a speech engine mangles, and the severity first
        # because it is the part that decides whether you get out of bed.
        def twiml
          spoken = @incident.page_spoken
          <<~XML
            <Response>
              <Pause length="1"/>
              <Say voice="Polly.Joanna">#{ERB::Util.html_escape(spoken)}</Say>
              <Pause length="1"/>
              <Say voice="Polly.Joanna">Repeating. #{ERB::Util.html_escape(spoken)}</Say>
            </Response>
          XML
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
