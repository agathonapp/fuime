# frozen_string_literal: true

require "rails_helper"

# Fuime: collecting the guardian's identity details on the cards profile.
#
# The examples that matter are the ones asserting what is NOT persisted. Fuime taking on
# `requirement_collection = application` is unavoidable for cards; Fuime becoming a store
# of Social Security numbers and ID photographs is not, and the difference is entirely in
# this service's behaviour.
RSpec.describe Fuime::RequirementCollectionService do
  let(:venture) { create(:event) }
  let(:minor) { create(:user, :minor) }
  let(:guardian) { create(:user, birthday: 40.years.ago.to_date) }

  let(:service) { described_class.new(event: venture, guardian:) }

  let(:details) do
    {
      first_name: "Dana",
      last_name: "Okafor",
      dob: Date.new(1986, 4, 17),
      ssn_last_4: "6789",
      address: { line1: "1 Founders Way", city: "Austin", state: "TX", postal_code: "78701" }
    }
  end

  before do
    create(:organizer_position, event: venture, user: minor)
    create(:guardianship, :active, guardian:, minor:)
  end

  def cards_account(**overrides)
    create(:stripe_connected_account, :cards_enabled, :ready,
           event: venture, owner: guardian, **overrides)
  end

  def stub_account_update(requirements: {})
    account = Stripe::Account.construct_from(
      id: venture.stripe_connected_account.stripe_id,
      charges_enabled: true, payouts_enabled: true, details_submitted: true, livemode: false,
      controller: { losses: { payments: "application" }, fees: { payer: "application" },
                    requirement_collection: "application", stripe_dashboard: { type: "none" }
},
      capabilities: { card_payments: "active", transfers: "active", card_issuing: "active" },
      requirements: requirements
    )
    allow(Stripe::Account).to receive(:update).and_return(account)
    account
  end

  def stub_file_upload(id: "file_1PxYz")
    allow(Stripe::File).to receive(:create).and_return(Stripe::File.construct_from(id:))
  end

  describe "when Fuime must not collect" do
    # The default profile has Stripe collecting directly. Gathering an SSN Fuime has no
    # need for would be taking on breach liability for nothing.
    it "refuses on a payments-only venture" do
      create(:stripe_connected_account, :ready, event: venture, owner: guardian)

      expect { service.submit!(details:) }
        .to raise_error(described_class::CollectionNotRequired, /through Stripe directly/i)
    end

    it "refuses when there is no Stripe account at all" do
      expect { service.submit!(details:) }.to raise_error(described_class::CollectionNotRequired)
    end

    it "does not contact Stripe when it refuses" do
      create(:stripe_connected_account, :ready, event: venture, owner: guardian)
      allow(Stripe::Account).to receive(:update)

      expect { service.submit!(details:) }.to raise_error(described_class::CollectionNotRequired)
      expect(Stripe::Account).not_to have_received(:update)
    end
  end

  describe "forwarding details to Stripe" do
    before { cards_account }

    it "sends the identity fields in Stripe's individual shape" do
      stub_account_update

      service.submit!(details:)

      expect(Stripe::Account).to have_received(:update).with(
        venture.stripe_connected_account.stripe_id,
        hash_including(
          individual: hash_including(
            first_name: "Dana",
            last_name: "Okafor",
            ssn_last_4: "6789",
            dob: { day: 17, month: 4, year: 1986 }
          )
        ),
        anything
      )
    end

    # Updating a connected account uses the platform key with the id as the first
    # argument. Passing a Stripe-Account header here produces an error that reads like a
    # permissions problem, so the absence is asserted.
    it "updates the account with the platform key and no Stripe-Account header" do
      stub_account_update

      service.submit!(details:)

      expect(Stripe::Account).to have_received(:update) do |_id, _params, opts|
        expect(opts).not_to have_key(:stripe_account)
        expect(opts[:api_key]).to be_present
      end
    end

    it "only forwards fields it knows about" do
      stub_account_update

      service.submit!(details: details.merge(favourite_colour: "green", internal_note: "vip"))

      expect(Stripe::Account).to have_received(:update) do |_id, params, _opts|
        expect(params[:individual].keys).not_to include(:favourite_colour, :internal_note)
      end
    end

    it "raises when there is nothing to send" do
      stub_account_update

      expect { service.submit!(details: {}) }.to raise_error(described_class::NothingSubmitted)
    end
  end

  describe "what is persisted, and what is not" do
    before { cards_account }

    it "records only field NAMES, never their values" do
      stub_account_update

      record = service.submit!(details:)

      expect(record.fields_forwarded).to contain_exactly("first_name", "last_name", "dob", "ssn_last_4", "address")
      expect(record.fields_forwarded.to_json).not_to include("6789")
      expect(record.fields_forwarded.to_json).not_to include("Okafor")
    end

    # The whole point. If any of these appear anywhere in the persisted row, the design
    # has failed.
    it "persists no identity value anywhere on the record" do
      stub_account_update

      record = service.submit!(details:)

      serialized = record.attributes.to_json
      ["6789", "Okafor", "Dana", "1 Founders Way", "78701", "1986"].each do |secret|
        expect(serialized).not_to include(secret),
                                  "#{secret.inspect} was persisted on guardian_verifications"
      end
    end

    it "records the consent provenance L4 asks for" do
      stub_account_update

      record = service.submit!(
        details:, consent_ip: "203.0.113.9", consent_user_agent: "Mobile Safari",
        doc_version_hash: "abc123"
      )

      expect(record.consent_ip).to eq("203.0.113.9")
      expect(record.consent_user_agent).to eq("Mobile Safari")
      expect(record.doc_version_hash).to eq("abc123")
      expect(record.submitted_at).to be_present
    end

    # Snapshotted before the update, because afterwards Stripe has cleared whatever was
    # satisfied and the record would not show what was actually asked for.
    it "snapshots what Stripe was asking for at submission time" do
      venture.stripe_connected_account.update!(
        requirements: { "currently_due" => ["individual.ssn_last_4"], "past_due" => [] }
      )
      stub_account_update(requirements: { currently_due: [] })

      record = service.submit!(details:)

      expect(record.stripe_requirements_snapshot["currently_due"]).to eq(["individual.ssn_last_4"])
    end

    # Stripe verifies asynchronously; acceptance is recorded later by account.updated.
    it "does not claim Stripe accepted the details" do
      stub_account_update

      expect(service.submit!(details:)).not_to be_accepted
    end
  end

  describe "the ID document" do
    before { cards_account }

    it "uploads it to Stripe and keeps only the token" do
      stub_account_update
      stub_file_upload(id: "file_abc123")

      record = service.submit!(details:, document: StringIO.new("fake-image-bytes"))

      expect(record.vendor).to eq("stripe")
      expect(record.vendor_ref).to eq("file_abc123")
      expect(record.fields_forwarded).to include("id_document")
    end

    it "attaches the token to the account rather than the bytes" do
      stub_account_update
      stub_file_upload(id: "file_abc123")

      service.submit!(details:, document: StringIO.new("fake-image-bytes"))

      expect(Stripe::Account).to have_received(:update).with(
        anything,
        hash_including(individual: hash_including(verification: { document: { front: "file_abc123" } })),
        anything
      )
    end

    # A file must BELONG to the connected account, which needs the Stripe-Account
    # header — the opposite of Account.update above. Getting this backwards fails in a
    # way that looks like a permissions bug.
    it "uploads with the Stripe-Account header" do
      stub_account_update
      stub_file_upload

      service.submit!(details:, document: StringIO.new("bytes"))

      expect(Stripe::File).to have_received(:create).with(
        hash_including(purpose: "identity_document"),
        hash_including(stripe_account: venture.stripe_connected_account.stripe_id)
      )
    end

    # Fuime forwarded the bytes and kept none, so release is simultaneous with
    # submission rather than a deletion job that might never run.
    it "records the evidence as released immediately" do
      stub_account_update
      stub_file_upload

      record = service.submit!(details:, document: StringIO.new("bytes"))

      expect(record.evidence_released_at).to be_present
      expect(record).to be_evidence_released
      expect(GuardianVerification.awaiting_evidence_release).to be_empty
    end

    it "stores no image bytes on the record" do
      stub_account_update
      stub_file_upload

      record = service.submit!(details:, document: StringIO.new("fake-image-bytes"))

      expect(record.attributes.to_json).not_to include("fake-image-bytes")
    end
  end

  describe "error handling" do
    before { cards_account }

    # A Stripe validation error can echo the submitted value back. Interpolating it into
    # Fuime's message would put an SSN into logs and error reports, reintroducing the
    # exposure this service exists to prevent.
    it "never echoes Stripe's message, which can contain the submitted value" do
      allow(Stripe::Account).to receive(:update)
        .and_raise(Stripe::InvalidRequestError.new("invalid ssn_last_4: 6789", nil))

      expect { service.submit!(details:) }.to raise_error(described_class::Error) { |error|
        expect(error.message).not_to include("6789")
        expect(error.message).to match(/check them and try again/i)
      }
    end
  end

  describe "#outstanding_descriptions" do
    before { cards_account }

    it "translates Stripe's machine identifiers into sentences a parent can act on" do
      venture.stripe_connected_account.update!(
        requirements: {
          "currently_due" => %w[individual.ssn_last_4 individual.verification.document external_account],
          "past_due"      => []
        }
      )

      descriptions = described_class.new(event: venture.reload, guardian:).outstanding_descriptions

      expect(descriptions).to include(match(/last 4 digits/i))
      expect(descriptions).to include(match(/photo of the account owner's government-issued ID/i))
      expect(descriptions).to include(match(/bank account for payouts/i))
    end

    # Stripe adds requirement identifiers. One nobody can see is a venture that never
    # activates with no explanation, so unknown ones are humanised rather than dropped.
    it "passes through a requirement it has never seen" do
      venture.stripe_connected_account.update!(
        requirements: { "currently_due" => ["individual.political_exposure"], "past_due" => [] }
      )

      descriptions = described_class.new(event: venture.reload, guardian:).outstanding_descriptions

      expect(descriptions).to be_present
      expect(descriptions.first).to match(/political exposure/i)
    end
  end
end
