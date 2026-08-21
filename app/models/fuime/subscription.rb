# frozen_string_literal: true

# == Schema Information
#
# Table name: fuime_subscriptions
#
#  id                     :bigint           not null, primary key
#  cancel_at_period_end   :boolean          default(FALSE), not null
#  current_period_end     :datetime
#  grant_notes            :text
#  granted_at             :datetime
#  status                 :string           default("incomplete"), not null
#  created_at             :datetime         not null
#  updated_at             :datetime         not null
#  billed_to_id           :bigint           not null
#  event_id               :bigint
#  granted_by_id          :bigint
#  stripe_customer_id     :string
#  stripe_subscription_id :string
#
# Indexes
#
#  index_fuime_subscriptions_family_per_guardian        (billed_to_id) UNIQUE WHERE (event_id IS NULL)
#  index_fuime_subscriptions_on_billed_to_id            (billed_to_id)
#  index_fuime_subscriptions_on_event_id                (event_id) UNIQUE WHERE (event_id IS NOT NULL)
#  index_fuime_subscriptions_on_granted_by_id           (granted_by_id)
#  index_fuime_subscriptions_on_stripe_subscription_id  (stripe_subscription_id) UNIQUE WHERE (stripe_subscription_id IS NOT NULL)
#
# Foreign Keys
#
#  fk_rails_...  (billed_to_id => users.id)
#  fk_rails_...  (event_id => events.id)
#  fk_rails_...  (granted_by_id => users.id)
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
    # Raised when an admin action would write to a row Stripe is billing.
    class StripeBacked < StandardError; end
    # Raised when a comp-only action is attempted on a paid subscription.
    class NotComped < StandardError; end
    # Raised when a Stripe-only action is attempted on a comp.
    class NotStripeBacked < StandardError; end

    self.table_name = "fuime_subscriptions"

    # Fuime: this row decides what a family is charged, so a change to it has to
    # be attributable — including the ones that arrive from a webhook.
    has_paper_trail

    # No event = a FAMILY subscription: the guardian's Pro plan, covering
    # every venture they sign for.
    belongs_to :event, optional: true
    belongs_to :billed_to, class_name: "User"
    # Present only on a comped subscription — see #comped?.
    belongs_to :granted_by, class_name: "User", optional: true

    scope :family, -> { where(event_id: nil) }
    scope :comped, -> { where.not(granted_by_id: nil).where(stripe_subscription_id: nil) }

    ACTIVE_STATUSES = %w[active trialing].freeze

    # Statuses that mean somebody has to do something. `incomplete` is in here
    # deliberately: it is the status of a Checkout session that was opened and
    # never paid, and a family sitting in it thinks they bought the plan.
    ATTENTION_STATUSES = %w[past_due unpaid incomplete].freeze

    scope :needs_attention, -> { where(status: ATTENTION_STATUSES) }

    def active?
      ACTIVE_STATUSES.include?(status)
    end

    def needs_attention?
      ATTENTION_STATUSES.include?(status)
    end

    # Fuime: is this plan a gift from Fuime rather than a paid subscription?
    #
    # The distinction governs every admin action on this model. A row Stripe is
    # actually billing must never be edited locally — the model is a mirror, and a
    # mirror that disagrees with the account being charged is worse than no mirror
    # (ADMIN_OPS_QUEUES.md §4). A comp has no Stripe side to disagree with, so it
    # is the one thing an admin may write directly.
    #
    # Both halves of the test matter. `granted_by_id` present says a human decided
    # this; `stripe_subscription_id` blank says Stripe is not billing it. A comp
    # that the family later pays for (they buy the plan themselves) picks up a
    # subscription id through the webhook and stops being comped from that moment,
    # which is the correct answer for every caller.
    def comped?
      granted_by_id.present? && stripe_subscription_id.blank?
    end

    def stripe_backed?
      stripe_subscription_id.present?
    end

    # Fuime: comp the family plan to a user, or re-comp a lapsed one.
    #
    # Refuses outright on a Stripe-backed row rather than quietly flipping the
    # status: the family is being charged, the webhook would overwrite whatever we
    # wrote at the next event anyway, and "the admin page says active while Stripe
    # says past_due" is precisely the failure this model is shaped to avoid.
    def self.grant_family_plan!(user:, by:, notes: nil)
      record = family.find_or_initialize_by(billed_to: user)

      if record.stripe_backed?
        raise StripeBacked, "#{user.email} has a real Stripe subscription (#{record.stripe_subscription_id}). " \
                            "Cancel or change it in Stripe, not here."
      end

      record.status = "active"
      record.granted_by = by
      record.granted_at = Time.current
      record.grant_notes = record.stamp_note(notes, by:)
      record.save!
      record
    end

    # Ends a comp. Status rather than deletion, so the grant stays readable —
    # who gave it, when, and now who took it away.
    def revoke_grant!(by:, notes: nil)
      raise NotComped, "this subscription is billed by Stripe; cancel it there" unless comped?

      update!(status: "canceled", grant_notes: stamp_note(notes, by:, verb: "revoked"))
    end

    # Cancels the real subscription AT STRIPE and lets the webhook mirror it back.
    #
    # Deliberately does not write `status` itself. Stripe is the authority for a
    # paid subscription; `customer.subscription.deleted` arrives seconds later and
    # `#sync_from_stripe!` records it. Writing both would make this the second
    # writer of a mirrored column, which is the thing #comped? exists to prevent.
    def cancel_in_stripe!
      raise NotStripeBacked, "there is no Stripe subscription to cancel" unless stripe_backed?

      Stripe::Subscription.cancel(stripe_subscription_id, {}, { api_key: StripeService.secret_key })
    end

    # Notes accumulate rather than overwrite, same as Event#record_vetting_decision!:
    # the reason a plan was comped in August is the context for revoking it in
    # November.
    def stamp_note(notes, by:, verb: "granted")
      line = "#{Time.current.to_fs(:long)} — #{by&.name || 'system'} #{verb}#{": #{notes.strip}" if notes.present?}"
      [line, grant_notes.presence].compact.join("\n\n")
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
