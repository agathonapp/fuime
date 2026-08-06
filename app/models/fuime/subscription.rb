# frozen_string_literal: true

# == Schema Information
#
# Table name: fuime_subscriptions
#
#  id                     :bigint           not null, primary key
#  cancel_at_period_end   :boolean          default(FALSE), not null
#  current_period_end     :datetime
#  status                 :string           default("incomplete"), not null
#  created_at             :datetime         not null
#  updated_at             :datetime         not null
#  billed_to_id           :bigint           not null
#  event_id               :bigint
#  stripe_customer_id     :string
#  stripe_subscription_id :string
#
# Indexes
#
#  index_fuime_subscriptions_family_per_guardian        (billed_to_id) UNIQUE WHERE (event_id IS NULL)
#  index_fuime_subscriptions_on_billed_to_id            (billed_to_id)
#  index_fuime_subscriptions_on_event_id                (event_id) UNIQUE WHERE (event_id IS NOT NULL)
#  index_fuime_subscriptions_on_stripe_subscription_id  (stripe_subscription_id) UNIQUE WHERE (stripe_subscription_id IS NOT NULL)
#
# Foreign Keys
#
#  fk_rails_...  (billed_to_id => users.id)
#  fk_rails_...  (event_id => events.id)
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

    # No event = a FAMILY subscription: the guardian's Pro plan, covering
    # every venture they sign for.
    belongs_to :event, optional: true
    belongs_to :billed_to, class_name: "User"

    scope :family, -> { where(event_id: nil) }

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
