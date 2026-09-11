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
      expect(event.public_message).to be_present
      expect(event.fuime_offers.published.count).to eq(1)
      expect(event.fuime_offers.draft.count).to eq(1)
      expect(event.accepts_payments?).to be(false)
    end

    it "is idempotent and keeps offers creatable" do
      first = described_class.new.seed!
      second = described_class.new.seed!

      expect(second[:event].id).to eq(first[:event].id)
      expect(Event.where(slug: described_class::SLUG).count).to eq(1)
      expect(first[:event].fuime_offers.live.count).to eq(2)
    end

    # "On Fuime since" on the storefront and the Insights timeframe menu on
    # home both read created_at; a venture born during the meeting reads wrong.
    it "backdates the venture on first seed only" do
      event = described_class.new.seed![:event]
      expect(event.created_at).to be < 9.weeks.ago

      travel_to(1.day.from_now) do
        described_class.new.seed!
      end
      expect(event.reload.created_at).to be < 9.weeks.ago
    end

    # Every reset gives the room the first-run experience: the welcome overlay
    # and the guided tour for Maya, and none of that for the parent.
    it "re-arms the welcome for the teen and retires any started tour" do
      result = described_class.new.seed!
      position = OrganizerPosition.find_by!(user: result[:teen], event: result[:event])
      position.update!(first_time: false)
      tour = Tour.create!(tourable: position, name: "welcome", step: 3)

      described_class.new.seed!

      expect(position.reload.first_time).to be(true)
      expect(Tour.unscoped.find(tour.id).active).to be(false)
      guardian_position = OrganizerPosition.find_by!(user: result[:guardian], event: result[:event])
      expect(guardian_position.first_time).to be(false)
    end

    # Anything the presenter listed during a demo is archived so the list
    # reads the same every time; the draft sample goes back to being a draft.
    it "restores the two sample offers and archives extras" do
      result = described_class.new.seed!
      event = result[:event]
      extra = create(:fuime_offer, event:, name: "Dog walking")
      draft = event.fuime_offers.draft.first
      expect(draft.publish!).to be(true)

      described_class.new.seed!

      expect(extra.reload).to be_archived
      expect(draft.reload).to be_draft
      expect(event.fuime_offers.live.count).to eq(2)
    end

    it "leaves a fresh new-founder persona with no name, no age answer and no venture" do
      result = described_class.new.seed!
      sam = result[:new_founder]

      expect(sam.email).to eq(described_class::NEW_FOUNDER_EMAIL)
      expect(sam.full_name).to be_blank
      expect(sam.age_attestation).to be_nil
      expect(sam).to be_onboarding
      expect(sam.events).to be_empty
      expect(sam.applications).to be_empty
    end
  end

  describe "#reset_new_founder!" do
    before { stub_ledger_import }

    # A signup demo leaves a named, attested founder with an application, a
    # venture and a guardian invite behind. The next demo has to start on the
    # first screen, so all of it goes.
    it "wipes a mid-demo founder back to a blank slate" do
      sam = described_class.new.reset_new_founder!
      sam.update_columns(full_name: "Sam Rivera")
      sam.attest_minor_13_plus!(ip: "127.0.0.1", user_agent: "rspec")
      venture = create(:event, slug: "sams-demo-venture")
      create(:organizer_position, user: sam, event: venture, role: :manager)
      application = create(:event_application, user: sam, event: venture, teen_led: true)
      create(:guardianship, minor: sam, guardian: create(:user, birthday: 40.years.ago.to_date))

      described_class.new.reset_new_founder!

      sam.reload
      expect(sam.full_name).to be_blank
      expect(sam.age_attestation).to be_nil
      expect(sam.events).to be_empty
      expect(Event.find_by(id: venture.id)).to be_nil
      expect(Event::Application.find_by(id: application.id)).to be_nil
      expect(Guardianship.where(minor: sam)).to be_empty
    end

    it "never touches the pitch venture" do
      pitch = described_class.new.seed![:event]
      sam = User.find_by!(email: described_class::NEW_FOUNDER_EMAIL)
      create(:organizer_position, user: sam, event: pitch, role: :member)

      described_class.new.reset_new_founder!

      expect(Event.find_by(id: pitch.id)).to be_present
      expect(pitch.reload).to be_demo_mode
    end
  end

  describe "#record_mock_sale!" do
    it "refuses any venture but the pitch venture" do
      other = create(:event, :demo_mode, slug: "other-demo")
      allow(RawCsvTransactionService::Create).to receive(:new)

      expect(described_class.new.record_mock_sale!(event: other, memo: "Lawn", amount_cents: 35_00)).to be_nil
      expect(RawCsvTransactionService::Create).not_to have_received(:new)
    end

    it "refuses a non-positive amount" do
      pitch = create(:event, :demo_mode, slug: described_class::SLUG)
      allow(RawCsvTransactionService::Create).to receive(:new)

      expect(described_class.new.record_mock_sale!(event: pitch, memo: "Lawn", amount_cents: 0)).to be_nil
      expect(RawCsvTransactionService::Create).not_to have_received(:new)
    end

    # The import is stubbed out, so nothing lands — and the method must say so
    # rather than hand back whatever the last ledger line happened to be.
    it "returns nil when no line landed on the ledger" do
      stub_ledger_import
      pitch = described_class.new.seed![:event]

      expect(described_class.new.record_mock_sale!(event: pitch, memo: "Lawn [fuime_fee]", amount_cents: 35_00)).to be_nil
    end

    # The real pipeline: CSV row → hashed → canonical → mapped to the venture.
    it "posts one income line through the CSV import path" do
      pitch = described_class.new.seed![:event]
      before = pitch.canonical_transactions.count

      sale = described_class.new.record_mock_sale!(event: pitch, memo: "Front lawn — storefront", amount_cents: 35_00)

      expect(sale).to be_a(CanonicalTransaction)
      expect(sale.amount_cents).to eq(35_00)
      expect(sale.memo).to include("Front lawn")
      expect(pitch.canonical_transactions.count).to eq(before + 1)
    end
  end
end
