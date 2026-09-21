# frozen_string_literal: true

module Fuime
  # Scheduled wrapper for the missed-payment sweep — see the service header for
  # the failure modes it recovers from.
  #
  # This exists as a schedule rather than a rake task anybody remembers to run
  # because the failure it covers is silent by construction: if the webhook never
  # arrives, nothing anywhere reports a problem. The founder sees an empty ledger
  # after a real sale and concludes the product is broken, which is the one
  # impression there is no recovering from (TEEN_GROWTH G10).
  #
  # Hourly, not every 30 minutes. The sweep lists PaymentIntents on the platform
  # account over a 24-hour window, so a shorter cadence re-reads the same page of
  # Stripe results for no new information. A sale delayed an hour is invisible to
  # the founder; a sale lost entirely is not.
  class MissedMorPaymentSweepJob < ApplicationJob
    queue_as :low

    def perform
      # The sweep reads PaymentIntents on the PLATFORM account, which is only
      # where storefront sales live under merchant-of-record. With MoR off those
      # intents belong to connected accounts and this would sweep the wrong
      # ledger, so it declines rather than guessing.
      return unless ::Fuime::Features.merchant_of_record?

      result = Fuime::MissedMorPaymentSweep.sweep!
      report_to_oncall(result)
      result
    end

    private

    # Fuime: a recovery that recovers something is an incident.
    #
    # ── Why this is the strongest money-in check Fuime has ────────────────
    #
    # Every other way of noticing a broken checkout is statistical: sales are
    # lower than usual, the graph looks wrong, nobody has bought anything in six
    # hours. All of those need a baseline before they mean anything, and at
    # launch volume Fuime does not have one (see Checks::MoneyIn, which disarms
    # itself for exactly that reason).
    #
    # This one needs no baseline at all. It compares Stripe's own record of
    # succeeded PaymentIntents against Fuime's ledger, so ONE sale that Stripe
    # took and Fuime never recorded is conclusive on the first day at any
    # volume. `posted > 0` is not "the safety net did its job" — it is "the
    # primary path is broken and has been since at least the oldest intent in
    # this window".
    #
    # The sale itself is already recovered by the time this runs; the founder
    # will see it. What the incident is for is the NEXT sale, which the same
    # broken webhook path will also drop, and which may be in a window this
    # sweep no longer looks at.
    def report_to_oncall(result)
      posted = result.is_a?(Hash) ? result[:posted].to_i : 0

      if posted.zero?
        ::Fuime::Incident.auto_resolve!(key: "money_in.webhook_gap")
        return
      end

      ::Fuime::Incident.raise!(
        key: "money_in.webhook_gap",
        # Not one of Check.all, on purpose: Fuime::Oncall::Sweep auto-resolves
        # incidents belonging to checks it ran, and this detector runs on its own
        # hourly schedule. A check_name the sweep does not know is what keeps it
        # from closing an incident it never looked at.
        check_name: "missed_payment_sweep",
        title: "#{posted} paid #{'sale'.pluralize(posted)} never reached the ledger from a webhook",
        # Sev-1: money changed hands and Fuime did not know. Every subsequent
        # sale is landing in the same hole, the founder is watching an empty
        # ledger after a real order, and the recovery window is finite.
        severity: :sev1,
        detail: {
          "recovered_sales" => posted,
          "skipped"         => result[:skipped],
          "impact"          => "Stripe took the money and the venture's ledger did not show it. " \
                      "This sweep recovered these; the next sale will be dropped the same way.",
          "hint"            => "Check the Stripe webhook endpoint is reachable and that payment_intent.succeeded is still ticked."
        }
      )
    rescue => e
      # The sweep's own work is done and correct by this point. Failing to
      # report must not undo it or fail the job.
      Rails.logger.error("[Fuime] could not raise the webhook-gap incident: #{e.class}: #{e.message}")
    end

  end
end
