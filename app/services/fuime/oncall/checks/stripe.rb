# frozen_string_literal: true

module Fuime
  module Oncall
    module Checks
      # Fuime: can this app still talk to Stripe?
      #
      # Sev-1, because under merchant-of-record Stripe is not a feature of Fuime
      # — it is the whole of money-in. If this call fails, no teenager can take a
      # payment, and the storefront will be failing in whatever way a Stripe
      # error surfaces at checkout.
      #
      # ── An expired or revoked key looks identical to an outage from here ────
      #
      # Deliberately not distinguished. Both mean no sales, both need somebody
      # now, and guessing between them in the page body would only ever be a
      # guess. The detail carries the error class so whoever wakes up can tell in
      # one look.
      #
      # `Stripe::Balance.retrieve` is the ping: it is the cheapest authenticated
      # call, it touches no object this app owns, and it cannot create anything.
      class Stripe < Check
        TIMEOUT_SECONDS = 10

        def call
          key = StripeService.secret_key
          if key.blank?
            return [finding(
              key: "stripe.no_credential",
              title: "No Stripe secret key is configured",
              severity: :sev1,
              mode: StripeService.mode,
              impact: "Checkout cannot be created. Every sale fails."
            )]
          end

          started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          # Two hashes, and the order matters: the first is request PARAMS and
          # the second is per-request OPTIONS. Passing the key in the first
          # position sends it as a query parameter, and Stripe answers
          # "Received unknown parameter: api_key" — a 400 that this check would
          # then report as Stripe being down. A monitoring check that
          # manufactures its own outage is worse than no check.
          ::Stripe::Balance.retrieve({}, { api_key: key })
          elapsed_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round

          return [] if elapsed_ms <= 5_000

          [finding(
            key: "stripe.slow",
            title: "Stripe API took #{elapsed_ms}ms to answer",
            severity: :sev2,
            round_trip_ms: elapsed_ms
          )]
        rescue ::Stripe::StripeError, ::Stripe::APIConnectionError => e
          [finding(
            key: "stripe.unreachable",
            title: "Stripe is not answering (#{e.class.name.demodulize})",
            severity: :sev1,
            error_class: e.class.name,
            error: e.message.to_s.truncate(300),
            mode: StripeService.mode,
            impact: "No teenager can take a payment while this is true."
          )]
        end

      end
    end
  end
end
