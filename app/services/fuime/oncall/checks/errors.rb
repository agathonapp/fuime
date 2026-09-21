# frozen_string_literal: true

module Fuime
  module Oncall
    module Checks
      # Fuime: is the app throwing exceptions at people?
      #
      # Every other check here watches a CONDITION — a queue depth, a deadline,
      # a third party. This one watches the thing a founder or a buyer actually
      # experiences when something breaks: a page that does not work.
      #
      # ── The thresholds, and why they are not lower ─────────────────────────
      #
      # Fuime's traffic is small, so any sustained rate of unhandled exceptions
      # is abnormal — but a single burst is not. A deploy, a bot finding one bad
      # URL, one malformed webhook: each produces a handful of errors and then
      # stops. WINDOW is long enough that a burst does not fill it and a real
      # breakage does.
      #
      # Raising these thresholds is the wrong response to noise. If this fires on
      # something that is not a problem, the fix is to add that error class to
      # `ErrorCounter::IGNORED` where the reason can be written down, not to
      # raise the bar until genuine breakage fits underneath it.
      class Errors < Check
        WINDOW = 10.minutes
        WARN_THRESHOLD = 10
        PAGE_THRESHOLD = 50

        def call
          count, by_class = ::Fuime::Oncall::ErrorCounter.recent(window: WINDOW)

          # nil means the counter could not be read, which is NOT all-clear —
          # see Check's header on why returning [] is a positive statement.
          # Raising lets Sweep record it as a check that cannot run, so the
          # error rate reads as unmonitored rather than as fine.
          raise "error counts are unreadable (Redis)" if count.nil?

          return [] if count < WARN_THRESHOLD

          [finding(
            key: "errors.rate",
            title: "#{count} unhandled #{'error'.pluralize(count)} in the last #{WINDOW.inspect}",
            severity: count >= PAGE_THRESHOLD ? :sev1 : :sev2,
            error_count: count,
            window_minutes: WINDOW.in_minutes.to_i,
            # The classes are the whole diagnostic value here. There are no
            # backtraces — that is AppSignal's job, and it is still unconfigured.
            top_classes: by_class.sort_by { |_k, v| -v }.first(5).to_h,
            hint: "No backtraces here by design. Set APPSIGNAL_PUSH_API_KEY for those."
          )]
        end

      end
    end
  end
end
