# frozen_string_literal: true

# Fuime: Generate Stripe Checkout payment links for businesses
# Uses the platform's pooled Stripe account with event_id in metadata
# for ledger allocation
module Fuime
  class PaymentLinkService
    FUIME_PLATFORM_FEE_PERCENT = 4 # 4% platform fee

    def initialize(event:, amount_cents:, description:)
      @event = event
      @amount_cents = amount_cents
      @description = description
    end

    def create_checkout_session(success_url:, cancel_url:)
      # Calculate platform fee
      fee_cents = (@amount_cents * FUIME_PLATFORM_FEE_PERCENT / 100.0).round

      Stripe::Checkout::Session.create(
        {
          mode: "payment",
          line_items: [
            {
              price_data: {
                currency: "usd",
                product_data: {
                  name: @description,
                  description: "Payment to #{@event.name} via Fuime",
                },
                unit_amount: @amount_cents,
              },
              quantity: 1,
            },
          ],
          # Store event_id for ledger allocation
          metadata: {
            fuime_event_id: @event.id,
            fuime_event_name: @event.name,
            fuime_fee_cents: fee_cents,
          },
          payment_intent_data: {
            metadata: {
              fuime_event_id: @event.id,
              fuime_event_name: @event.name,
              fuime_fee_cents: fee_cents,
            },
            statement_descriptor_suffix: statement_descriptor,
          },
          success_url: success_url,
          cancel_url: cancel_url,
        },
        { api_key: StripeService.secret_key }
      )
    end

    # Generate a reusable payment link
    def create_payment_link
      # First create a product
      product = Stripe::Product.create(
        {
          name: "Payment to #{@event.name}",
          description: @description,
          metadata: {
            fuime_event_id: @event.id,
          },
        },
        { api_key: StripeService.secret_key }
      )

      # Create a price
      price = Stripe::Price.create(
        {
          product: product.id,
          unit_amount: @amount_cents,
          currency: "usd",
        },
        { api_key: StripeService.secret_key }
      )

      # Create the payment link
      Stripe::PaymentLink.create(
        {
          line_items: [{ price: price.id, quantity: 1 }],
          metadata: {
            fuime_event_id: @event.id,
            fuime_event_name: @event.name,
          },
          payment_intent_data: {
            metadata: {
              fuime_event_id: @event.id,
              fuime_event_name: @event.name,
            },
            statement_descriptor_suffix: statement_descriptor,
          },
        },
        { api_key: StripeService.secret_key }
      )
    end

    private

    def statement_descriptor
      # Max 22 chars for statement descriptor
      "FUIME #{@event.short_name || @event.name}"[0..21].strip
    end
  end
end
