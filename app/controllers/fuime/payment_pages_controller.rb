# frozen_string_literal: true

# Fuime: one link, one thing, one price.
#
# The page an operator SENDS, as opposed to the storefront a customer BROWSES.
# A 16-year-old shipping a site on Replit, posting on Instagram or sending a DM
# wants a URL for the one thing they sell — not a shop the buyer has to navigate.
# Same shape as a Stripe Payment Link, and the missing half of the public side.
#
# ── Public, unauthenticated, and hostile-input territory ────────────────────
#
# The payer is a customer, not a Fuime user. Everything here arrives from a
# stranger and the same rules as Fuime::CheckoutsController apply: the price
# comes off the record and never off the request, and the token is looked up
# against PUBLISHED offers only.
#
# ── What this page deliberately does not say ────────────────────────────────
#
# Who runs the business. The storefront already reasons about this at length —
# a minor's first name plus a price is a targeting profile, so the owner's name
# appears only when the owner is a confirmed adult. This page shows less than the
# storefront does, not more: the business name, the thing, the price. A stranger
# following a link from a Replit site is entitled to know what they are buying
# and from which business, and nothing about the child running it.
module Fuime
  class PaymentPagesController < ApplicationController
    skip_before_action :signed_in_user
    skip_after_action :verify_authorized

    layout "fuime_payment_page"

    def show
      @offer = published_offer
      return render_not_found if @offer.nil?

      @event = @offer.event

      # A payment page for a venture that has stopped being able to sell must say
      # so rather than showing a dead button. Unlike the storefront — which stays
      # useful as a description of the business — this page has exactly one
      # purpose, so when it cannot serve it the honest thing is to say why.
      @accepts_payments = @event.show_public_pay_button?

      # Fuime: …or the operator is rehearsing. Sandbox Mode's whole value is
      # seeing the Buy button BEFORE the venture can take real money — that is
      # the moment a founder most wants to know their link works, and a
      # rehearsal reaches nothing the missing setup would have provided.
      # Fuime::CheckoutsController checks the same condition before Stripe, so
      # the button this renders cannot 404 into a real charge.
      @accepts_payments ||= helpers.sandbox_rehearsal?(@event)

      # Fuime: the return leg of a rehearsal. Stripe sends the founder back here
      # with `sandbox_session=cs_test_…`; we ask Stripe what actually happened
      # rather than trusting the redirect, and record a Fuime::TestSale.
      # Idempotent on the session id, so a refresh does not double-count.
      @sandbox_result =
        if params[:sandbox_session].present? && helpers.sandbox_rehearsal?(@event)
          ::Fuime::SandboxCheckout.new(
            event: @event, user: current_user, session_id: params[:sandbox_session]
          ).record!
        end
      @paid = params[:paid] == "1"

      # ── FUIME: the founder looking at their own pay page ─────────────────
      #
      # A founder could publish a product and then never see what they had
      # made. Pressing Buy on their own page bounced them with "Checkout is
      # billed to an adult" — a message about somebody else's purchase, on
      # their own storefront, which reads as "your page is broken".
      #
      # The refusal itself is right and stays: a minor reaching Stripe could
      # actually complete a payment, and a minor's payment authorisation is
      # voidable (L2). Letting the founder through to checkout to "just look"
      # would be letting a minor transact.
      #
      # So this is a preview instead of a refusal. Same page the customer sees,
      # with the button replaced by a plain statement of what goes there. No
      # Stripe session is created, nothing is charged, and the founder can
      # finally see their own product.
      @previewing_own_page = current_user.present? &&
                             !current_user.known_adult? &&
                             @event.users.exists?(id: current_user.id)
    end

    private

    # Published offers on public ventures only.
    #
    # Both halves matter. An unpublished offer is one the operator has taken off
    # sale, and a link that keeps working after they do is a link they cannot
    # revoke. A non-public venture has deliberately not published a storefront,
    # and a payment page is a public page.
    #
    # Resolved venture-first so the offer identifier is namespaced: `mow` means
    # this business's mow, and a slug or token belonging to another business
    # finds nothing here rather than quietly charging for somebody else's work.
    def published_offer
      venture = ::Event.not_hidden.find_by(slug: params[:event_slug], is_public: true)
      return nil if venture.nil?

      ::Fuime::Offer.find_public(venture.fuime_offers.published, params[:offer])
    end

    # 404 rather than a redirect with a flash.
    #
    # A redirect to the root with "that isn't for sale" tells whoever is probing
    # that the token space is worth probing. A plain not-found says nothing about
    # whether the token ever existed, which is the correct answer to a stranger
    # guessing.
    def render_not_found
      respond_to do |format|
        format.html { render "fuime/payment_pages/not_found", status: :not_found, layout: "fuime_payment_page" }
        format.any  { head :not_found }
      end
    end

  end
end
