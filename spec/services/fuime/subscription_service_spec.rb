# frozen_string_literal: true

require "rails_helper"

# Fuime: the monthly software fee — the pricing model's second dial.
# Individuals: monthly fee (here) + 4% revenue fee (plans) + Stripe processing
# passed through itemised. Schools: invoice per contract, never card-on-file.
RSpec.describe Fuime::SubscriptionService do
  let(:guardian) { create(:user, birthday: 40.years.ago.to_date) }

  def stub_billing!(price_exists: false)
    allow(Stripe::Customer).to receive(:create)
      .and_return(Stripe::Customer.construct_from(id: "cus_test_1"))
    allow(Stripe::Price).to receive(:list)
      .and_return(Stripe::ListObject.construct_from(data: price_exists ? [{ id: "price_existing" }] : []))
    allow(Stripe::Price).to receive(:create)
      .and_return(Stripe::Price.construct_from(id: "price_new"))
    allow(Stripe::Checkout::Session).to receive(:create)
      .and_return(Stripe::Checkout::Session.construct_from(id: "cs_sub_1", url: "https://checkout.stripe.com/x"))
  end

  it "bills an individual venture: customer, price by lookup key, subscription session" do
    stub_billing!
    venture = create(:event, plan_type: Event::Plan::Standard)

    session = described_class.new(event: venture)
                             .checkout_session(guardian:, success_url: "https://x/s", cancel_url: "https://x/c")

    expect(session.id).to eq("cs_sub_1")
    sub = Fuime::Subscription.find_by(event: venture)
    expect(sub.billed_to).to eq(guardian)
    expect(sub.stripe_customer_id).to eq("cus_test_1")
    expect(Stripe::Checkout::Session).to have_received(:create).with(
      hash_including(mode: "subscription",
                     subscription_data: { metadata: { fuime_event_id: venture.id } }),
      anything
    )
  end

  it "refuses to bill a school venture — invoiced per contract, not card-on-file" do
    school = create(:event, plan_type: Event::Plan::School)
    venture = create(:event, name: "Sub School Venture", parent: school, plan_type: Event::Plan::School)

    expect {
      described_class.new(event: venture).checkout_session(guardian:, success_url: "s", cancel_url: "c")
    }.to raise_error(described_class::NotBillable)
  end

  describe Fuime::SubscriptionWebhookHandler do
    it "mirrors subscription state onto the record via metadata" do
      stub_billing!
      venture = create(:event, plan_type: Event::Plan::Standard)
      described_class.module_parent::SubscriptionService.new(event: venture)
                     .checkout_session(guardian:, success_url: "s", cancel_url: "c")

      event = Stripe::Event.construct_from(
        type: "customer.subscription.updated",
        data: { object: { id: "sub_test_1", status: "active", cancel_at_period_end: false,
                          current_period_end: 30.days.from_now.to_i,
                          metadata: { fuime_event_id: venture.id.to_s } } }
      )
      described_class.new(event:).handle

      sub = Fuime::Subscription.find_by(event: venture)
      expect(sub.status).to eq("active")
      expect(sub).to be_active
      expect(sub.stripe_subscription_id).to eq("sub_test_1")
    end

    it "logs and ignores an unknown subscription rather than raising" do
      event = Stripe::Event.construct_from(
        type: "customer.subscription.deleted",
        data: { object: { id: "sub_ghost", status: "canceled", cancel_at_period_end: false, metadata: {} } }
      )
      expect { described_class.new(event:).handle }.not_to raise_error
    end
  end

  describe "the pricing model, as encoded in plans" do
    it "individuals: monthly fee + 4% revenue fee" do
      plan = Event::Plan::Standard.new
      expect(plan.monthly_fee_cents).to be_positive
      expect(plan.revenue_fee).to eq(0.04)
    end

    it "schools: no card-billed monthly fee, no revenue fee" do
      plan = Event::Plan::School.new
      expect(plan.monthly_fee_cents).to eq(0)
      expect(plan.revenue_fee).to eq(0.0)
    end
  end
end
