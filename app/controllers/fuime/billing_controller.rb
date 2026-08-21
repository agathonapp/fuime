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
      @is_adult = adult?
      @is_staff = current_user.staff?
      # A teen's upgrade path is their guardian; name them.
      @guardians = current_user.guardians.to_a
    end

    def subscribe
      return refuse_minor unless adult?

      # Fuime: refuse a second subscription for the same family (2026-08-21).
      #
      # Nothing stopped a repeat POST here. The page hides the Upgrade button once
      # the plan is active, but the route was reachable — a double submit, a
      # bookmarked form, or a back-button re-post minted a SECOND Stripe
      # subscription against the same customer. The webhook then overwrote
      # `stripe_subscription_id` with the new one, so the first became invisible to
      # Fuime while continuing to charge the guardian's card every month, forever,
      # with no surface anywhere in the app that could see it.
      #
      # `#active?` covers the already-have-it case (paid active/trialing, and a
      # comp). `#stripe_backed?` is the rest of the hole: past_due / unpaid /
      # incomplete still have a live Stripe subscription, and opening Checkout
      # would mint a second one the same way. Those go to the billing portal.
      existing = service.record
      if existing&.active?
        redirect_to my_billing_path,
                    alert: existing.comped? ? "You already have the family plan, comped by Fuime — there's nothing to buy." : "You're already on the family plan."
        return
      end

      if existing&.stripe_backed?
        session = service.portal_session(return_url: my_billing_url)
        redirect_to session.url, allow_other_host: true
        return
      end

      session = service.checkout_session(
        success_url: my_billing_url(subscribed: 1),
        cancel_url: my_billing_url
      )
      redirect_to session.url, allow_other_host: true
    rescue Fuime::SubscriptionService::NotBillable => e
      redirect_to my_billing_path, alert: e.message
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

    def refuse_minor
      redirect_to my_billing_path,
                  alert: "The family plan is billed to a parent or guardian — ask them to upgrade from their account."
    end

  end
end
