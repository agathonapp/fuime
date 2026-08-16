# frozen_string_literal: true

# Fuime: where a teenager decides what they sell and what it costs.
#
# The operator side of Fuime::Offer. The buyer side is the storefront, which only
# ever reads `published` offers.
#
# ── Who may act here ────────────────────────────────────────────────────────
#
# The operator, and only the operator. `manage_offers?` resolves through
# EventPolicy's business-operation check, which is the same gate as spending —
# and deliberately NOT the same as the payout gate. A guardian approves money
# leaving; a guardian does not price their kid's work. §8.3 D2 says the operator
# controls their own pricing, and a guardian setting it would be as much a
# third party setting the rate as Fuime doing it.
#
# The guardian still sees everything: reader access renders this page, and every
# offer is visible on the storefront and in the ledger. Visibility without
# control is the intended shape here, and it is the opposite of the payout
# screen, where control is the whole point.
module Fuime
  class OffersController < ApplicationController
    before_action :set_event
    before_action :set_offer, only: %i[update publish unpublish archive restore]

    def index
      authorize @event, :offers?

      @offers = @event.fuime_offers.live.in_operator_order
      @archived = @event.fuime_offers.where(aasm_state: "archived").order(updated_at: :desc)
      @offer = Fuime::Offer.new
      @can_manage = policy(@event).manage_offers?

      # Why publishing may be unavailable, in the operator's own terms. Rendered
      # only on this authenticated page — `Event#selling_blockers` names operators
      # and states their ages, and must never reach a public page (see
      # spec/controllers/fuime/storefront_blocker_privacy_spec.rb).
      @selling_blockers = @event.selling_blockers
    end

    def create
      authorize @event, :manage_offers?

      offer = @event.fuime_offers.new(offer_params)
      offer.position = (@event.fuime_offers.maximum(:position) || 0) + 1

      if offer.save
        redirect_to fuime_offers_path(event_slug: @event.slug),
                    notice: "Saved as a draft. Publish it when you're ready for people to buy it."
      else
        redirect_to fuime_offers_path(event_slug: @event.slug),
                    alert: offer.errors.full_messages.to_sentence
      end
    end

    def update
      authorize @event, :manage_offers?

      if @offer.update(offer_params)
        redirect_to fuime_offers_path(event_slug: @event.slug), notice: "Updated."
      else
        redirect_to fuime_offers_path(event_slug: @event.slug),
                    alert: @offer.errors.full_messages.to_sentence
      end
    end

    def publish
      authorize @event, :manage_offers?

      # The return value is load-bearing. AASM is not whiny by default: when the
      # save behind a transition fails validation it **reverts the in-memory
      # state and returns false** rather than raising. A `publish!` followed by
      # an unconditional success message would therefore tell an operator their
      # offer was live while it sat in draft — and the validation that fires here
      # is the one that refuses to publish for a venture that cannot take
      # payments, i.e. exactly the case a teenager most needs told about.
      unless @offer.publish!
        redirect_to fuime_offers_path(event_slug: @event.slug),
                    alert: @offer.errors.full_messages.to_sentence.presence ||
                           "That couldn't be published."
        return
      end

      redirect_to fuime_offers_path(event_slug: @event.slug),
                  notice: "\"#{@offer.name}\" is live on your storefront."
    rescue AASM::InvalidTransition
      redirect_to fuime_offers_path(event_slug: @event.slug), alert: "That's already published."
    end

    def unpublish
      authorize @event, :manage_offers?

      @offer.unpublish!
      redirect_to fuime_offers_path(event_slug: @event.slug),
                  notice: "Taken off your storefront. It's still here as a draft."
    rescue AASM::InvalidTransition
      redirect_to fuime_offers_path(event_slug: @event.slug), alert: "That isn't published."
    end

    def archive
      authorize @event, :manage_offers?

      @offer.archive!
      redirect_to fuime_offers_path(event_slug: @event.slug),
                  notice: "Archived. Payments people already made for it are unaffected."
    rescue AASM::InvalidTransition
      redirect_to fuime_offers_path(event_slug: @event.slug), alert: "That's already archived."
    end

    def restore
      authorize @event, :manage_offers?

      @offer.restore!
      redirect_to fuime_offers_path(event_slug: @event.slug),
                  notice: "Back as a draft. Check the price before you publish it again."
    rescue AASM::InvalidTransition
      redirect_to fuime_offers_path(event_slug: @event.slug), alert: "That isn't archived."
    end

    # The public page's own settings, edited from the same screen as the things
    # on it.
    #
    # `storefront_tagline` has been a column since the storefront shipped with no
    # UI to edit it — which is how a field ends up permanently blank in
    # production and nobody notices for months.
    #
    # Same authorization as pricing: the operator runs their own shop. A guardian
    # reads it. `manage_offers?` rather than a new predicate, because "who may
    # change how this business presents itself" and "who may price its work" are
    # the same question with the same answer.
    def update_storefront
      authorize @event, :manage_offers?

      if @event.update(storefront_params)
        redirect_to fuime_offers_path(event_slug: @event.slug), notice: "Storefront updated."
      else
        redirect_to fuime_offers_path(event_slug: @event.slug),
                    alert: @event.errors.full_messages.to_sentence
      end
    end

    private

    # Deliberately three fields.
    #
    # `Event` is HCB's core model with a very wide attribute surface, including
    # things that decide whether a venture can spend money. A permissive
    # `params.require(:event).permit!` here would be a mass-assignment hole on a
    # page a 16-year-old can reach. Widen this by naming a field, never by
    # loosening the filter.
    def storefront_params
      params.require(:event).permit(:storefront_tagline, :logo, :is_public)
    end

    def set_event
      @event = Event.find_by!(slug: params[:event_slug])
    end

    # Scoped through the venture rather than found globally, so an operator of
    # one venture cannot act on another's offer by id.
    def set_offer
      @offer = @event.fuime_offers.find(params[:id])
    end

    def offer_params
      params.require(:fuime_offer)
            .permit(:name, :description, :unit_label, :position, :slug)
            .merge(price_cents: price_cents_param)
    end

    # Accepts what a person types — "35", "35.00", "$35", "1,250.50".
    #
    # Returns nil rather than 0 on unparseable input, so the model's numericality
    # message ("has to be an amount you've decided on") is what the operator
    # reads. Zero would produce "must be greater than 0", which sounds like Fuime
    # rejecting their price rather than not having understood it.
    #
    # Nothing here supplies a fallback price. See Fuime::Offer's header: a
    # default is a Fuime-set rate for anybody who does not change it (§8.3 D2).
    def price_cents_param
      raw = params.dig(:fuime_offer, :price).to_s.gsub(/[^0-9.]/, "")
      return nil if raw.blank?

      (BigDecimal(raw) * 100).round
    rescue ArgumentError
      nil
    end

  end
end
