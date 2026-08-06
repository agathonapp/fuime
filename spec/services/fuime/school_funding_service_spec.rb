# frozen_string_literal: true

require "rails_helper"

# Fuime: asking Stripe to pull a school's own money into its own Stripe balance.
#
# Every example here stubs Stripe, which is the point worth stating rather than
# hiding: whether a Stripe-liability connected account may create a top-up through
# the API at all is UNVERIFIED against the real Stripe (see the service). These
# examples prove the shape of the call and the handling around it — not that Stripe
# will accept it.
#
# The two that matter most are the refusal path (because it is the one most likely
# to be the real behaviour) and the fact that nothing here ever marks its own work
# succeeded. Only a webhook does that.
RSpec.describe Fuime::SchoolFundingService do
  let(:school) { create(:event, plan_type: Event::Plan::School) }
  let!(:account) { create(:stripe_connected_account, :ready, event: school) }
  let(:guide) { create_school_manager(school) }

  let(:service) { described_class.new(event: school) }

  def stub_topup(id: "tu_1")
    topup = Stripe::Topup.construct_from(id:, amount: 50_000, currency: "usd")
    allow(Stripe::Topup).to receive(:create).and_return(topup)
    topup
  end

  describe "#fund!" do
    it "asks Stripe for a top-up on the school's own connected account" do
      stub_topup

      service.fund!(amount_cents: 50_000, requested_by: guide)

      expect(Stripe::Topup).to have_received(:create).with(
        hash_including(amount: 50_000, currency: "usd"),
        { stripe_account: account.stripe_id }
      )
    end

    it "records the funding against the school with the requester attributed" do
      stub_topup

      funding = service.fund!(amount_cents: 50_000, requested_by: guide)

      expect(funding.event).to eq(school)
      expect(funding.requested_by).to eq(guide)
      expect(funding.amount_cents).to eq(50_000)
      expect(funding.stripe_topup_id).to eq("tu_1")
    end

    # The single most important assertion in this file.
    it "leaves the funding pending — only a webhook may call it succeeded" do
      stub_topup

      funding = service.fund!(amount_cents: 50_000, requested_by: guide)

      expect(funding).to be_pending
      expect(funding.succeeded_at).to be_nil
    end

    it "posts nothing to the ledger" do
      stub_topup

      service.fund!(amount_cents: 50_000, requested_by: guide)

      expect(school.balance_v2_cents).to eq(0)
    end
  end

  describe "when Stripe refuses" do
    before do
      allow(Stripe::Topup).to receive(:create)
        .and_raise(Stripe::InvalidRequestError.new("Top-ups are not supported for this account", nil))
    end

    it "raises with the Dashboard fallback named, because that path still works" do
      expect { service.fund!(amount_cents: 50_000, requested_by: guide) }
        .to raise_error(described_class::StripeRefused, /Stripe Dashboard/)
    end

    # Deleting the evidence of a failed attempt turns a support question into
    # archaeology.
    it "keeps the row, marked failed, with Stripe's reason on it" do
      begin
        service.fund!(amount_cents: 50_000, requested_by: guide)
      rescue described_class::StripeRefused
        nil
      end

      funding = SchoolFunding.last
      expect(funding).to be_failed
      expect(funding.failure_message).to include("not supported")
    end
  end

  describe "refusals before Stripe is called" do
    it "refuses a venture that is not a school programme" do
      family = create(:event)
      create(:stripe_connected_account, :ready, event: family)

      expect { described_class.new(event: family).fund!(amount_cents: 50_000, requested_by: guide) }
        .to raise_error(described_class::NotASchoolVenture)
    end

    it "refuses when the school has no Stripe account to fund" do
      bare = create(:event, plan_type: Event::Plan::School)

      expect { described_class.new(event: bare).fund!(amount_cents: 50_000, requested_by: guide) }
        .to raise_error(described_class::AccountNotReady)
    end

    it "refuses an amount below Stripe's floor" do
      expect { service.fund!(amount_cents: 50, requested_by: guide) }
        .to raise_error(described_class::Error, /smallest top-up/i)
    end

    it "does not call Stripe when it refuses" do
      allow(Stripe::Topup).to receive(:create)

      begin
        service.fund!(amount_cents: 50, requested_by: guide)
      rescue described_class::Error
        nil
      end

      expect(Stripe::Topup).not_to have_received(:create)
    end
  end

  # Stripe can deliver the webhook before the create call returns, in which case the
  # recorder has already made a row keyed on the topup id and this one has none.
  # Two rows for one movement would double-count in any reconciliation a business
  # office does.
  describe "when the webhook wins the race" do
    it "keeps one row, and attributes it to the requester" do
      topup = stub_topup

      allow(Stripe::Topup).to receive(:create) do
        Fuime::ConnectFundingRecorder.new(
          event: Stripe::Event.construct_from(
            type: "topup.succeeded",
            account: account.stripe_id,
            data: { object: { id: topup.id, object: "topup", amount: 50_000, created: Time.current.to_i } }
          )
        ).handle
        topup
      end

      funding = service.fund!(amount_cents: 50_000, requested_by: guide)

      expect(SchoolFunding.where(stripe_topup_id: "tu_1").count).to eq(1)
      expect(funding.requested_by).to eq(guide)
      expect(funding).to be_succeeded
      expect(school.balance_v2_cents).to eq(50_000)
    end
  end

  # The reason the whole feature exists.
  describe "end to end with an award" do
    it "lets a school award a student only after the top-up has landed" do
      _school, _cohort, venture = nil
      tree = build_school_tree
      school_with_tree = tree[0]
      venture = tree[2]
      create(:stripe_connected_account, :ready, event: school_with_tree)
      manager = create_school_manager(school_with_tree)
      student = create_student(venture)

      award_service = Fuime::SchoolAwardService.new(venture:)
      expect(award_service.available_to_award_cents).to eq(0)

      Fuime::ConnectFundingRecorder.new(
        event: Stripe::Event.construct_from(
          type: "topup.succeeded",
          account: school_with_tree.stripe_connected_account.stripe_id,
          data: { object: { id: "tu_e2e", object: "topup", amount: 100_00, created: Time.current.to_i } }
        )
      ).handle

      expect(award_service.available_to_award_cents).to eq(100_00)

      expect {
        award_service.grant!(amount_cents: 100_00, awarded_to: student, awarded_by: manager)
      }.to change { venture.balance_v2_cents }.by(100_00)
    end
  end
end
