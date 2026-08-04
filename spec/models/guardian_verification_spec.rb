# frozen_string_literal: true

require "rails_helper"

# Fuime: the guard that keeps "we never store identity documents" true over time.
#
# L4 requires verify-then-delete: COPPA's VPC methods mandate prompt deletion, BIPA gives
# a private right of action over stored face-match data, and holding ID documents pulls
# Fuime into breach-notification statutes it is otherwise entirely outside.
#
# The claim decays without enforcement — someone adds a column to make a screen easier,
# or pastes a value into vendor_ref while debugging. These examples are the enforcement.
RSpec.describe GuardianVerification, type: :model do
  let(:venture) { create(:event) }
  let(:guardian) { create(:user, birthday: 40.years.ago.to_date) }

  def build_record(**overrides)
    described_class.new({
      event: venture,
      user: guardian,
      verification_method: described_class::ID_AND_DATABASE,
      submitted_at: Time.current,
      fields_forwarded: %w[dob ssn_last_4],
      vendor: "stripe",
      vendor_ref: "file_1A2b3C4d"
    }.merge(overrides))
  end

  # THE structural guarantee. If a column capable of holding identity data is ever added,
  # this fails rather than shipping — which is the only way a rule like this survives
  # contact with a deadline.
  describe "the table itself cannot hold personal data" do
    FORBIDDEN_COLUMN_FRAGMENTS = %w[
      ssn social_security tax_id tin ein
      first_name last_name full_name legal_name
      dob date_of_birth birthday
      address line1 line2 postal city state zip
      id_number document_number passport license
      image photo selfie scan front back file_data attachment
    ].freeze

    it "has no column whose name suggests it holds identity data" do
      offending = described_class.column_names.select do |column|
        FORBIDDEN_COLUMN_FRAGMENTS.any? { |fragment| column.include?(fragment) }
      end

      expect(offending).to be_empty,
                           "guardian_verifications must hold only the consent RECORD (method, vendor " \
                           "ref, timestamps, doc-version hash, IP/UA) — never the evidence. " \
                           "Offending columns: #{offending.inspect}. If Stripe needs one of these, " \
                           "forward it and store a vendor_ref instead."
    end

    it "has no binary or attachment column" do
      binary = described_class.columns.select { |c| c.type.in?(%i[binary blob]) }.map(&:name)

      expect(binary).to be_empty
    end
  end

  describe "fields_forwarded records names, never values" do
    it "accepts known field names" do
      expect(build_record(fields_forwarded: %w[first_name dob address ssn_last_4 id_document])).to be_valid
    end

    # The likeliest mistake: someone puts the VALUE here instead of the name. The
    # allowlist makes that impossible rather than merely discouraged, because no value
    # is a member of the allowed set.
    it "rejects a value masquerading as a field name" do
      record = build_record(fields_forwarded: ["123-45-6789"])

      expect(record).not_to be_valid
      expect(record.errors[:fields_forwarded].join).to match(/never their values/i)
    end

    it "rejects an unknown field name" do
      record = build_record(fields_forwarded: %w[mothers_maiden_name])

      expect(record).not_to be_valid
    end

    it "rejects non-string entries" do
      record = build_record(fields_forwarded: [{ ssn_last_4: "6789" }])

      expect(record).not_to be_valid
      expect(record.errors[:fields_forwarded].join).to match(/field names as strings/i)
    end
  end

  describe "the last line of defence" do
    it "refuses to save an SSN hidden in vendor_ref" do
      record = build_record(vendor_ref: "ref for 123-45-6789")

      expect(record).not_to be_valid
      expect(record.errors[:vendor_ref].join).to match(/Social Security number/i)
    end

    it "refuses to save an SSN without dashes" do
      record = build_record(vendor_ref: "customer 123456789 verified")

      expect(record).not_to be_valid
    end

    # A vendor ref is a token. A base64 payload here would be the document itself.
    it "refuses an embedded document" do
      record = build_record(vendor_ref: "data:image/png;base64,iVBORw0KGgoAAAANS")

      expect(record).not_to be_valid
      expect(record.errors[:vendor_ref].join).to match(/document or image/i)
    end

    it "refuses a vendor_ref long enough to be a payload rather than a token" do
      record = build_record(vendor_ref: "a" * 400)

      expect(record).not_to be_valid
      expect(record.errors[:vendor_ref].join).to match(/too long to be a vendor token/i)
    end

    it "accepts a normal Stripe file token" do
      expect(build_record(vendor_ref: "file_1PxYzAbCdEfGhIjK")).to be_valid
    end
  end

  describe "method validation" do
    it "accepts the COPPA-grade methods" do
      described_class::METHODS.each do |method|
        expect(build_record(verification_method: method)).to be_valid, "expected #{method} to be valid"
      end
    end

    it "rejects an invented method" do
      expect(build_record(verification_method: "vibes")).not_to be_valid
    end

    # BIPA reaches face-matching specifically, and it carries a private right of action.
    # Flagged so a flow using it can be given the notice-and-consent choreography rather
    # than only deletion.
    it "flags the face-match method as BIPA-relevant" do
      expect(build_record(verification_method: described_class::ID_AND_SELFIE)).to be_bipa_applies
      expect(build_record(verification_method: described_class::ID_AND_DATABASE)).not_to be_bipa_applies
    end
  end

  describe "acceptance" do
    # Stripe verifies asynchronously, so "we sent it" is not "they took it". Conflating
    # them is how a family gets told they are verified while requirements are outstanding.
    it "is not accepted merely because it was submitted" do
      expect(build_record(accepted_at: nil)).not_to be_accepted
    end

    it "is accepted once Stripe confirms" do
      expect(build_record(accepted_at: Time.current)).to be_accepted
    end
  end

  describe "evidence release" do
    it "is released when the document was forwarded and kept by nobody" do
      record = build_record(evidence_released_at: Time.current)

      expect(record).to be_evidence_released
    end

    # Fuime never receives an image for these, so a null timestamp is correct rather
    # than an outstanding deletion. Stating it explicitly stops an audit reading these
    # rows as unremediated.
    it "is vacuously released for methods where Fuime never holds evidence" do
      [described_class::STRIPE_HOSTED, described_class::CARD_MICRO_TRANSACTION].each do |method|
        record = build_record(verification_method: method, evidence_released_at: nil)

        expect(record).to be_evidence_released, "#{method} never involves Fuime holding an image"
      end
    end

    it "is NOT released when Fuime took a document and recorded no release" do
      record = build_record(verification_method: described_class::ID_AND_DATABASE,
                            evidence_released_at: nil)

      expect(record).not_to be_evidence_released
    end

    # The query a retention job and an audit both want.
    it "surfaces rows still awaiting release" do
      stale = build_record(verification_method: described_class::ID_AND_DATABASE,
                           evidence_released_at: nil)
      stale.save!
      build_record(verification_method: described_class::STRIPE_HOSTED,
                   evidence_released_at: nil).save!

      expect(described_class.awaiting_evidence_release).to contain_exactly(stale)
    end
  end
end
