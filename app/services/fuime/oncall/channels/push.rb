# frozen_string_literal: true

module Fuime
  module Oncall
    module Channels
      # Fuime: the alarm ping — one HTTPS POST to whatever relay the responder
      # carries on their phone.
      #
      # ── Priority is the entire feature ────────────────────────────────────
      #
      # All four relays below are a POST with a JSON or text body, and the only
      # interesting difference between them is how they spell "make a noise even
      # though this phone is on silent". A push notification at default priority
      # is swallowed by Do Not Disturb, which means a page that is delivered,
      # acknowledged by the relay, recorded as a success here — and never heard.
      # That is the precise failure this subsystem exists to eliminate, so the
      # severity is mapped onto each relay's loudest setting rather than left at
      # its default.
      #
      #   ntfy     — Priority: 5 (max). On iOS this needs the app's notification
      #              settings to allow Critical Alerts; on Android max priority
      #              is enough on its own.
      #   pushover — priority 2 (emergency): re-alerts every RETRY_SECONDS until
      #              acknowledged IN PUSHOVER, for up to EXPIRE_SECONDS. This is
      #              the closest of the four to a real pager.
      #   slack    — no priority concept at all. Included because it is where a
      #              team already is, but it is a notification, not a page, and
      #              must not be somebody's only channel.
      #   generic  — plain JSON for anything else (a personal relay, a Shortcut).
      #
      # ── The body is deliberately thin ─────────────────────────────────────
      #
      # A relay is a third party, and ntfy's public topics are readable by anyone
      # who guesses the topic name. Fuime's incidents contain venture names and
      # amounts belonging to minors, so the full detail NEVER goes over this
      # channel. `Incident#page_text` decides what is safe based on whether the
      # relay is authenticated; everything else lives behind the admin login.
      class Push
        TIMEOUT_SECONDS = 10
        PUSHOVER_RETRY_SECONDS = 60
        PUSHOVER_EXPIRE_SECONDS = 1800

        Result = Struct.new(:ok, :code, :error, keyword_init: true)

        def initialize(responder:, incident:)
          @responder = responder
          @incident = incident
        end

        def deliver!
          uri = URI.parse(@responder.push_url)
          request = build_request(uri)

          http = Net::HTTP.new(uri.host, uri.port)
          http.use_ssl = uri.scheme == "https"
          http.open_timeout = TIMEOUT_SECONDS
          http.read_timeout = TIMEOUT_SECONDS

          response = http.request(request)
          code = response.code.to_s

          if code.start_with?("2")
            Result.new(ok: true, code:)
          else
            Result.new(ok: false, code:, error: response.body.to_s.truncate(200))
          end
        rescue => e
          Result.new(ok: false, error: "#{e.class}: #{e.message}".truncate(300))
        end

        private

        def private? = @responder.push_private?

        def title = @incident.page_title(private: private?)
        def text  = @incident.page_text(private: private?)

        def build_request(uri)
          case @responder.push_kind
          when "ntfy"     then ntfy(uri)
          when "pushover" then pushover(uri)
          when "slack"    then slack(uri)
          else                 generic(uri)
          end
        end

        def ntfy(uri)
          request = Net::HTTP::Post.new(uri.request_uri)
          request["Title"] = title
          # 5 is ntfy's max. Anything less is a notification, not a page.
          request["Priority"] = @incident.sev3? ? "3" : "5"
          request["Tags"] = @incident.sev1? ? "rotating_light" : "warning"
          # Bearer is optional on ntfy.sh but required for a private topic, and a
          # private topic is the only way this channel is safe for real detail.
          credential = @responder.push_credential
          request["Authorization"] = "Bearer #{credential}" if credential.present?
          request.body = text
          request
        end

        def pushover(uri)
          token, user = @responder.push_credential.to_s.split(":", 2)
          params = {
            token:, user:, title:, message: text,
            priority: if @incident.sev1?
                        2
                      else
                        (@incident.sev3? ? 0 : 1)
                      end,
            sound: @incident.sev1? ? "persistent" : "pushover"
          }
          # Emergency priority requires a retry cadence and an expiry, or
          # Pushover rejects the message outright.
          if @incident.sev1?
            params[:retry] = PUSHOVER_RETRY_SECONDS
            params[:expire] = PUSHOVER_EXPIRE_SECONDS
          end

          request = Net::HTTP::Post.new(uri.request_uri)
          request.set_form_data(params.compact)
          request
        end

        def slack(uri)
          request = Net::HTTP::Post.new(uri.request_uri)
          request["Content-Type"] = "application/json"
          request.body = { text: "*#{title}*\n#{text}" }.to_json
          request
        end

        def generic(uri)
          request = Net::HTTP::Post.new(uri.request_uri)
          request["Content-Type"] = "application/json"
          request["User-Agent"] = "Fuime-Oncall/1"
          request.body = {
            severity: @incident.severity, key: @incident.key,
            title:, message: text, opened_at: @incident.opened_at.iso8601
          }.to_json
          request
        end

      end
    end
  end
end
