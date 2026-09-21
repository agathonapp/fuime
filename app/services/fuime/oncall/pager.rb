# frozen_string_literal: true

module Fuime
  module Oncall
    # Fuime: decide who to wake, over which channel, and write down what happened.
    #
    # ── Escalation ADDS people, it does not hand over ──────────────────────
    #
    # When an unacknowledged sev-1 climbs a rung, position 1 keeps being paged
    # and position 2 joins them. The alternative — moving the page to the next
    # person — assumes the first person is unavailable, when the far more common
    # reason for a missed page is that the page never arrived. Handing over
    # would then silently stop retrying the one channel that might work.
    #
    # ── Why every attempt is written down, including successes ─────────────
    #
    # See Fuime::IncidentNotification. This codebase has three separate examples
    # of alerting that reported health while reaching nobody. A row per attempt
    # makes "did last night's page actually leave the building?" a query rather
    # than an experiment, and makes Checks::Alerting able to notice a channel
    # that has failed every time for a day.
    class Pager
      def self.dispatch!(now: Time.current)
        new(now:).dispatch!
      end

      def self.page!(incident, now: Time.current)
        new(now:).page!(incident)
      end

      def initialize(now: Time.current)
        @now = now
      end

      def dispatch!
        paged = []

        ::Fuime::Incident.unacknowledged.by_urgency.find_each do |incident|
          next unless incident.page_due?(now: @now)

          paged << incident if page!(incident)
        end

        paged
      end

      def page!(incident)
        position = incident.target_escalation_position(now: @now)
        responders = ::Fuime::Oncall::Responder.paging.where(escalation_position: ..position).to_a

        if responders.empty?
          # Recorded rather than silently skipped: "there was nobody to page" is
          # the single most important fact about an incident that nobody
          # answered, and it is the fact that is hardest to reconstruct later.
          ::Fuime::IncidentNotification.create!(
            incident:, channel: "push", status: :failed, attempted_at: @now,
            error: "No responder is on call. Add one at /admin/oncall."
          )
          incident.update!(last_paged_at: @now, page_count: incident.page_count + 1,
                           escalation_position: position)
          Rails.logger.error("[Fuime::Oncall] incident #{incident.key} had nobody to page")
          return false
        end

        responders.each do |responder|
          responder.channels_for(incident.severity).each do |channel|
            deliver(incident:, responder:, channel:)
          end
        end

        incident.update!(last_paged_at: @now, page_count: incident.page_count + 1,
                         escalation_position: position)
        true
      end

      private

      def deliver(incident:, responder:, channel:)
        result =
          case channel
          when :push  then Channels::Push.new(responder:, incident:).deliver!
          when :sms   then Channels::Sms.new(responder:, incident:).deliver!
          when :voice then Channels::Voice.new(responder:, incident:).deliver!
          when :email then deliver_email(incident:, responder:)
          end

        ::Fuime::IncidentNotification.create!(
          incident:, responder:, channel: channel.to_s,
          target_redacted: redacted_target(responder, channel),
          status: result.ok ? :delivered : :failed,
          response_code: result.code, error: result.error,
          attempted_at: @now
        )
      rescue => e
        # A channel blowing up must never stop the remaining channels — the
        # whole point of having several is that they fail independently.
        Rails.error.report(e, handled: true, context: { incident: incident.key, channel: })
        ::Fuime::IncidentNotification.create!(
          incident:, responder:, channel: channel.to_s, status: :failed,
          error: "#{e.class}: #{e.message}".truncate(300), attempted_at: @now
        )
      end

      def deliver_email(incident:, responder:)
        ::Fuime::OncallMailer.with(incident:, responder:).page.deliver_later
        Channels::Push::Result.new(ok: true, code: "queued")
      rescue => e
        Channels::Push::Result.new(ok: false, error: "#{e.class}: #{e.message}".truncate(300))
      end

      def redacted_target(responder, channel)
        case channel
        when :push          then responder.redacted_push
        when :sms, :voice   then responder.redacted_phone
        when :email         then responder.email
        end
      end

    end
  end
end
