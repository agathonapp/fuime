# frozen_string_literal: true

# Fuime: the venture's business cards.
#
# ── The authorization split is the interesting part ─────────────────────────
#
#   #index    both — the teen needs to see their card, the guardian needs to see all
#   #create   the GUARDIAN — issuing a card creates a liability they carry
#   #update   the GUARDIAN — raising a limit increases what can be spent
#   #freeze   EITHER — a teen who lost their card must be able to stop it immediately
#   #unfreeze the GUARDIAN — restoring spend is the Accountholder's decision
#   #destroy  the GUARDIAN — cancellation is permanent
#
# Freeze being available to the teen while unfreeze is not is deliberate and is the
# whole design: freezing can only ever reduce what is spendable, so giving it to the
# person most likely to notice a lost card first costs nothing. Making unfreeze
# guardian-only is what stops that from becoming a route around the limit controls.
module Fuime
  class CardsController < ApplicationController
    before_action :set_event
    before_action :set_card, only: [:update, :freeze, :unfreeze, :destroy]

    def index
      authorize @event, :cards?

      @connected_account = @event.stripe_connected_account
      @cardholders = @event.venture_cardholders.includes(:user, :venture_cards)
      @cards = @event.venture_cards.includes(venture_cardholder: :user)

      @can_issue = policy(@event).issue_cards?
      @can_manage = policy(@event).manage_cards?
      @can_freeze = policy(@event).freeze_cards?

      # Who could be given a card but has not been. Drives the issue form's options
      # rather than listing everyone and failing on submit.
      @issuable_cardholders = @cardholders.select(&:issuable?)
      @blocked_cardholders = @cardholders.reject(&:issuable?)
    end

    def create
      authorize @event, :issue_cards?

      cardholder = @event.venture_cardholders.find(params[:venture_cardholder_id])
      service.issue_card!(
        cardholder:,
        spending_limit_cents: limit_cents_param || Fuime::CardIssuingService::DEFAULT_SPENDING_LIMIT_CENTS,
        interval: interval_param
      )

      redirect_to fuime_cards_path(event_slug: @event.slug),
                  notice: "Card issued to #{cardholder.user.name.presence || cardholder.user.email}."
    rescue Fuime::CardIssuingService::Error => e
      redirect_to fuime_cards_path(event_slug: @event.slug), alert: e.message
    end

    def update
      authorize @event, :manage_cards?

      limit = limit_cents_param
      if limit.blank?
        redirect_to fuime_cards_path(event_slug: @event.slug),
                    alert: "Enter a monthly limit of at least $1."
        return
      end

      service.update_spending_limit!(card: @card, spending_limit_cents: limit, interval: interval_param)

      redirect_to fuime_cards_path(event_slug: @event.slug),
                  notice: "Limit updated to #{humanized(limit)} per #{interval_param.sub('ly', '')}."
    rescue Fuime::CardIssuingService::Error => e
      redirect_to fuime_cards_path(event_slug: @event.slug), alert: e.message
    end

    def freeze
      authorize @event, :freeze_cards?

      service.freeze_card!(@card)

      redirect_to fuime_cards_path(event_slug: @event.slug),
                  notice: "Card frozen. Nothing can be spent on it until it's unfrozen."
    rescue Fuime::CardIssuingService::Error => e
      redirect_to fuime_cards_path(event_slug: @event.slug), alert: e.message
    end

    def unfreeze
      authorize @event, :manage_cards?

      service.unfreeze_card!(@card)

      redirect_to fuime_cards_path(event_slug: @event.slug), notice: "Card unfrozen."
    rescue Fuime::CardIssuingService::Error => e
      redirect_to fuime_cards_path(event_slug: @event.slug), alert: e.message
    end

    def destroy
      authorize @event, :manage_cards?

      service.cancel_card!(@card)

      redirect_to fuime_cards_path(event_slug: @event.slug),
                  notice: "Card cancelled. Cancelling can't be undone — issue a new card if one is needed."
    end

    private

    def set_event
      @event = Event.find_by!(slug: params[:event_slug])
    end

    # Scoped through the venture. A bare VentureCard.find would let a guardian of one
    # venture act on another venture's card by id, since the policy is checked against
    # @event rather than against the card.
    def set_card
      @card = @event.venture_cards.find(params[:id])
    end

    def service
      @service ||= Fuime::CardIssuingService.new(event: @event)
    end

    # Same lenient parsing as the payout form: people type dollar signs and commas, and
    # refusing that input teaches a family the tool is broken rather than that they
    # mistyped. Returns nil rather than 0 for unusable input so the caller can say
    # something specific.
    def limit_cents_param
      raw = params[:spending_limit].to_s.gsub(/[^\d.]/, "")
      return nil if raw.blank?

      cents = (BigDecimal(raw) * 100).round
      cents.positive? ? cents : nil
    rescue ArgumentError
      nil
    end

    # Allowlisted against Stripe's own enum. An arbitrary string here would be rejected
    # by Stripe with a message a family could not act on.
    def interval_param
      candidate = params[:interval].to_s
      VentureCard::INTERVALS.include?(candidate) ? candidate : Fuime::CardIssuingService::DEFAULT_INTERVAL
    end

    def humanized(cents)
      ActiveSupport::NumberHelper.number_to_currency(cents.to_i / 100.0)
    end

  end
end
