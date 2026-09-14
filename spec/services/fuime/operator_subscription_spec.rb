# frozen_string_literal: true

require "rails_helper"

# Fuime: an operator can sell a monthly or yearly product.
#
# `MOR_RISK_ACCEPTANCE.md` §8 recorded the absence deliberately. What makes
# adding it delicate is that Fuime bills its OWN software plan through Stripe
# Billing on the SAME platform account, so two unrelated kinds of subscription
# now share one webhook stream. Most of this file is about keeping them apart.
RSpec.describe "Operator subscriptions", :merchant_of_record do
  let(:event) { create(:event, plan_type: Event::Plan::Standard, name: "Sunset Lawn") }

  describe Fuime::Offer do
    it "is one-time by default — nothing recurs unless the operator said so" do
      expect(build(:fuime_offer, event:).billing_interval).to be_nil
      expect(build(:fuime_offer, event:)).to be_one_time
    end

    it "accepts month and year" do
      %w[month year].each do |interval|
        expect(build(:fuime_offer, event:, billing_interval: interval)).to be_valid
      end
    end

    # Stripe supports these; Fuime deliberately does not. A teenager billing
    # weekly is a support burden, and the constraint is cheap to widen later and
    # impossible to narrow once somebody has sold one.
    it "refuses intervals Fuime does not sell" do
      %w[day week fortnight].each do |interval|
        expect(build(:fuime_offer, event:, billing_interval: interval)).not_to be_valid
      end
    end

    it "says the cadence the way a buyer reads it" do
      expect(build(:fuime_offer, event:, billing_interval: "month").price_cadence).to eq("per month")
      expect(build(:fuime_offer, event:, billing_interval: "year").price_cadence).to eq("per year")
      expect(build(:fuime_offer, event:).price_cadence).to be_nil
    end

    it "is enforced in the database, not only the model" do
      offer = create(:fuime_offer, event:)

      expect { offer.update_column(:billing_interval, "week") }
        .to raise_error(ActiveRecord::StatementInvalid)
    end
  end

  describe Fuime::PaymentLinkService do
    def session_args_for(offer)
      captured = nil
      allow(Stripe::Checkout::Session).to receive(:create) { |args, _opts| captured = args; double(url: "x") }
      allow(event).to receive(:selling_blockers).and_return([])

      described_class.new(
        event:, amount_cents: offer&.price_cents || 2_500,
        description: "Weekly mow", offer:
      ).create_mor_checkout_session(success_url: "https://x", cancel_url: "https://y")

      captured
    end

    it "sells a one-time offer as a payment, with no recurring block" do
      args = session_args_for(create(:fuime_offer, event:, price_cents: 2_500))

      expect(args[:mode]).to eq("payment")
      expect(args[:line_items].first[:price_data]).not_to have_key(:recurring)
      expect(args[:payment_intent_data]).to be_present
    end

    it "sells a recurring offer as a subscription on the stated interval" do
      args = session_args_for(create(:fuime_offer, event:, price_cents: 9_99, billing_interval: "month"))

      expect(args[:mode]).to eq("subscription")
      expect(args[:line_items].first[:price_data][:recurring]).to eq(interval: "month")
    end

    # Stripe rejects `recurring` inside mode: "payment", and rejects
    # `payment_intent_data` inside mode: "subscription". Getting either wrong is
    # a 400 at the moment a real buyer clicks pay.
    it "sends subscription metadata where a renewal can still read it" do
      args = session_args_for(create(:fuime_offer, event:, price_cents: 9_99, billing_interval: "month"))

      expect(args).not_to have_key(:payment_intent_data)
      expect(args[:subscription_data][:metadata][:fuime_event_id]).to eq(event.id)
    end

    # The whole reason the discriminator exists — see the handler spec below.
    it "stamps an operator's subscription as an operator sale" do
      args = session_args_for(create(:fuime_offer, event:, price_cents: 9_99, billing_interval: "month"))

      expect(args[:subscription_data][:metadata][:fuime_subscription_kind])
        .to eq(described_class::OPERATOR_SALE_KIND)
    end

    it "does not stamp a one-time sale, which is not a subscription at all" do
      args = session_args_for(create(:fuime_offer, event:, price_cents: 2_500))

      expect(args[:metadata]).not_to have_key(:fuime_subscription_kind)
    end
  end

  # ── The collision ────────────────────────────────────────────────────────
  #
  # Fuime::SubscriptionWebhookHandler mirrors the venture's OWN Fuime plan and
  # finds the row by `fuime_event_id`. An operator's customer subscription
  # carries that key too, because the ledger needs it to attribute the renewal.
  # Without the guard, a buyer cancelling a teenager's $9.99 tool would write
  # that buyer's `canceled` status onto the venture's Fuime plan row.
  describe Fuime::SubscriptionWebhookHandler do
    let!(:plan_row) do
      Fuime::Subscription.create!(
        event:, stripe_subscription_id: "sub_the_ventures_own_plan",
        status: "active", billed_to: create(:user)
      )
    end

    def deliver(metadata:, status: "canceled", id: "sub_a_customers_purchase")
      described_class.new(
        event: Stripe::Event.construct_from(
          type: "customer.subscription.updated",
          data: { object: { id:, object: "subscription", status:, metadata: } }
        )
      ).handle
    end

    it "ignores an operator's own sale instead of applying it to the venture's plan" do
      expect {
        deliver(metadata: {
                  fuime_event_id: event.id.to_s,
                  fuime_subscription_kind: Fuime::PaymentLinkService::OPERATOR_SALE_KIND
                })
      }.not_to(change { plan_row.reload.status })

      expect(plan_row.reload.status).to eq("active")
      expect(plan_row.reload.stripe_subscription_id).to eq("sub_the_ventures_own_plan")
    end

    it "still mirrors the venture's own Fuime plan, which carries no kind" do
      deliver(metadata: { fuime_event_id: event.id.to_s }, id: "sub_the_ventures_own_plan")

      expect(plan_row.reload.status).to eq("canceled")
    end
  end
end
