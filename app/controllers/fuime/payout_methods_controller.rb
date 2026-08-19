# frozen_string_literal: true

# Fuime: where an operator says their money should go.
#
# Four surfaces:
#
#   #show        the page — readable by the whole team, actionable by the adult
#   #link_token  JSON, mints the token Plaid Link needs (adult only)
#   #create      what Link returns, exchanged into a verified destination
#   #destroy     retiring a destination
#
# ── The authorization shape ─────────────────────────────────────────────────
#
# The same split as Fuime::PaymentSetupsController, for the same reason. The teen
# reads and the responsible adult acts, because the bank account is the adult's —
# a minor generally cannot open one (MOR_MIGRATION_PLAN §4.3) — and because a
# teen who could repoint the destination could route their earnings past the
# approval that makes the ownership structure real (CLAUDE.md L2).
#
# `connect_payout_method?` resolves to the guardian on a family venture and to a
# manager on a school one; this controller does not know the difference.
#
# ── Why this page exists regardless of the flag ─────────────────────────────
#
# The nav item is merchant-of-record only, because under Connect the destination
# is Stripe's business and a second bank connection would be a redundant thing to
# ask a family for. But the page itself is reachable by URL in every
# configuration, and that is deliberate: FEATURE_MERCHANT_OF_RECORD cannot be
# turned on in production until counsel answers §7 Q1/Q2/Q4, and a flow nobody
# can run even once is how this repository has twice shipped an integration that
# had never touched the service it integrates with. What the page will not do is
# claim the destination is in use when it is not — see the view.
module Fuime
  class PayoutMethodsController < ApplicationController
    before_action :set_event
    before_action :authorize_connect, only: [:link_token, :create, :destroy]
    # Not :destroy — removing a destination must always be possible, including
    # (especially) a sandbox one somebody connected before this gate existed.
    before_action :refuse_uncollectable, only: [:link_token, :create]

    def show
      authorize @event, :payout_method?

      @payout_method = @event.fuime_payout_methods.live.first
      @can_connect = policy(@event).connect_payout_method?
      @configured = ::Fuime::PlaidLinkService.configured?
      @sandbox = ::Fuime::PlaidLinkService.sandbox?
      # Plaid is reachable but must not be used yet — sandbox alongside live
      # Stripe. See Fuime::PlaidLinkService.collectable?.
      @collectable = ::Fuime::PlaidLinkService.collectable?

      # What Fuime owes them, which is the reason this page is worth their time.
      # Under MoR a venture with no destination is SKIPPED from every payout run
      # (Fuime::PayableAssessment), so the amount waiting is the honest argument
      # for connecting a bank — and the same figure the Payouts page shows,
      # read through the same presenter so the two cannot disagree.
      @payables = ::Fuime::PayablesLedger.new(event: @event)

      # Whether this destination is what the payout run actually reads. False
      # under Connect, where the money is already in the family's own Stripe
      # account and this row is a preparation rather than a live setting.
      @in_use = ::Fuime::Features.merchant_of_record?

      # The adults who could act, so a teen reading this page is told who to ask
      # rather than shown a button that does nothing for them.
      @responsible_adults = @event.institutionally_sponsored? ? [] : @event.overseeing_guardians
    end

    # A fresh Link token per request.
    #
    # JSON only and POST rather than GET: minting one is a write at Plaid, and a
    # token is single-use, so a prefetching browser or a link-scanner following a
    # GET would burn tokens the operator then can't use.
    def link_token
      render json: { link_token: service.link_token }
    rescue ::Fuime::PlaidLinkService::NotConfigured => e
      # An operator problem, not the family's. Logged as info rather than
      # reported: nothing is broken, something was never set up.
      Rails.logger.info("[Fuime] Plaid link token requested while unconfigured: #{e.message}")
      render json: { error: "Connecting a bank isn't available right now." }, status: :service_unavailable
    rescue ::Fuime::PlaidLinkService::Error => e
      render json: { error: e.message }, status: :service_unavailable
    end

    def create
      payout_method = service.connect!(
        public_token: params[:public_token],
        account_id: params[:account_id]
      )

      redirect_to fuime_payout_method_path(event_slug: @event.slug),
                  notice: "#{payout_method.display_name} is connected. #{next_step_sentence}"
    rescue ::Fuime::PlaidLinkService::NotConfigured
      redirect_to fuime_payout_method_path(event_slug: @event.slug),
                  alert: "Connecting a bank isn't available right now."
    rescue ::Fuime::PlaidLinkService::Error => e
      # Already written for a family to read — surfaced verbatim rather than
      # replaced with something generic, the same handling Fuime::PayoutsController
      # gives its service errors.
      redirect_to fuime_payout_method_path(event_slug: @event.slug), alert: e.message
    rescue ActiveRecord::RecordInvalid => e
      redirect_to fuime_payout_method_path(event_slug: @event.slug),
                  alert: e.record.errors.full_messages.to_sentence
    end

    # Retiring a destination.
    #
    # Scoped through the venture rather than found by bare id, for the same
    # reason Fuime::PayoutsController scopes its requests: `connect_payout_method?`
    # is checked against @event, so a global find would let a guardian of one
    # venture remove another venture's destination by guessing an id.
    def destroy
      payout_method = @event.fuime_payout_methods.live.find(params[:id])

      # AASM reverts the state and returns false on a failed save rather than
      # raising, so an unchecked call here would report a removal that did not
      # happen — and leave money pointed at an account somebody just tried to
      # disconnect.
      if payout_method.remove!
        redirect_to fuime_payout_method_path(event_slug: @event.slug),
                    notice: "#{payout_method.display_name} has been removed. " \
                            "Connect another account when you're ready to be paid."
      else
        redirect_to fuime_payout_method_path(event_slug: @event.slug),
                    alert: "We couldn't remove that account. Please try again."
      end
    end

    private

    def set_event
      @event = Event.find_by!(slug: params[:event_slug])
    end

    def authorize_connect
      authorize @event, :connect_payout_method?
    end

    # Sandbox Plaid while Stripe is live: connecting would mint a destination
    # that reads as verified and points at a fictional account, permanently
    # indistinguishable from a real one after PLAID_ENV is promoted.
    #
    # A refusal rather than a hidden button, because the nav is cosmetic and this
    # is the money path — a bookmarked URL, a stale tab or a direct POST must all
    # land here too.
    def refuse_uncollectable
      return if ::Fuime::PlaidLinkService.collectable?

      message = "Connecting a bank isn't available yet — payouts open later. " \
                "Nothing you've earned is affected."

      respond_to do |format|
        format.json { render json: { error: message }, status: :service_unavailable }
        format.any do
          redirect_to fuime_payout_method_path(event_slug: @event.slug), alert: message
        end
      end
    end

    def service
      @service ||= ::Fuime::PlaidLinkService.new(event: @event, user: current_user)
    end

    # What happens next depends on which model is live, and saying the wrong one
    # is a promise about money. Under MoR the destination is read by the weekly
    # run; under Connect it is preparation and nothing will be sent here.
    def next_step_sentence
      if ::Fuime::Features.merchant_of_record?
        "Payouts will be sent here."
      else
        "Payouts still go through this venture's Stripe account for now."
      end
    end

  end
end
