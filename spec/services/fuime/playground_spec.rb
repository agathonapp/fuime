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
  end
end
