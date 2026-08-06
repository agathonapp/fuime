# frozen_string_literal: true

# Fuime: the guardian's flow for setting up payments on a venture.
#
# Four surfaces, one per thing that can happen:
#
#   #show     the status page — who needs to do what, readable by the whole team
#   #new      the embedded Stripe onboarding form, guardian only
#   #return   where Stripe sends the guardian when they exit the flow
#   #refresh  re-ask Stripe for the current state
#
# ── The authorization shape, which is the subtle part ─────────────────────────
#
# EventPolicy deliberately keeps a guardian read-only on the venture: `member?`
# and `manager?` both require an OrganizerPosition, which a guardian never has,
# and the comment on `guardian_reader?` says outright that "a guardian can see a
# venture and act on nothing in it."
#
# Completing Stripe onboarding is a write, performed by exactly that read-only
# party. It is allowed here because the thing being written is not the venture —
# it is the guardian's own Stripe account. The line Fuime draws is: the teen
# operates the business, the guardian owns the money rails. So `setup_payments?`
# authorises the guardian (and admins) and nobody else, including the teen, who
# cannot supply the identity details Stripe requires of an account owner.
module Fuime
  class PaymentSetupsController < ApplicationController
    # Fuime: gates whether a venture may be onboarded onto the CARDS profile.
    #
    # Off by default and deliberately not self-serve. A `:cards_enabled` account moves
    # `losses.payments` to `application`, which means FUIME ABSORBS EVERY NEGATIVE
    # BALANCE on that venture, collects the guardian's SSN, and pays Stripe's processing
    # fees. That is a capitalisation and compliance decision, not a preference a family
    # should be able to make from a form.
    #
    # It is also unresolved with Stripe: open question 3 in LEGAL_RESEARCH asks whether a
    # teen sole-prop with a guardian representative is a supported Issuing use case at
    # all. Until that is answered, offering cards broadly could create accounts Stripe
    # later rejects — and because `controller` is create-only, those families could not be
    # migrated back. They would have to re-onboard from scratch.
    #
    # So the flag exists to make the path REACHABLE and testable end to end, per venture,
    # without making it available.
    CARDS_FLAG = :fuime_cards_2026_08_04

    before_action :set_event
    # `:create` was in this list but no such action exists on this controller (the flow is
    # show / new / return / refresh, and routes.rb defines exactly those four). Rails
    # raises AbstractController::ActionNotFound for a callback naming a missing action
    # whenever `raise_on_missing_callback_actions` is on, which it is by default in
    # development and test — so every request to the payment-setup flow raised locally.
    # Production defaults that check off, which is why it went unnoticed: the bug was
    # invisible exactly where anyone would have hit it least.
    before_action :authorize_setup, only: [:new, :return, :refresh]

    # Status of payment setup for this venture. Deliberately readable by the team
    # as well as the guardian: a teen needs to know whether they can be paid and
    # whose action is outstanding, even though they cannot act on it themselves.
    def show
      authorize @event, :payment_setup_status?

      # The account this venture is actually paid into, which inside a school
      # programme belongs to the school. Showing only its OWN account told a student
      # at a fully onboarded school that setup had never been started.
      @connected_account = @event.payment_account
      @inherited_account = @event.shares_payment_account?
      @guardians = @event.overseeing_guardians

      # Nothing to set up on a venture that already inherits an account, and this is
      # a guard rather than a nicety: a guide with manager rights would otherwise be
      # invited to onboard a SECOND Stripe account per student, each carrying the
      # school's own entity details, when the school's existing account already
      # serves the whole tree.
      @can_set_up = policy(@event).setup_payments? && !@inherited_account

      # Whether this venture may still CHOOSE the cards profile. False once an account
      # exists, because `controller` is create-only at Stripe and the choice is therefore
      # already made and unchangeable — offering it again would promise something only a
      # full re-onboarding could deliver.
      @can_choose_cards = @connected_account.blank? && cards_available?
    end

    # The embedded onboarding form.
    #
    # Mints a fresh Account Session client secret on every render because they
    # are short-lived by design; there is nothing to cache and caching one would
    # produce an expired-session error for the guardian.
    def new
      # Refused server-side, not just hidden in #show, because this is a URL anyone
      # with manager rights can type. Creating an account here would give one student
      # a second Stripe account inside a programme whose money is meant to be in one
      # place — and Event#payment_account would then stop resolving to the school's,
      # silently splitting the programme's balance in two.
      if @event.shares_payment_account?
        redirect_to fuime_payment_setup_path(event_slug: @event.slug),
                    notice: "This venture is already set up through its school's payment account."
        return
      end

      @connected_account = service.mark_onboarding_started!

      # A `:cards_enabled` venture collects its requirements through Fuime, not through
      # Stripe's embedded component — `requirement_collection = application` inverts
      # whose job that is. Fuime::ConnectOnboardingService#account_session_client_secret
      # raises for this profile rather than serving a flow that would collect nothing, so
      # this redirect is what turns that refusal into a working path instead of a wall.
      if @connected_account.cards_profile?
        redirect_to fuime_requirement_collection_path(event_slug: @event.slug)
        return
      end

      @client_secret = service.account_session_client_secret
      @publishable_key = StripeService.publishable_key
    rescue Stripe::StripeError => e
      Rails.error.report(e, handled: true, context: { event_id: @event.id })
      redirect_to fuime_payment_setup_path(event_slug: @event.slug),
                  alert: "Stripe couldn't start payment setup just now. Please try again in a moment."
    end

    # Where the embedded component's `setOnExit` callback sends the guardian.
    #
    # Always re-asks Stripe rather than assuming success. Exiting the flow does
    # not mean all information was collected or that no requirements remain — only
    # that the flow was entered and exited. Treating the exit as completion is the
    # standard way to tell a family they can take payments when they cannot.
    def return
      account = service.refresh!

      notice =
        if account&.ready_for_payments?
          "Payment setup is complete. #{@event.name} can now accept payments."
        elsif account&.onboarding_submitted?
          "Thanks — Stripe is reviewing the details. We'll update this page when they're done."
        else
          "Payment setup isn't finished yet. You can pick up where you left off."
        end

      redirect_to fuime_payment_setup_path(event_slug: @event.slug), notice:
    rescue Stripe::StripeError => e
      Rails.error.report(e, handled: true, context: { event_id: @event.id })
      redirect_to fuime_payment_setup_path(event_slug: @event.slug),
                  alert: "We couldn't check the status with Stripe. Please refresh in a moment."
    end

    # Account Session client secrets expire. When one does while the guardian has
    # the page open, the right response is a new session, not an error — from their
    # point of view nothing has gone wrong.
    #
    # Serves both shapes because two callers need it: the embedded component's
    # `fetchClientSecret` asks for JSON mid-session, and a guardian who lands here
    # in a browser (a stale bookmark, a reload) should get the form back.
    def refresh
      respond_to do |format|
        format.json do
          render json: { client_secret: service.account_session_client_secret }
        end
        format.any do
          redirect_to new_fuime_payment_setup_path(event_slug: @event.slug)
        end
      end
    rescue Stripe::StripeError => e
      Rails.error.report(e, handled: true, context: { event_id: @event.id })
      respond_to do |format|
        format.json { render json: { error: "Could not start a Stripe session" }, status: :service_unavailable }
        format.any do
          redirect_to fuime_payment_setup_path(event_slug: @event.slug),
                      alert: "Stripe couldn't start payment setup just now. Please try again in a moment."
        end
      end
    end

    private

    def set_event
      # Matches Fuime::TaxesController — event-scoped Fuime routes address the
      # venture by slug.
      @event = Event.find_by!(slug: params[:event_slug])
    end

    def authorize_setup
      authorize @event, :setup_payments?
    end

    def service
      @service ||= Fuime::ConnectOnboardingService.new(
        event: @event, guardian: acting_guardian, profile: resolved_profile
      )
    end

    # Which account configuration this request is operating on.
    #
    # An existing account's profile is the ONLY valid answer for it: `controller` is
    # create-only, so the profile cannot be changed, and passing a different one would
    # make Fuime::ConnectOnboardingService raise. Reading it back also means a `?profile=`
    # in the URL cannot reinterpret an account that already exists.
    def resolved_profile
      existing = @event.stripe_connected_account&.controller_profile
      return existing if existing.present?

      requested_profile
    end

    # The profile being asked for on a venture that has no account yet.
    #
    # The flag is checked SERVER-SIDE here rather than only hidden in the view, because
    # `?profile=cards_enabled` is a URL anyone can type. Without this check that param
    # would let a family create an account on which Fuime carries every chargeback, which
    # is the one decision that must never be reachable by guessing a query string.
    def requested_profile
      return Fuime::ConnectOnboardingService::DEFAULT_PROFILE unless cards_available?

      if params[:profile].to_s == "cards_enabled"
        :cards_enabled
      else
        Fuime::ConnectOnboardingService::DEFAULT_PROFILE
      end
    end

    def cards_available?
      Flipper.enabled?(CARDS_FLAG, @event)
    end

    # Which adult is being recorded as the account owner.
    #
    # For a guardian setting up their own ward's venture that is simply them. An
    # admin acting in support must not be recorded as the owner of a family's
    # Stripe account, so they are resolved to the venture's actual overseeing
    # guardian, and the flow refuses rather than guessing if there isn't exactly
    # one — silently picking `.first` is how a second teen's parent ends up owning
    # someone else's business.
    def acting_guardian
      # Fuime: an institutionally sponsored venture has no guardian, by design —
      # the school is in loco parentis. Before this branch existed, every school
      # request fell through to the raise below with "(0 candidates)", which is
      # what took app.fuime.com/:slug/payments/setup down with a 400.
      #
      # The account owner is the manager performing the onboarding: they are the
      # person supplying the institution's own identity details to Stripe, and
      # EventPolicy#setup_payments? has already confirmed they are a manager of
      # this org or an ancestor of it. Nobody else reaches this line.
      return current_user if @event.institutionally_sponsored?

      return current_user if current_user.guardian_of_event?(@event)

      guardians = @event.overseeing_guardians.to_a

      if guardians.one?
        guardians.first
      else
        raise ActionController::BadRequest,
              "Cannot determine the responsible guardian for event #{@event.id} " \
              "(#{guardians.count} candidates); an admin must not be recorded as the account owner."
      end
    end

  end
end
