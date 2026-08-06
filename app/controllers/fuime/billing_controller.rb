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
      @pro_plan = Event::Plan::Pro.new
      @subscription = service.record
      @is_adult = adult?
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

    def adult?
      !current_user.minor_or_unknown_age?
    end

    def refuse_minor
      redirect_to my_billing_path,
                  alert: "The family plan is billed to a parent or guardian — ask them to upgrade from their account."
    end

  end
end
