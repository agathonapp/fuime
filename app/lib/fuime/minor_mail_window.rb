# frozen_string_literal: true

# Fuime: when it is acceptable to email a minor.
#
# L7 (CLAUDE.md; docs/fuime/LEGAL_RESEARCH.md): notifications to minors are
# transactional only and none between midnight and 6 a.m. This computes the
# delay that keeps a send inside that window, for use as
# `deliver_later(wait_until: Fuime::MinorMailWindow.earliest_send_time)`.
#
# ── Why a zone comes from the environment ────────────────────────────────────
#
# The app has no `config.time_zone`, so Rails runs in UTC and a naive "not
# between 0 and 6" would be quiet hours in London for a family in California.
# No profile carries a time zone yet, so the env var names one zone for the
# whole platform — the launch cohort's. When profiles carry a zone, pass it in;
# the signature already takes one.
#
# `Event::ApplicationReminderJob` was excluded when this was written, to keep a
# scheduling change out of an onboarding PR; the draft-reminder series was cut
# from four mails to two and moved inside this window afterwards, in the same
# pass that rewrote the lifecycle mail. `GuardianshipMailer#accepted` is
# addressed to the guardian, an adult, so L7 does not reach it.
module Fuime
  module MinorMailWindow
    QUIET_UNTIL_HOUR = 6
    DEFAULT_ZONE = "America/Los_Angeles"

    module_function

    def zone(name = ENV.fetch("FUIME_MAIL_TIME_ZONE", DEFAULT_ZONE))
      ActiveSupport::TimeZone[name] || ActiveSupport::TimeZone[DEFAULT_ZONE]
    end

    # `now` when the local hour is already 6 a.m. or later, otherwise 6 a.m.
    # local on the same local day.
    def earliest_send_time(now: Time.current, zone_name: nil)
      tz = zone_name ? zone(zone_name) : zone
      local = now.in_time_zone(tz)
      return now if local.hour >= QUIET_UNTIL_HOUR

      local.change(hour: QUIET_UNTIL_HOUR, min: 0, sec: 0)
    end

    def quiet?(now: Time.current, zone_name: nil)
      tz = zone_name ? zone(zone_name) : zone
      now.in_time_zone(tz).hour < QUIET_UNTIL_HOUR
    end
  end
end
