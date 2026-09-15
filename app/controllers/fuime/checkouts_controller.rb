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
#
# Anyone may buy, signed in or not. The pay link a teen texts to a customer has
# always worked without a Fuime account, and as of 2026-09-15 a signed-in buyer
# is treated no differently — see #refuse_minor_buyer for why the old
# adult-only rule protected nobody while blocking teen-to-teen sales.
module Fuime
  class CheckoutsController < ApplicationController
    skip_before_action :signed_in_user
    skip_after_action :verify_authorized
    # Checkout is a customer action, not operating a business. Without this, a
    # parked teen's POST is swallowed by the guardian-invite redirect — so a
    # teenager who has not yet invited a guardian cannot buy from anyone.
    skip_before_action :enforce_guardianship_requirement
    # FUIME-DISABLED (2026-09-15): `before_action :refuse_minor_buyer`.
    # The rule and the full reasoning are on the method itself. Restoring it is
    # this one line.

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

      # Playground Mode: click the real Buy / share path, never live Stripe.
      # Handled before `accepts_payments?` — demo ventures fail that check on
      # purpose (OperatorEligibility administrative blocker).
      if event.demo_mode?
        complete_playground_checkout!(event)
        return
      end

      # ── Sandbox Mode ──────────────────────────────────────────────────────
      #
      # A founder rehearsing their own storefront. Checked BEFORE
      # `accepts_payments?` on purpose: the moment a teenager most wants to see
      # what a customer sees is while their guardian is still finishing Stripe
      # onboarding, and a rehearsal reaches nothing that setup would provide.
      #
      # #sandbox_checkout? is deliberately narrow — the venture has the flag on
      # AND the person clicking is an operator of THIS venture. A customer is
      # never diverted here, which is what makes it safe for a founder to leave
      # Sandbox Mode switched on and forget about it: the worst case is that
      # they see a banner they stopped reading, not that they lose a sale.
      if sandbox_checkout?(event)
        start_sandbox_checkout!(event)
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
        description: offer&.payment_description || payment_description(event),
        # Decides one-time vs subscription, and carries the offer's identity into
        # metadata so a renewal arriving next year can still be attributed.
        offer:
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

    # FUIME-DISABLED (2026-09-15): the signed-in buyer age rule.
    #
    # It refused a Stripe session to any signed-in user we could not positively
    # confirm was an adult. Removed, for three reasons — the first of which is
    # that it never actually prevented anything:
    #
    #   1. **It was bypassable by design, and said so.** Its own refusal read
    #      "Sign out to pay as a guest." Guests have always been able to check
    #      out — the pay link a teen texts a customer has to work without a
    #      Fuime account. So a minor determined to buy opened a private window
    #      and bought. The rule stopped no minor from paying; it only stopped
    #      the ones honest enough to be signed in.
    #   2. **It blocked teen-to-teen sales**, which are a core Fuime case, not an
    #      edge one. A teenager buying from another teenager's storefront is the
    #      product working.
    #   3. **Unknown age failed closed, and unknown is the common case.**
    #      `User#is_minor?` is `age&.<(18)` — nil when no birthday is on record —
    #      so `known_adult?` fell through to an attestation most accounts have
    #      never made. Every signed-in user without a date of birth, adult or
    #      not, was refused.
    #
    # Not a legal requirement. LEGAL_RESEARCH.md carries no constraint on who
    # may BUY; L2 governs the operator's account and ToS — guardian as principal
    # obligor — not the customer. The doctrine the rule invoked cuts the other
    # way in that document's own words (§205): "minors *can* sign; contracts are
    # voidable." Voidable is a chargeback risk Fuime already carries on every
    # guest sale, and a signed-in buyer is the better-evidenced version of it.
    #
    # Kept as a method rather than deleted (Rule 2) so restoring the rule is one
    # line — put `before_action :refuse_minor_buyer` back and drop the early
    # return. #refuse_minor and #adult? stay for the same reason.
    def refuse_minor_buyer
      return unless current_user
      return if adult?
      # Playground Mode bills nobody, so there is no adult to bill. The person
      # pressing Buy on the pitch venture is usually an admin impersonating
      # Maya, who is 16 — refusing her bounced the demo's own Buy button.
      return if playground_event?

      # Sandbox Mode bills nobody either, and here the minor is the entire
      # point: the founder rehearsing the flow is a teenager, and this rule
      # exists to stop a minor being CHARGED. A rehearsal charges no one, so
      # applying it here would make the feature unusable by the only people it
      # was built for. The narrow #sandbox_checkout? gate still means this
      # bypass is unreachable for anyone but an operator of this venture.
      return if sandbox_event?

      refuse_minor
    end

    def sandbox_event?
      event = ::Event.not_hidden.find_by(slug: params[:slug])
      return false if event.nil?

      sandbox_checkout?(event)
    end

    def playground_event?
      ::Event.not_hidden.find_by(slug: params[:slug])&.demo_mode? || false
    end

    # Whoever is driving the demo: an admin impersonating a persona, or staff
    # signed in as themselves. Only their Buy writes a ledger line — a stranger
    # who finds the public storefront gets the thank-you screen and nothing
    # else, so the endpoint cannot be used to grow the ledger from outside.
    def demo_driver?
      current_session&.impersonated? || current_user&.staff? || false
    end

    def adult?
      current_user.known_adult? || current_user.staff?
    end

    def refuse_minor
      redirect_to refuse_destination,
                  alert: "Checkout is billed to an adult. Sign out to pay as a guest, or ask a parent or guardian to complete this payment."
    end

    def refuse_destination
      event = ::Event.not_hidden.find_by(slug: params[:slug])
      return root_path unless event

      offer = find_offer(event)
      return_url(event, offer)
    end

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
    PLAYGROUND_NOTICE = "Playground Mode — no real charge. This is what a customer sees after paying."
    PLAYGROUND_RECORDED_NOTICE = "Playground Mode — no real charge. This is what a customer sees after paying, and the sale is on the ledger now."

    def complete_playground_checkout!(event)
      offer = find_offer(event)
      if params[:offer_token].present? && offer.nil?
        redirect_to fuime_storefront_path(slug: event.slug),
                    alert: "That isn't for sale right now."
        return
      end

      notice = PLAYGROUND_NOTICE
      if demo_driver?
        amount_cents = offer&.price_cents || parse_amount(params[:amount])
        recorded = ::Fuime::Playground.new.record_mock_sale!(
          event:,
          memo: offer ? "#{offer.name} — storefront" : "#{payment_description(event)} — storefront",
          amount_cents:
        )
        notice = PLAYGROUND_RECORDED_NOTICE if recorded
      end

      redirect_to return_url(event, offer, paid: true), notice:
    end

    # Is this Buy click a rehearsal?
    #
    # Both halves are required, and the second one is the whole safety argument:
    # `manage_sandbox?` is the operator gate (EventPolicy), so a customer, a
    # stranger with the link, a signed-out visitor and a member of a DIFFERENT
    # venture all fail it and fall through to the real Stripe path.
    #
    # Not `policy(event)` — Pundit's helper memoizes per record and this runs on
    # a public controller where `current_user` may be nil.
    def sandbox_checkout?(event)
      return false unless event.sandbox_mode?
      return false if current_user.blank?
      return false unless ::StripeService.sandbox_available?

      EventPolicy.new(current_user, event).manage_sandbox?
    end

    # Send the founder to Stripe's own hosted checkout, in test mode.
    #
    # This is a REAL Stripe Checkout Session — real hosted page, Stripe's own
    # Test Mode banner, `4242 4242 4242 4242` — created with the test-mode key
    # (StripeService.sandbox_secret_key), so it can only ever take a test card
    # and can only ever produce `livemode: false` objects.
    #
    # Rehearsing against a mock was the earlier implementation, and the reason it
    # was replaced is that a mock cannot fail the way production fails. The parts
    # most likely to be broken for a given venture — the hosted page rendering,
    # the redirect, the success URL coming back to the right screen — are exactly
    # the parts a mock skips.
    #
    # The success URL carries Stripe's `{CHECKOUT_SESSION_ID}` template so the
    # return leg can ask Stripe what actually happened rather than trust the
    # redirect. See Fuime::SandboxCheckout.
    def start_sandbox_checkout!(event)
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
        description: offer&.payment_description || payment_description(event),
        offer:,
        sandbox: true
      ).create_checkout_session(
        success_url: sandbox_return_url(event, offer),
        cancel_url: return_url(event, offer)
      )

      redirect_to session.url, allow_other_host: true
    rescue ::Stripe::StripeError => e
      # A rehearsal that cannot start is a Fuime configuration problem, not
      # something the founder did. Say so plainly rather than showing them the
      # customer-facing "please try again" — they are the one person who can
      # report it, and "we couldn't start that payment" would read to them as
      # their own storefront being broken.
      Rails.error.report(e)
      Rails.logger.error("[Fuime] Sandbox checkout failed for #{event.slug}: #{e.message}")
      redirect_to fuime_sandbox_path(event_slug: event.slug),
                  alert: "Test mode couldn't reach Stripe. This is a Fuime problem, not yours — your real storefront is unaffected."
    end

    # Where Stripe returns a rehearsing founder. `{CHECKOUT_SESSION_ID}` is
    # Stripe's own template — it substitutes the real id on redirect — so it must
    # survive URL building unescaped, which is why it is appended rather than
    # passed as a query param.
    def sandbox_return_url(event, offer)
      base = return_url(event, offer, paid: true)
      separator = base.include?("?") ? "&" : "?"
      "#{base}#{separator}sandbox_session={CHECKOUT_SESSION_ID}"
    end

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
