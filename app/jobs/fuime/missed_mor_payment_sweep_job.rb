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

      Fuime::MissedMorPaymentSweep.sweep!
    end

  end
end
