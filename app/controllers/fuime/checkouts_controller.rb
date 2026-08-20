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
      # `.not_hidden` for the reason Fuime::StorefrontsController now does: an
      # admin-hidden venture must not be payable. Its OTHER states — frozen, demo
      # mode — are refused by #accepts_payments? below, which now asks
      # Fuime::OperatorEligibility about all three.
      event = ::Event.not_hidden.find_by!(slug: params[:slug])

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

      # ── Buying an offer, or paying an amount ──────────────────────────────
      #
      # Two shapes, and the difference is who chose the number.
      #
      # With an offer, the operator set the price and the buyer is agreeing to
      # it: the amount comes off the record and the buyer's input is ignored
      # entirely. That is not a UI nicety — a posted `amount` alongside an
      # `offer_id` would let a stranger buy a $35 lawn mow for $1, and reading
      # the price from the record is the only version of this that cannot be
      # rewritten in a form.
      #
      # Without one, the old free-amount path stands. It is still the right thing
      # for a venture that has not listed anything yet, and for the customer who
      # was told a price in person.
      offer = find_offer(event)
      if params[:offer_token].present? && offer.nil?
        redirect_to fuime_storefront_path(slug: event.slug),
                    alert: "That isn't for sale right now."
        return
      end

      amount_cents = offer&.price_cents || parse_amount(params[:amount])
      if amount_cents.nil?
        redirect_to fuime_storefront_path(slug: event.slug),
                    alert: "Enter an amount between $1 and $10,000."
        return
      end

      session = ::Fuime::PaymentLinkService.new(
        event:,
        amount_cents:,
        description: offer&.payment_description || payment_description(event)
      ).create_checkout_session(
        success_url: return_url(event, offer, paid: true),
        cancel_url: return_url(event, offer)
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

    # The offer being bought, if one was named.
    #
    # Never by id, so the primary key does not appear in public HTML. The
    # storefront's Buy buttons and the payment page both post `offer.to_param` —
    # the operator's slug when they have chosen one, the permanent token when
    # they have not. See Fuime::Offer.find_public and AddSlugToFuimeOffers.
    #
    # Scoped to this venture's PUBLISHED offers. Both halves matter: a token from
    # another venture would charge this buyer for something this business does
    # not sell and credit the wrong operator's ledger, and a draft or archived
    # offer is one the operator has deliberately taken off sale — a stale link
    # must not still be able to buy it.
    def find_offer(event)
      return nil if params[:offer_token].blank?

      # Slug or token — see Fuime::Offer.find_public. Scoped to this venture's
      # published offers either way.
      ::Fuime::Offer.find_public(event.fuime_offers.published, params[:offer_token])
    end

    # Where Stripe sends the buyer back to.
    #
    # The page they came from, which for a payment link is the payment page
    # itself. Bouncing a customer who followed a direct link into a storefront
    # they never asked to see is the browse step the link exists to avoid — and
    # it hands them a shop when what they wanted was a receipt.
    def return_url(event, offer, paid: false)
      if offer.present?
        return fuime_payment_page_url(event_slug: event.slug, offer: offer.to_param,
                                      **(paid ? { paid: 1 } : {}))
      end

      fuime_storefront_url(slug: event.slug, **(paid ? { paid: 1 } : {}))
    end

    def payment_description(event)
      # Control characters, and now square brackets.
      #
      # A bracketed "[fuime_…]" in a memo is how Fuime::PayablesLedger classifies
      # a ledger line, so an anonymous stranger typing "[fuime_fee_x" into this
      # box on a public page could make a teenager's $35 sale appear on their own
      # earnings page as a $35 platform fee. Unauthenticated free text that
      # reaches a ledger is exactly the input that has to be assumed hostile.
      #
      # See Fuime::VentureLedger.sanitize_memo_text. Stripped rather than refused
      # because there is nobody here to tell — the payer is a customer, not a
      # Fuime user, and a validation error on a checkout is a lost sale for a
      # child over a character they had no reason to avoid.
      supplied = ::Fuime::VentureLedger.sanitize_memo_text(params[:description])
                                       .gsub(/[[:cntrl:]]/, "").strip
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
