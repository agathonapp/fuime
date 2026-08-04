# frozen_string_literal: true

# Fuime: Start a Stripe Checkout session from a business's public storefront.
#
# This is the "money in" entry point — the half of the payment flow that was
# missing. `Fuime::PaymentLinkService` and `Fuime::PaymentWebhookHandler` were
# both already built, but nothing called the service, so the storefront's Pay
# button was hardcoded `disabled` and no payment could ever be started.
#
# Public and unauthenticated by design: the payer is a customer, not a Fuime
# user. The business is identified by slug, exactly as the storefront is.
module Fuime
  class CheckoutsController < ApplicationController
    skip_before_action :signed_in_user
    skip_after_action :verify_authorized

    # Guardrails on a public, unauthenticated endpoint that talks to Stripe.
    MINIMUM_AMOUNT_CENTS = 1_00
    MAXIMUM_AMOUNT_CENTS = 10_000_00

    def create
      event = ::Event.find_by!(slug: params[:slug])

      # Only businesses that have published a storefront can be paid. Without
      # this, the endpoint would take payments for any org by slug, including
      # ones deliberately kept private.
      unless event.is_public
        redirect_to root_path, alert: "This business is not accepting payments."
        return
      end

      # …and only ventures whose guardian has completed Stripe setup. `is_public`
      # defaults to true, so it never gated anything meaningful — every activated
      # venture presented a working payment form. Under the connected-account
      # model there is nowhere for the money to go until a guardian has onboarded,
      # so this is the check that makes the form honest.
      unless event.accepts_payments?
        redirect_to fuime_storefront_path(slug: event.slug),
                    alert: "This business isn't set up to accept payments yet."
        return
      end

      amount_cents = parse_amount(params[:amount])
      if amount_cents.nil?
        redirect_to fuime_storefront_path(slug: event.slug),
                    alert: "Enter an amount between $1 and $10,000."
        return
      end

      session = ::Fuime::PaymentLinkService.new(
        event:,
        amount_cents:,
        description: payment_description(event)
      ).create_checkout_session(
        success_url: fuime_storefront_url(slug: event.slug, paid: 1),
        cancel_url: fuime_storefront_url(slug: event.slug)
      )

      redirect_to session.url, allow_other_host: true
    rescue Stripe::StripeError => e
      # Never surface a raw Stripe error to a customer, and never leave the
      # storefront on an error page mid-demo.
      Rails.error.report(e)
      Rails.logger.error("[Fuime] Checkout failed for #{params[:slug]}: #{e.message}")
      redirect_to fuime_storefront_path(slug: params[:slug]),
                  alert: "We couldn't start that payment. Please try again."
    end

    private

    # The payer types this, and it ends up on the Stripe product and then in the
    # ledger memo a teenager reads. Bound the length and strip control
    # characters so an anonymous stranger can't write arbitrary text onto a
    # child's ledger.
    MAX_DESCRIPTION_LENGTH = 120

    def payment_description(event)
      supplied = params[:description].to_s.gsub(/[[:cntrl:]]/, "").strip
      return "Payment to #{event.name}" if supplied.blank?

      supplied.truncate(MAX_DESCRIPTION_LENGTH)
    end

    def parse_amount(raw)
      # Accepts "25", "25.00", "$25.00", "1,250".
      cleaned = raw.to_s.gsub(/[^0-9.]/, "")
      return nil if cleaned.blank?

      cents = (BigDecimal(cleaned) * 100).round
      return nil if cents < MINIMUM_AMOUNT_CENTS || cents > MAXIMUM_AMOUNT_CENTS

      cents
    rescue ArgumentError
      nil
    end

  end
end
