# frozen_string_literal: true

require "rails_helper"

# Fuime: money arriving into a school's Stripe balance, and the ledger agreeing.
#
# The load-bearing examples here are about WHEN the credit posts. A top-up is an ACH
# pull that takes days, and Fuime::SchoolAwardService spends against the balance it
# produces — so crediting at `topup.created` would let a school award money still in
# transit, which Fuime::PayoutService would then let a student withdraw out of other
# students' revenue. Nothing posts until Stripe says the money landed.
#
# The other half is that this works for top-ups Fuime never created. A business office
# can add funds from the Stripe Dashboard, and since it is unverified whether a
# Stripe-liability connected account may create top-ups through the API at all, that
# may be the ONLY path that works. The recorder is the feature; the button is not.
RSpec.describe Fuime::ConnectFundingRecorder do
  let(:school) { create(:event, plan_type: Event::Plan::School) }
  let!(:account) { create(:stripe_connected_account, :ready, event: school) }

  def stripe_event(type, object, account_id: account.stripe_id)
    Stripe::Event.construct_from(type:, account: account_id, data: { object: })
  end

  def handle(type, object, account_id: account.stripe_id)
    described_class.new(event: stripe_event(type, object, account_id:)).handle
  end

  def topup(id: "tu_1", amount: 50_000, **extra)
    {
      id:,
      object: "topup",
      amount:,
      currency: "usd",
      created: Time.current.to_i,
      **extra,
    }
  end

  def settled_lines
    CanonicalEventMapping.where(event_id: school.id).map(&:canonical_transaction)
  end

  def balance_cents
    school.balance_v2_cents
  end

  describe "topup.created" do
    it "records the top-up as pending" do
      handle("topup.created", topup)

      funding = SchoolFunding.find_by(stripe_topup_id: "tu_1")
      expect(funding).to be_present
      expect(funding).to be_pending
      expect(funding.amount_cents).to eq(50_000)
    end

    # The whole reason the credit waits. See the class comment.
    it "posts nothing to the ledger, because the money has not landed" do
      handle("topup.created", topup)

      expect(settled_lines).to be_empty
      expect(balance_cents).to eq(0)
    end
  end

  describe "topup.succeeded" do
    it "credits the school's ledger so awards can be granted against it" do
      handle("topup.succeeded", topup)

      expect(settled_lines.map(&:amount_cents)).to contain_exactly(50_000)
      expect(balance_cents).to eq(50_000)
    end

    it "marks the funding succeeded with the evidence the DB constraint requires" do
      handle("topup.succeeded", topup)

      funding = SchoolFunding.find_by(stripe_topup_id: "tu_1")
      expect(funding).to be_succeeded
      expect(funding.succeeded_at).to be_present
    end

    # The memo is pinned by Fuime::TaxTrackerService. A school moving its own money
    # between its own accounts has earned nothing.
    it "labels the line so the tax tracker excludes it from income" do
      handle("topup.succeeded", topup)

      expect(settled_lines.first.memo).to include("Funds added")
      expect(Fuime::TaxTrackerService::EXCLUDED_MEMO_PATTERNS).to include("funds added")
    end

    it "is idempotent — a redelivered event does not double the balance" do
      handle("topup.succeeded", topup)
      handle("topup.succeeded", topup)

      expect(balance_cents).to eq(50_000)
      expect(SchoolFunding.where(stripe_topup_id: "tu_1").count).to eq(1)
    end

    # Stripe does not guarantee webhook ordering.
    it "does not walk a landed top-up back to pending when created arrives late" do
      handle("topup.succeeded", topup)
      handle("topup.created", topup)

      expect(SchoolFunding.find_by(stripe_topup_id: "tu_1")).to be_succeeded
      expect(balance_cents).to eq(50_000)
    end

    # The case that makes this the feature rather than the button.
    it "works for a top-up Fuime never created, with no local row beforehand" do
      expect(SchoolFunding.count).to eq(0)

      handle("topup.succeeded", topup(id: "tu_dashboard"))

      funding = SchoolFunding.find_by(stripe_topup_id: "tu_dashboard")
      expect(funding).to be_present
      expect(funding.requested_by).to be_nil
      expect(balance_cents).to eq(50_000)
    end
  end

  describe "topup.failed and topup.canceled" do
    it "records the failure reason without touching the ledger" do
      handle("topup.failed", topup(failure_code: "debit_not_authorized",
                                   failure_message: "The bank declined the debit."))

      funding = SchoolFunding.find_by(stripe_topup_id: "tu_1")
      expect(funding).to be_failed
      expect(funding.failure_code).to eq("debit_not_authorized")
      expect(funding.failure_message).to eq("The bank declined the debit.")
      expect(balance_cents).to eq(0)
    end

    it "supplies a message when Stripe gives none, so support is not left guessing" do
      handle("topup.canceled", topup)

      funding = SchoolFunding.find_by(stripe_topup_id: "tu_1")
      expect(funding).to be_canceled
      expect(funding.failure_message).to be_present
    end
  end

  describe "topup.reversed" do
    it "debits the balance back out when a cleared top-up is returned" do
      handle("topup.succeeded", topup)
      expect(balance_cents).to eq(50_000)

      handle("topup.reversed", topup)

      expect(balance_cents).to eq(0)
    end

    # Reversing a line that was never written would invent a debit — the mirror of
    # the rule Fuime::ConnectPayoutRecorder applies to failed payouts.
    it "reverses nothing when no credit was ever recorded" do
      handle("topup.reversed", topup)

      expect(settled_lines).to be_empty
      expect(balance_cents).to eq(0)
    end
  end

  describe "events it should not act on" do
    it "ignores a top-up for an unknown connected account" do
      handle("topup.succeeded", topup, account_id: "acct_unknown")

      expect(SchoolFunding.count).to eq(0)
      expect(balance_cents).to eq(0)
    end

    it "ignores an event type it does not handle" do
      expect(handle("topup.something_else", topup)).to be_nil
      expect(balance_cents).to eq(0)
    end

    it "ignores a zero or negative amount rather than posting a nonsense line" do
      handle("topup.succeeded", topup(amount: 0))

      expect(settled_lines).to be_empty
    end
  end

  describe "dispatch from the webhook handler" do
    # The recorder is only useful if the endpoint actually routes to it.
    it "is reached for topup events arriving on the connect endpoint" do
      Fuime::ConnectWebhookHandler.new(event: stripe_event("topup.succeeded", topup)).handle

      expect(balance_cents).to eq(50_000)
    end
  end
end
