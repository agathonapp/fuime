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
