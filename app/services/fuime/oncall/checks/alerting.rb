# frozen_string_literal: true

module Fuime
  module Oncall
    module Checks
      # Fuime: is the thing that tells you about problems itself working?
      #
      # ── Why this is the most important check in the directory ──────────────
      #
      # Three separate alerting paths in this codebase have failed by reporting
      # success while reaching nobody: AdminMailer addressed to a credential that
      # was never set, `deliver_mail` returning early on an empty recipient list,
      # and EARMUFFED_USER_IDS silently subtracting real users from every
      # recipient list. In each case the system's self-reported health was
      # perfect **because** it was doing nothing. A pager inherits that failure
      # mode by default, and inherits it worse, because it is trusted more.
      #
      # ── It cannot fully save itself, and that is fine ──────────────────────
      #
      # If email and push are both dead, the incident this check raises reaches
      # nobody either. That is unavoidable from inside and is what the external
      # heartbeat (Fuime::Oncall::SweepJob) is for. What this check DOES cover is
      # the far more common partial failure: the push relay is dead but email
      # works, or the roster is populated with people who have no pageable
      # channel. Those are silent today and catastrophic on the night they
      # matter.
      class Alerting < Check
        FAILURE_WINDOW = 24.hours

        def call
          findings = []

          responders = ::Fuime::Oncall::Responder.paging.to_a

          if responders.empty?
            findings << finding(
              key: "alerting.no_responders",
              title: "Nobody is on call — the roster is empty",
              # Deliberately sev-1 in its own right. An empty roster means every
              # future sev-1 goes nowhere, so this is the outage that hides all
              # the others.
              severity: :sev1,
              hint: "Add yourself at /admin/oncall. Until then, incidents are recorded but nobody is paged."
            )
          elsif responders.none?(&:pageable?)
            findings << finding(
              key: "alerting.nobody_pageable",
              title: "Everybody on call is email-only — nothing can wake anyone",
              severity: :sev2,
              responders: responders.map(&:name),
              hint: "Email is not a page. Add a push URL or a phone number to at least the first position."
            )
          end

          if smtp_missing.any?
            findings << finding(
              key: "alerting.smtp_unconfigured",
              title: "SMTP is missing #{smtp_missing.join(', ')} — no email can be sent",
              # Sev-1 because this breaks login, not only alerting: Fuime signs
              # people in with emailed codes, so an unset SMTP password locks
              # every founder and guardian out of the product.
              severity: :sev1,
              missing: smtp_missing,
              impact: "Email login codes fail, so nobody can sign in. The daily digest also stops."
            )
          end

          # A channel that failed every time it was tried is a channel you do not
          # have. Checked over a day rather than per-attempt so a single timeout
          # against a push relay does not page anybody.
          # `responder_id: nil` rows are the pager recording that there was nobody
          # to page at all. That is a real and important failure, but it is the
          # one `alerting.no_responders` above already names — counting it here
          # too would report a dead push channel when the actual problem is an
          # empty roster, and send somebody to debug the wrong thing.
          recent = ::Fuime::IncidentNotification
                   .where(attempted_at: FAILURE_WINDOW.ago..)
                   .where.not(responder_id: nil)
          by_channel = recent.group(:channel, :status).count
          ::Fuime::IncidentNotification::CHANNELS.each do |channel|
            attempts = by_channel.sum { |(c, _s), n| c == channel ? n : 0 }
            next if attempts.zero?

            failures = by_channel.fetch([channel, "failed"], 0)
            next unless failures == attempts

            findings << finding(
              key: "alerting.channel_dead.#{channel}",
              title: "Every #{channel} page in the last #{FAILURE_WINDOW.inspect} failed to send",
              severity: :sev2,
              channel:,
              attempts:,
              hint: "Pages are being recorded but not delivered over this channel."
            )
          end

          findings
        end

        private

        def smtp_missing
          @smtp_missing ||= begin
            return [] unless Rails.application.config.action_mailer.delivery_method == :smtp

            settings = Rails.application.config.action_mailer.smtp_settings || {}
            settings.slice(:address, :port, :user_name, :password)
                    .select { |_k, v| v.blank? }
                    .keys
                    .map(&:to_s)
          end
        end

      end
    end
  end
end
