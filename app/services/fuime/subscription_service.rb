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

    # event: nil (the default) is the FAMILY subscription — the Pro plan,
    # billed to the guardian, covering all their ventures. Passing an event
    # bills that venture's own plan instead (the per-venture path).
    def initialize(guardian:, event: nil)
      @guardian = guardian
      @event = event
    end

    def record
      @event ? Fuime::Subscription.find_by(event: @event) : Fuime::Subscription.family.find_by(billed_to: @guardian)
    end

    # A Stripe Checkout session (mode: subscription) for the guardian to enter
    # their card. Returns the session; the caller redirects to session.url.
    def checkout_session(success_url:, cancel_url:)
      cents = (@event ? @event.plan&.monthly_fee_cents : Event::Plan::Pro.new.monthly_fee_cents).to_i
      raise NotBillable, "nothing to bill monthly here" unless cents.positive?

      sub = if @event
              Fuime::Subscription.find_or_create_by!(event: @event) { |s| s.billed_to = @guardian }
            else
              Fuime::Subscription.family.find_or_create_by!(billed_to: @guardian)
            end

      if sub.stripe_customer_id.blank?
        customer = Stripe::Customer.create(
          { email: @guardian.email, name: @guardian.name,
            metadata: { fuime_user_id: @guardian.id }
},
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
          subscription_data: { metadata: @event ? { fuime_event_id: @event.id } : { fuime_guardian_user_id: @guardian.id } },
          success_url:, cancel_url:
        },
        request_options
      )
    end

    # Stripe's hosted billing portal — card updates, invoices, cancellation.
    # Fuime never renders a card form of its own; the portal is the management
    # half of the same boundary Checkout is the acquisition half of.
    def portal_session(return_url:)
      sub = record
      raise NotBillable, "no billing relationship yet" if sub&.stripe_customer_id.blank?

      Stripe::BillingPortal::Session.create(
        { customer: sub.stripe_customer_id, return_url: },
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
