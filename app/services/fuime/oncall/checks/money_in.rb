# frozen_string_literal: true

module Fuime
  module Oncall
    module Checks
      # Fuime: has the money stopped, and is that a Tuesday or a bug?
      #
      # ── The problem this check has, stated honestly ────────────────────────
      #
      # Zero sales in the last six hours is the signature of a broken checkout
      # AND the signature of a quiet afternoon, and at Fuime's current volume it
      # is overwhelmingly the second. A check that cannot tell them apart and
      # pages anyway trains its reader to ignore it, and the reader is one
      # person.
      #
      # So this check **arms itself only once there is a baseline to be missing
      # from**. Below MIN_BASELINE sales in the trailing week it returns no
      # findings and says, in `Sweep`'s log, that it is disarmed. That is not a
      # bug and must not be "fixed" by lowering the threshold to make the check
      # feel useful — an unarmed silence detector is the correct behaviour at
      # launch volume, and the day it arms itself is a good day.
      #
      # ── What covers the gap while it is disarmed ───────────────────────────
      #
      # Fuime::MissedMorPaymentSweepJob, which raises `money_in.webhook_gap`
      # directly. That one does not need a baseline: it compares Stripe's own
      # record of succeeded PaymentIntents against Fuime's ledger, so a single
      # sale that Stripe took and Fuime never recorded is detectable on its own,
      # on the first day, at any volume. It is the stronger of the two checks
      # and this one is the backstop, not the reverse.
      class MoneyIn < Check
        # Two sales a day, sustained for a week, before silence means anything.
        MIN_BASELINE = 14
        BASELINE_WINDOW = 7.days
        SILENCE_WINDOW = 6.hours
        # Below this many sales expected in the silence window, the window is
        # simply too short to conclude anything from — three is the point where
        # a zero stops being ordinary variance.
        MIN_EXPECTED = 3

        def call
          return [] unless ::Fuime::Features.merchant_of_record?

          now = Time.current
          silent_since = now - SILENCE_WINDOW

          recent = ::Fuime::Sale.where(occurred_at: silent_since..).count
          return [] if recent.positive?

          baseline = ::Fuime::Sale.where(occurred_at: (now - BASELINE_WINDOW)...silent_since).count
          return [] if baseline < MIN_BASELINE

          # Sales per hour over the baseline window, scaled to the silence window.
          expected = (baseline.to_f / (BASELINE_WINDOW - SILENCE_WINDOW).in_hours) * SILENCE_WINDOW.in_hours
          return [] if expected < MIN_EXPECTED

          [finding(
            key: "money_in.silent",
            title: "No sales in #{SILENCE_WINDOW.inspect} — about #{expected.round} were expected",
            severity: :sev2,
            expected_sales: expected.round,
            baseline_sales_per_week: baseline,
            silence_window_hours: SILENCE_WINDOW.in_hours.to_i,
            hint: "Check the storefront checkout end to end before assuming a quiet day."
          )]
        end

      end
    end
  end
end
