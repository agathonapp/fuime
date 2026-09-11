# frozen_string_literal: true

require "rails_helper"

# Fuime: the production pitch venture. Must run while Stripe is live and
# must not call DemoSandbox.guard_enabled!.
RSpec.describe Fuime::Playground do
  def stub_ledger_import
    allow(RawCsvTransactionService::Create).to receive(:new).and_return(
      instance_double(RawCsvTransactionService::Create, run: nil)
    )
    allow(TransactionEngine::HashedTransactionService::RawCsvTransaction::Import)
      .to receive(:new).and_return(instance_double(TransactionEngine::HashedTransactionService::RawCsvTransaction::Import, run: true))
    allow(TransactionEngine::CanonicalTransactionService::Import::All)
      .to receive(:new).and_return(instance_double(TransactionEngine::CanonicalTransactionService::Import::All, run: true))
  end

  describe "LEDGER_LINES" do
    it "is lawn-job income only — no invented card/supply spend" do
      expect(described_class::LEDGER_LINES).to be_present
      expect(described_class::LEDGER_LINES).to all(include(:memo, :cents, :days_ago))
      expect(described_class::LEDGER_LINES.map { |line| line[:cents] }).to all(be_positive)

      memos = described_class::LEDGER_LINES.map { |line| line[:memo] }
      expect(memos.grep(/business cards|leaf bags|trimmer|booth fee|restaurant depot|packaging/i)).to be_empty
      expect(memos.grep(/lawn|yard|mow/i).size).to eq(memos.size)
    end

    it "lets FeeEngine accrue Free's 7% take-rate rather than inventing a second fee line" do
      expect(Event::Plan::Free::REVENUE_FEE).to eq(0.07)
      expect(Event::Plan::Pro::REVENUE_FEE).to eq(Event::Plan::Free::REVENUE_FEE)
      expect(described_class::LEDGER_LINES.map { |line| line[:memo] }.grep(/fee/i)).to be_empty

      collections = described_class::LEDGER_LINES.sum { |line| line[:cents] }
      expect(described_class.service_fee_cents).to eq(collections * Event::Plan::Free::REVENUE_FEE)
    end
  end

  describe "#seed!" do
    before { stub_ledger_import }

    it "creates a demo_mode venture with a draft and a published offer" do
      allow(StripeService).to receive(:live?).and_return(true)
      allow(Fuime::DemoSandbox).to receive(:guard_enabled!).and_call_original

      result = described_class.new.seed!
      event = result[:event]

      expect(Fuime::DemoSandbox).not_to have_received(:guard_enabled!)
      expect(event.slug).to eq(described_class::SLUG)
      expect(event).to be_demo_mode
      expect(event).to be_is_public
      expect(event.business_category).to eq("services")
      expect(event.storefront_tagline).to be_present
      expect(event.plan).to be_instance_of(Event::Plan::Free)
      expect(event.revenue_fee).to eq(Event::Plan::Free::REVENUE_FEE)
      expect(event.fuime_offers.published.count).to eq(1)
      expect(event.fuime_offers.draft.count).to eq(1)
      expect(event.accepts_payments?).to be(false)
    end

    it "is idempotent and keeps offers creatable" do
      stub_ledger_import
      first = described_class.new.seed!
      second = described_class.new.seed!

      expect(second[:event].id).to eq(first[:event].id)
      expect(Event.where(slug: described_class::SLUG).count).to eq(1)
      expect(first[:event].fuime_offers.live.count).to eq(2)
    end

    it "moves an existing Standard plan onto Free so the pending fee is 7%, not 5%" do
      result = described_class.new.seed!
      event = result[:event]
      event.plan.mark_inactive!(Event::Plan::Standard.name)
      expect(event.reload.plan).to be_instance_of(Event::Plan::Standard)
      expect(event.revenue_fee).to eq(Event::Plan::FALLBACK_REVENUE_FEE)

      described_class.new.seed!
      expect(event.reload.plan).to be_instance_of(Event::Plan::Free)
      expect(event.revenue_fee).to eq(Event::Plan::Free::REVENUE_FEE)
    end

    it "wipes this venture's mock ledger so a refresh replaces invented spend" do
      first = described_class.new.seed!
      event = first[:event]
      leftover = create(:canonical_transaction, amount_cents: -2_200, memo: "Business cards")
      create(:canonical_event_mapping, canonical_transaction: leftover, event:)
      expect(event.reload.canonical_transactions.map(&:memo)).to include("Business cards")

      described_class.new.seed!
      expect(CanonicalTransaction.exists?(leftover.id)).to be(false)
      expect(event.reload.canonical_transactions.map(&:memo)).not_to include("Business cards")
    end
  end

  describe "fund! against the real CSV import" do
    it "posts lawn-job income and FeeEngine's 7% accrual, not a second fee line" do
      result = described_class.new.seed!
      event = result[:event]

      expect(result[:warnings]).to be_empty
      memos = event.canonical_transactions.order(:date, :id).map(&:memo)
      expect(memos).to match_array(described_class::LEDGER_LINES.map { |line| line[:memo] })
      expect(event.canonical_transactions.where("amount_cents < 0")).to be_empty

      expected = described_class.service_fee_cents
      expect(event.fees.where(reason: :revenue).sum(:amount_cents_as_decimal)).to eq(expected)
      expect(event.fronted_fee_balance_v2_cents).to eq(expected.ceil)
    end
  end
end
