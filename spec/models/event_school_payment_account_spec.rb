# frozen_string_literal: true

require "rails_helper"

# Fuime: can a student inside a school programme make money, and on whose terms.
#
# Two bugs are pinned here, and both were silent.
#
# The first: `Event::Plan::School` states outright that "the school owns the account
# and the money", but nothing implemented it. `stripe_connected_account` is
# per-event with a UNIQUE index and no fallback, so a student sub org under a fully
# onboarded school resolved no account, `accepts_payments?` was false, the storefront
# still rendered a payment form, and the checkout endpoint then refused it. A school
# could onboard perfectly and every student took exactly $0.
#
# The second: the fee. School inherits FeeWaived (0%) because a school already pays
# per student per year and taking a cut of each student's revenue would charge one
# customer twice — but `revenue_fee` read the venture's OWN plan, and
# `EventService::Create` defaults every new sub org to Standard (4%). So the
# double-charge the plan exists to prevent is exactly what happened.
RSpec.describe "a school programme's money in", type: :model do
  describe "Event#payment_account" do
    it "is the venture's own account for an ordinary venture" do
      venture = create(:event)
      account = create(:stripe_connected_account, :ready, event: venture)

      expect(venture.payment_account).to eq(account)
      expect(venture.shares_payment_account?).to be false
    end

    it "is nil for an ordinary venture that hasn't onboarded" do
      expect(create(:event).payment_account).to be_nil
    end

    # THE fix. Without this a school's students cannot be paid at all.
    it "resolves to the school's account for a student sub org" do
      school, _cohort, venture = build_school_tree
      account = create(:stripe_connected_account, :ready, event: school)

      expect(venture.payment_account).to eq(account)
      expect(venture.shares_payment_account?).to be true
      expect(venture.accepts_payments?).to be true
    end

    # Walks, rather than reading the immediate parent — which is why the fixture is
    # three levels deep.
    it "reaches an account two levels up" do
      school, cohort, venture = build_school_tree
      account = create(:stripe_connected_account, :ready, event: school)

      expect(cohort.payment_account).to eq(account)
      expect(venture.payment_account).to eq(account)
    end

    # Nearest, not root: a school network can put the account on one campus.
    it "prefers the nearest ancestor holding an account" do
      school, cohort, venture = build_school_tree
      create(:stripe_connected_account, :ready, event: school)
      campus_account = create(:stripe_connected_account, :ready, event: cohort)

      expect(venture.payment_account).to eq(campus_account)
    end

    # A venture that owns one never borrows one, so a student venture that has been
    # onboarded separately keeps its own money.
    it "prefers the venture's own account over the school's" do
      school, _cohort, venture = build_school_tree
      create(:stripe_connected_account, :ready, event: school)
      own = create(:stripe_connected_account, :ready, event: venture)

      expect(venture.payment_account).to eq(own)
      expect(venture.shares_payment_account?).to be false
    end

    # The guard that keeps this Fuime-only. Upstream HCB has sub-organizations that
    # are ordinary orgs under a parent; if inheritance were unconditional, their
    # money would silently start routing into the parent's Stripe account.
    it "does not inherit across an ordinary parent/child pair" do
      parent = create(:event)
      child = create(:event, parent:)
      create(:stripe_connected_account, :ready, event: parent)

      expect(child.payment_account).to be_nil
      expect(child.accepts_payments?).to be false
      expect(child.shares_payment_account?).to be false
    end

    it "is nil when nothing in the school tree has onboarded" do
      _school, _cohort, venture = build_school_tree

      expect(venture.payment_account).to be_nil
      expect(venture.accepts_payments?).to be false
      # Not "shared" — there is nothing to share. PayoutRequest relies on this
      # distinction to avoid claiming a destination is unavailable when the real
      # problem is that setup never happened.
      expect(venture.shares_payment_account?).to be false
    end
  end

  describe "Event#revenue_fee" do
    it "is the venture's own plan rate for an ordinary venture" do
      venture = create(:event, plan_type: Event::Plan::Standard)

      expect(venture.revenue_fee).to eq(Event::Plan::Standard.new.revenue_fee)
      expect(venture.revenue_fee).to be > 0
    end

    # The double-charge. A student venture is created on Standard's 4% (that is what
    # EventService::Create gives a sub org) while the school it belongs to is
    # fee-waived, and the school is already paying per student per year.
    it "is the school's waived rate for a student sub org on the Standard plan" do
      _school, _cohort, venture = build_school_tree

      expect(venture.plan).to be_a(Event::Plan::Standard)
      expect(venture.billing_plan).to be_a(Event::Plan::School)
      expect(venture.revenue_fee).to eq(0.00)
    end

    it "is waived for the school itself" do
      school, _cohort, _venture = build_school_tree

      expect(school.revenue_fee).to eq(0.00)
    end

    it "leaves an ordinary sub-organization billing on its own plan" do
      parent = create(:event, plan_type: Event::Plan::Standard)
      child = create(:event, parent:, plan_type: Event::Plan::Standard)

      expect(child.billing_plan).to eq(child.plan)
      expect(child.revenue_fee).to eq(Event::Plan::Standard.new.revenue_fee)
    end

    # `billing_plan` walks ancestors, which needs an id. `revenue_fee` is reachable
    # during validation on a new record, so it must not raise there.
    it "does not blow up on an unsaved event" do
      expect { Event.new(name: "Unsaved").revenue_fee }.not_to raise_error
    end
  end
end
