# frozen_string_literal: true

require "rails_helper"

# Fuime: comping the family plan, and the line between a gift and a mirror.
#
# The invariant every example here defends: `Fuime::Subscription` mirrors Stripe,
# so the ONLY row an admin may write directly is one Stripe is not billing. A
# comped plan has no Stripe side to disagree with; a paid one does, and an admin
# writing to it would leave the console saying "active" while the card is failing.
RSpec.describe Fuime::Subscription do
  let(:admin) { create(:user, :make_admin, full_name: "Ada Admin") }
  let(:guardian) { create(:user, birthday: 40.years.ago.to_date) }

  describe ".grant_family_plan!" do
    it "creates an active family subscription with no Stripe side, and records who" do
      record = described_class.grant_family_plan!(user: guardian, by: admin, notes: "Founders Weekend")

      expect(record).to be_active
      expect(record).to be_comped
      expect(record.event_id).to be_nil
      expect(record.stripe_subscription_id).to be_nil
      expect(record.stripe_customer_id).to be_nil
      expect(record.granted_by).to eq(admin)
      expect(record.granted_at).to be_present
      expect(record.grant_notes).to include("Ada Admin", "Founders Weekend")
    end

    it "turns on everything the plan actually sells" do
      venture = create(:event, plan_type: Event::Plan::Free)
      teen = create(:user, birthday: 15.years.ago.to_date, verified: true)
      Guardianship.create!(guardian:, minor: teen, status: :active)
      create(:organizer_position, event: venture, user: teen, role: :manager)

      expect(guardian.fuime_pro?).to be false
      expect(venture.reload.billing_plan).to be_a(Event::Plan::Free)

      described_class.grant_family_plan!(user: guardian, by: admin)

      # Fresh objects: both predicates memoize per instance.
      expect(User.find(guardian.id).fuime_pro?).to be true
      expect(Event.find(venture.id).billing_plan).to be_a(Event::Plan::Pro)
      expect(User.find(teen.id).venture_slot_available?).to be true
    end

    it "re-comps a previously revoked grant rather than duplicating the row" do
      first = described_class.grant_family_plan!(user: guardian, by: admin, notes: "trial")
      first.revoke_grant!(by: admin, notes: "trial over")

      second = described_class.grant_family_plan!(user: guardian, by: admin, notes: "second look")

      expect(second.id).to eq(first.id)
      expect(second).to be_active
      # The history accumulates — the reason for the first grant is the context
      # for the second.
      expect(second.grant_notes).to include("trial", "trial over", "second look")
      expect(described_class.family.where(billed_to: guardian).count).to eq(1)
    end

    it "REFUSES to touch a subscription Stripe is billing" do
      described_class.create!(billed_to: guardian, status: "past_due",
                              stripe_customer_id: "cus_x", stripe_subscription_id: "sub_x")

      expect {
        described_class.grant_family_plan!(user: guardian, by: admin)
      }.to raise_error(described_class::StripeBacked, /Cancel or change it in Stripe/)

      expect(described_class.family.find_by(billed_to: guardian).status).to eq("past_due")
    end
  end

  describe "#revoke_grant!" do
    it "cancels a comp and takes the plan away" do
      record = described_class.grant_family_plan!(user: guardian, by: admin)
      record.revoke_grant!(by: admin, notes: "no longer a partner")

      expect(record.status).to eq("canceled")
      expect(record).not_to be_active
      expect(User.find(guardian.id).fuime_pro?).to be false
      expect(record.grant_notes).to include("revoked", "no longer a partner")
    end

    it "refuses on a Stripe-backed subscription" do
      record = described_class.create!(billed_to: guardian, status: "active",
                                       stripe_customer_id: "cus_y", stripe_subscription_id: "sub_y")

      expect { record.revoke_grant!(by: admin) }
        .to raise_error(described_class::NotComped, /cancel it there/)
      expect(record.reload.status).to eq("active")
    end
  end

  describe "#cancel_in_stripe!" do
    it "cancels at Stripe and leaves the status to the webhook" do
      record = described_class.create!(billed_to: guardian, status: "active",
                                       stripe_customer_id: "cus_z", stripe_subscription_id: "sub_z")

      expect(Stripe::Subscription).to receive(:cancel)
        .with("sub_z", {}, hash_including(:api_key))
        .and_return(Stripe::Subscription.construct_from(id: "sub_z", status: "canceled"))

      record.cancel_in_stripe!

      # Deliberately unchanged locally: Stripe is the authority and
      # customer.subscription.deleted is what writes this column.
      expect(record.reload.status).to eq("active")
    end

    it "refuses when there is nothing at Stripe to cancel" do
      record = described_class.grant_family_plan!(user: guardian, by: admin)

      expect { record.cancel_in_stripe! }
        .to raise_error(described_class::NotStripeBacked, /no Stripe subscription/)
    end
  end

  describe "#comped?" do
    it "stops being a comp the moment Stripe starts billing it" do
      record = described_class.grant_family_plan!(user: guardian, by: admin)
      expect(record).to be_comped

      record.sync_from_stripe!(
        Stripe::Subscription.construct_from(id: "sub_paid", status: "active", cancel_at_period_end: false)
      )

      expect(record.reload).not_to be_comped
      expect(record).to be_stripe_backed
    end
  end

  describe "scopes" do
    it "puts a stalled checkout in needs_attention, because the family thinks they paid" do
      stalled = described_class.create!(billed_to: guardian, status: "incomplete", stripe_customer_id: "cus_s")
      failing = described_class.create!(billed_to: create(:user), status: "past_due", stripe_customer_id: "cus_f")
      comped  = described_class.grant_family_plan!(user: create(:user), by: admin)

      expect(described_class.needs_attention).to contain_exactly(stalled, failing)
      expect(described_class.comped).to contain_exactly(comped)
    end
  end
end
