# frozen_string_literal: true

# Fuime: the monthly software fee, collected through Stripe Billing on the
# PLATFORM account (this is Fuime's own revenue — the one flow where money is
# supposed to come to us, unlike everything under Connect).
#
# The payer is the responsible adult. A subscription is a contract, so the
# card on file belongs to the guardian (L2) — the same person who owns the
# venture's connected account.
#
# Price objects are resolved by lookup_key ("fuime_monthly_<cents>") so a price
# change in the plan creates a NEW Stripe price instead of mutating the old one
# — existing subscribers keep the price they signed up at until deliberately
# migrated, which is how subscription pricing is supposed to behave.
module Fuime
  class SubscriptionService
    class NotBillable < StandardError; end

    def initialize(event:)
      @event = event
    end

    def record
      Fuime::Subscription.find_by(event: @event)
    end

    # A Stripe Checkout session (mode: subscription) for the guardian to enter
    # their card. Returns the session; the caller redirects to session.url.
    def checkout_session(guardian:, success_url:, cancel_url:)
      cents = @event.plan&.monthly_fee_cents.to_i
      raise NotBillable, "#{@event.name}'s plan has no monthly fee" unless cents.positive?

      sub = Fuime::Subscription.find_or_create_by!(event: @event) do |s|
        s.billed_to = guardian
      end

      if sub.stripe_customer_id.blank?
        customer = Stripe::Customer.create(
          { email: guardian.email, name: guardian.name,
            metadata: { fuime_user_id: guardian.id } },
          request_options
        )
        sub.update!(stripe_customer_id: customer.id)
      end

      Stripe::Checkout::Session.create(
        {
          mode: "subscription",
          customer: sub.stripe_customer_id,
          line_items: [{ price: price_id(cents), quantity: 1 }],
          # The join back: the webhook handler maps subscription events to the
          # venture through this metadata, on the SUBSCRIPTION object itself so
          # every later event carries it.
          subscription_data: { metadata: { fuime_event_id: @event.id } },
          success_url:, cancel_url:
        },
        request_options
      )
    end

    private

    def price_id(cents)
      lookup_key = "fuime_monthly_#{cents}"
      existing = Stripe::Price.list({ lookup_keys: [lookup_key], limit: 1 }, request_options).data.first
      return existing.id if existing

      Stripe::Price.create(
        {
          unit_amount: cents, currency: "usd",
          recurring: { interval: "month" },
          lookup_key:,
          product_data: { name: "Fuime membership" }
        },
        request_options
      ).id
    end

    # Platform account, platform key — never a stripe_account header here.
    def request_options
      { api_key: StripeService.secret_key }
    end

  end
end
