# frozen_string_literal: true

# Fuime: the family plan page — the one place the subscription is visible and
# purchasable.
#
# Who may pay is an L2 question, not a UX one: a subscription is a contract,
# so the card must belong to an adult. A minor sees their family's status and
# who to ask; the subscribe and portal actions refuse them outright rather
# than hiding the buttons and hoping.
module Fuime
  class BillingController < ApplicationController
    skip_after_action :verify_authorized

    def show
      # The settings sidebar (users/_nav) is written against the Users
      # controllers and reads @user to decide whose settings it is showing.
      @user = current_user
      @pro_plan = Event::Plan::Pro.new
      @subscription = service.record
      # Back from Stripe Checkout, but the webhook that writes the record may not
      # have landed yet. See the branch this drives in the view: without it the
      # page offered Upgrade again and a second press charged the parent twice.
      @just_paid = params[:subscribed].present? && !@subscription&.active?
      @is_adult = adult?
      @is_staff = current_user.staff?
      # A teen's upgrade path is their guardian; name them.
      @guardians = current_user.guardians.to_a
      # An invited parent who has not signed yet is not known to be an adult —
      # `known_adult?` is only ever set by GuardianshipsController#accept — so
      # the page tells them the ordering instead of calling them a minor.
      @pending_guardian_invite = pending_guardian_invite?
    end

    # Fuime: RETIRED 2026-09-14. Fuime has one flat price and nothing to sell a
    # subscription for.
    #
    # The action is kept and refuses, rather than the route being removed: the
    # Upgrade button is gone from #show, but this path has always been reachable
    # by a bookmark, a back-button re-post or a double submit — which is the
    # exact hole the old duplicate-subscription guard was written for. A removed
    # route would 404 at a parent who bookmarked their billing page; this tells
    # them why instead.
    #
    # What was here: an adult check, a guard against minting a second Stripe
    # subscription for a family that already had one, and a Checkout session.
    # All of it only made sense while there was something to buy. Families who
    # are STILL being billed cancel through #portal, which is untouched and is
    # now the only Stripe writer on this controller.
    def subscribe
      refuse_retired_plan
    end

    def portal
      return refuse_minor unless adult?

      session = service.portal_session(return_url: my_billing_url)
      redirect_to session.url, allow_other_host: true
    rescue Fuime::SubscriptionService::NotBillable
      redirect_to my_billing_path, alert: "Nothing to manage yet — the family plan hasn't been started."
    end

    private

    def service
      Fuime::SubscriptionService.new(guardian: current_user)
    end

    # Staff are not teen founders (User#staff?). Without the exemption every
    # Fuime admin reads as a minor here — no staff account has a birthday on
    # file, and #minor_or_unknown_age? is fail-closed — so the console's own
    # operators were shown "ask your parent" on their own subscription and
    # could not buy, or even preview, the plan they sell.
    def adult?
      current_user.known_adult? || current_user.staff?
    end

    # Fuime: a parent who has been invited but has not accepted yet reads as a
    # minor here — `known_adult?` is set in exactly one place, the guardian
    # accept (GuardianshipsController#accept) — and was told to "ask a parent".
    # The ordering (accept, then upgrade) is correct; it just was never said
    # (ONBOARDING_PLAN §2 #11).
    def pending_guardian_invite?
      current_user.guardianships_as_guardian.pending.exists?
    end

    def refuse_retired_plan
      redirect_to my_billing_path,
                  alert: "Fuime is one flat price now — #{Event::Plan.fuime_price_label} and no " \
                         "monthly fee. Unlimited businesses and API keys are included, so there's " \
                         "nothing to subscribe to."
    end

    def refuse_minor
      if pending_guardian_invite?
        redirect_to my_billing_path,
                    alert: "You can upgrade once you've accepted a guardian invitation — that's what confirms you're the adult on the account."
      else
        redirect_to my_billing_path,
                    alert: "The family plan is billed to a parent or guardian — ask them to upgrade from their account."
      end
    end

  end
end
