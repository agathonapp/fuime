# frozen_string_literal: true

require "rails_helper"

# Fuime: the pricing ladder.
#
#   Free   — 7% (HCB's own rate), no monthly. The D2C default; a kid starts
#            selling before any adult enters a card.
#   Pro    — $15/mo (env-tunable) billed to the GUARDIAN, covering every
#            venture they sign for, at 4%.
#   School — 0%, invoiced per contract; never card-on-file.
#
# The upgrade breakeven is worth stating where it can't be lost: 3 points of
# fee spread only beat $180/yr above ~$6,000 of annual sales, so Pro is sold
# on the software (unlimited businesses, cards when they land), not on fee
# arbitrage — the specs pin the mechanism, the PR carries the argument.
RSpec.describe Fuime::SubscriptionService do
  let(:guardian) { create(:user, birthday: 40.years.ago.to_date) }
  let(:teen) { create(:user, birthday: 15.years.ago.to_date, verified: true) }

  def stub_billing!
    allow(Stripe::Customer).to receive(:create)
      .and_return(Stripe::Customer.construct_from(id: "cus_test_1"))
    allow(Stripe::Price).to receive(:list)
      .and_return(Stripe::ListObject.construct_from(data: []))
    allow(Stripe::Price).to receive(:create)
      .and_return(Stripe::Price.construct_from(id: "price_new"))
    allow(Stripe::Checkout::Session).to receive(:create)
      .and_return(Stripe::Checkout::Session.construct_from(id: "cs_sub_1", url: "https://checkout.stripe.com/x"))
  end

  def family_venture
    create(:event, plan_type: Event::Plan::Free).tap do |venture|
      Guardianship.create!(guardian:, minor: teen, status: :active)
      OrganizerPositionInvite.create!(event: venture, user: teen, sender: teen, role: :manager)
    end
  end

  it "creates the guardian's FAMILY subscription: customer, Pro price, session" do
    stub_billing!

    session = described_class.new(guardian:)
                             .checkout_session(success_url: "https://x/s", cancel_url: "https://x/c")

    expect(session.id).to eq("cs_sub_1")
    sub = Fuime::Subscription.family.find_by(billed_to: guardian)
    expect(sub).to be_present
    expect(sub.event).to be_nil
    expect(Stripe::Checkout::Session).to have_received(:create).with(
      hash_including(mode: "subscription",
                     subscription_data: { metadata: { fuime_guardian_user_id: guardian.id } }),
      anything
    )
  end

  it "walks the ladder: Free 7% by default, Pro 4% family-wide once the guardian subscribes, back on lapse" do
    stub_billing!
    venture = family_venture

    expect(venture.billing_plan).to be_a(Event::Plan::Free)
    expect(venture.revenue_fee).to eq(0.07)

    described_class.new(guardian:).checkout_session(success_url: "s", cancel_url: "c")
    Fuime::Subscription.family.find_by(billed_to: guardian).update!(status: "active")

    upgraded = Event.find(venture.id) # fresh instance: resolution is memoised per object
    expect(upgraded.billing_plan).to be_a(Event::Plan::Pro)
    expect(upgraded.revenue_fee).to eq(0.04)

    Fuime::Subscription.family.find_by(billed_to: guardian).update!(status: "past_due")
    lapsed = Event.find(venture.id)
    expect(lapsed.revenue_fee).to eq(0.07)
  end

  it "a school venture stays 0% regardless of any guardian's subscription" do
    school = create(:event, plan_type: Event::Plan::School)
    venture = create(:event, name: "Ladder School Venture", parent: school)

    expect(venture.revenue_fee).to eq(0.0)
  end

  it "new root ventures default to the Free plan" do
    expect(Event.create!(name: "Fresh Default", slug: "fresh-default-ladder").plan)
      .to be_a(Event::Plan::Free)
  end

  describe Fuime::SubscriptionWebhookHandler do
    it "resolves a family subscription by guardian metadata and mirrors state" do
      stub_billing!
      described_class.module_parent::SubscriptionService.new(guardian:)
                     .checkout_session(success_url: "s", cancel_url: "c")

      event = Stripe::Event.construct_from(
        type: "customer.subscription.created",
        data: { object: { id: "sub_fam_1", status: "active", cancel_at_period_end: false,
                          current_period_end: 30.days.from_now.to_i,
                          metadata: { fuime_guardian_user_id: guardian.id.to_s } } }
      )
      described_class.new(event:).handle

      sub = Fuime::Subscription.family.find_by(billed_to: guardian)
      expect(sub.status).to eq("active")
      expect(guardian.reload.fuime_pro?).to be true
    end

    it "logs and ignores an unknown subscription rather than raising" do
      event = Stripe::Event.construct_from(
        type: "customer.subscription.deleted",
        data: { object: { id: "sub_ghost", status: "canceled", cancel_at_period_end: false, metadata: {} } }
      )
      expect { described_class.new(event:).handle }.not_to raise_error
    end
  end
end
