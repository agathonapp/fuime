# frozen_string_literal: true

# Fuime: the public shop window of listed offers.
#
# ── What this is, and what it is not ────────────────────────────────────────
#
# A LISTING of offers a founder has already chosen to put in the shop window.
# Not a dispatch, not a marketplace homepage, and not the path a first sale
# takes. At n=1 the working path is the payment link the founder already has
# (`/pay/:event_slug/:offer`). Discover does not invent a crowd to browse.
#
# The venture directory at `/directory` stays as it is: businesses, no prices.
# This page is the offer shop. The two must not be collapsed — a directory spec
# that asserts "quotes no prices" would break, and a Discover card that omitted
# the operator's price would be a listing that does not say what it costs.
#
# ── The constraint that shapes every decision here ──────────────────────────
#
# Same legal line as Fuime::DirectoryController (MOR_MIGRATION_PLAN §8.3 D2):
# operators publish; buyers browse and pay them. Fuime never assigns a buyer to
# an operator, never sets or suggests a price, and never ranks anyone by quality.
#
# Concretely, and enforced by spec/requests/fuime_discover_spec.rb:
#
#   * ordering is neutral (newest first, or A–Z) — never a quality score
#   * no ratings, reviews, featured, popular, recommended, or best match
#   * no search that needs inventory, no social proof
#   * the price on a card is `offer.price_cents` — the operator's number
#   * every card links to `/b/:slug` with no query string. Checkout reads the
#     price off the offer record. Passing an amount or offer_token through
#     Discover would let this page become a second checkout.
#
# ── What may be listed ──────────────────────────────────────────────────────
#
# Listed + published offers on a venture that is already publicly visible AND
# can actually be paid. The moment any of that is false the card drops. An
# unlisted published offer is a private pay link and stays on `/pay/` — it is
# not Discover, and Discover must 404 it rather than show a dead card or
# bounce with a flash.
module Fuime
  class DiscoverController < ApplicationController
    skip_before_action :signed_in_user
    skip_after_action :verify_authorized

    PER_PAGE = 24

    ORDERINGS = {
      "newest" => "Newest first",
      "name"   => "A–Z",
    }.freeze

    def index
      @ordering = ORDERINGS.key?(params[:order]) ? params[:order] : "newest"

      scope = ::Fuime::Offer.in_discover_window
                            .includes(event: [:stripe_connected_account, :plan])
                            .unscope(:order)
      scope = if @ordering == "name"
                scope.order(Arel.sql("LOWER(events.name) ASC"), Arel.sql("LOWER(fuime_offers.name) ASC"))
              else
                scope.order("fuime_offers.created_at DESC")
              end

      # #accepts_payments? cannot be expressed in SQL — see DirectoryController.
      # Filtering in Ruby over one page is the honest trade; a short page beats
      # a card that leads to a dead storefront.
      @page = scope.page(params[:page]).per(PER_PAGE)
      @offers = @page.select { |offer| offer.event.accepts_payments? }
    end

    # Offer-scoped deep link. Valid listed+payable offers send the buyer to the
    # storefront with no query string. Everything else 404s — unlisted, draft,
    # archived, missing, or a venture that cannot be paid. Not a flash redirect:
    # a 302 with "that isn't for sale" tells a stranger the token space is worth
    # probing, and would also leak that a private pay link exists.
    def show
      offer = discover_offer
      return render_not_found unless offer&.in_discover_window?

      redirect_to fuime_storefront_path(slug: offer.event.slug)
    end

    private

    def discover_offer
      venture = ::Event.not_hidden.find_by(slug: params[:event_slug])
      return nil if venture.nil?

      ::Fuime::Offer.find_public(venture.fuime_offers, params[:offer])
    end

    def render_not_found
      respond_to do |format|
        format.html { render "fuime/discover/not_found", status: :not_found }
        format.any  { head :not_found }
      end
    end

  end
end
