# frozen_string_literal: true

# == Schema Information — run annotate after migrating.
#
# Fuime: the software subscription for one venture (the monthly fee), mirrored
# from Stripe Billing. One row per venture; the payer is the responsible adult
# (billed_to), never the minor — L2 applies to the SaaS fee exactly as it does
# to everything else, because a subscription is a contract.
#
# `status` mirrors Stripe's subscription status verbatim (incomplete, trialing,
# active, past_due, canceled, unpaid). Nothing gates on it yet — deliberately.
# What non-payment locks is a product decision with one hard floor already
# decided: access to a venture's OWN money (payouts, the ledger) must never be
# held hostage to a lapsed software fee. Gate creation of new charges, cards,
# or storefronts — not custody.
module Fuime
  class Subscription < ApplicationRecord
    self.table_name = "fuime_subscriptions"

    belongs_to :event
    belongs_to :billed_to, class_name: "User"

    ACTIVE_STATUSES = %w[active trialing].freeze

    def active?
      ACTIVE_STATUSES.include?(status)
    end

    def sync_from_stripe!(subscription)
      update!(
        stripe_subscription_id: subscription.id,
        status: subscription.status,
        cancel_at_period_end: !!subscription.cancel_at_period_end,
        current_period_end: subscription.try(:current_period_end).present? ? Time.at(subscription.current_period_end) : nil
      )
    end
  end
end
