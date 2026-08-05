# frozen_string_literal: true

# == Schema Information
#
# Table name: guardian_verifications
#
#  id                           :bigint           not null, primary key
#  accepted_at                  :datetime
#  consent_ip                   :string
#  consent_user_agent           :text
#  doc_version_hash             :string
#  evidence_released_at         :datetime
#  fields_forwarded             :jsonb            not null
#  stripe_requirements_snapshot :jsonb            not null
#  submitted_at                 :datetime         not null
#  vendor                       :string
#  vendor_ref                   :text
#  verification_method          :string           not null
#  created_at                   :datetime         not null
#  updated_at                   :datetime         not null
#  event_id                     :bigint           not null
#  user_id                      :bigint           not null
#
# Indexes
#
#  index_guardian_verifications_on_event_id              (event_id)
#  index_guardian_verifications_on_event_id_and_user_id  (event_id,user_id)
#  index_guardian_verifications_on_user_id               (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (event_id => events.id)
#  fk_rails_...  (user_id => users.id)
#
# Fuime: the record that a guardian was verified. Deliberately NOT the evidence.
#
# See the migration for why. Short version: L4 requires "verify then delete" — COPPA's
# VPC methods mandate prompt deletion, BIPA gives a private right of action over stored
# face-match data, and holding ID documents pulls Fuime into breach-notification
# statutes it is otherwise outside. So identity values pass through process memory to
# Stripe and are never assigned to an attribute here.
#
# ── The guard is the point of this class ────────────────────────────────────
#
# "We don't store PII" is a claim that decays. Someone adds a column to make a screen
# easier, or stuffs a value into `vendor_ref` during a debugging session, and the claim
# is quietly false. Two mechanisms stop that:
#
#   1. `fields_forwarded` is validated against an ALLOWLIST of field NAMES, so the
#      column cannot hold values even by accident — only the names of fields sent.
#   2. `no_personal_data_in_attributes` scans this record's own string attributes for
#      SSN-shaped and blob-shaped content and refuses to save.
#
# A spec additionally asserts the TABLE has no PII-capable column, so adding one fails
# the suite rather than shipping.
class GuardianVerification < ApplicationRecord
  # COPPA-grade methods, per LEGAL_RESEARCH.md P2 item 6.
  ID_AND_DATABASE = "id_and_database"
  ID_AND_SELFIE = "id_and_selfie"
  CARD_MICRO_TRANSACTION = "card_micro_transaction"
  # Stripe's own hosted identity check. Listed separately because when Stripe collects
  # and holds the document, Fuime never possesses an image at all — which is the
  # cheapest way to satisfy L4 and the preferred option where available.
  STRIPE_HOSTED = "stripe_hosted"

  METHODS = [ID_AND_DATABASE, ID_AND_SELFIE, CARD_MICRO_TRANSACTION, STRIPE_HOSTED].freeze

  # Face-matching is in scope for BIPA, which carries a private right of action. Any
  # flow using it needs the BIPA notice-and-consent choreography, not just deletion.
  BIPA_METHODS = [ID_AND_SELFIE].freeze

  # The complete set of things Fuime may record having forwarded. NAMES ONLY.
  #
  # An allowlist rather than a pattern check because it is airtight: a value cannot
  # accidentally be recorded here, since no value is a member of this set.
  FORWARDABLE_FIELDS = %w[
    first_name last_name dob address phone email
    ssn_last_4 id_number id_document business_url mcc
  ].freeze

  # Anything matching these must never reach an attribute on this model.
  SSN_PATTERN = /\b\d{3}-?\d{2}-?\d{4}\b/
  DATA_URI_PATTERN = /\Adata:[^;]*;base64,/i
  # A vendor ref is a token (`file_1A2b…`). Anything this long is a payload.
  MAX_REF_LENGTH = 255

  belongs_to :event
  belongs_to :user

  validates :verification_method, inclusion: { in: METHODS }
  validates :submitted_at, presence: true

  validate :fields_forwarded_are_names_only
  validate :no_personal_data_in_attributes

  scope :accepted, -> { where.not(accepted_at: nil) }
  scope :recent_first, -> { order(submitted_at: :desc) }

  # Stripe accepted the identity information. Distinct from "Fuime sent it" because
  # Stripe verifies asynchronously, and conflating the two is how a family gets told
  # they are verified while Stripe still has requirements outstanding.
  def accepted?
    accepted_at.present?
  end

  # Has Fuime confirmed it is no longer holding the document?
  #
  # Vacuously true for methods where Fuime never receives an image (Stripe-hosted, card
  # micro-transaction), and that is stated rather than left implicit — a null
  # `evidence_released_at` on those rows is correct, not an outstanding deletion.
  def evidence_released?
    return true if never_possessed_evidence?

    evidence_released_at.present?
  end

  def never_possessed_evidence?
    verification_method.in?([STRIPE_HOSTED, CARD_MICRO_TRANSACTION])
  end

  # Rows that still need attention: Fuime took an image and has not recorded releasing
  # it. This is the query a retention job and an audit both want, and the reason
  # `evidence_released_at` is recorded rather than assumed.
  def self.awaiting_evidence_release
    where(verification_method: [ID_AND_DATABASE, ID_AND_SELFIE], evidence_released_at: nil)
  end

  def bipa_applies?
    verification_method.in?(BIPA_METHODS)
  end

  private

  def fields_forwarded_are_names_only
    values = Array(fields_forwarded)

    unless values.all? { |v| v.is_a?(String) }
      errors.add(:fields_forwarded, "must contain field names as strings, never values")
      return
    end

    unknown = values - FORWARDABLE_FIELDS
    return if unknown.empty?

    # Named explicitly in the message: the most likely cause of an unknown entry is
    # someone putting a VALUE here, and a vague error would send them looking in the
    # wrong place.
    errors.add(
      :fields_forwarded,
      "contains #{unknown.inspect}, which are not known field names. This column records " \
      "WHICH fields were sent to Stripe, never their values."
    )
  end

  # Last line of defence. If identity data reaches this model at all, something
  # upstream is wrong, and failing the save is better than persisting it.
  def no_personal_data_in_attributes
    %i[vendor vendor_ref doc_version_hash consent_ip consent_user_agent].each do |attr|
      value = self[attr]
      next if value.blank?

      if value.to_s.match?(SSN_PATTERN)
        errors.add(attr, "looks like it contains a Social Security number, which must never be stored")
      end

      if value.to_s.match?(DATA_URI_PATTERN)
        errors.add(attr, "looks like it contains an embedded document or image, which must never be stored")
      end
    end

    if vendor_ref.present? && vendor_ref.to_s.length > MAX_REF_LENGTH
      errors.add(:vendor_ref, "is too long to be a vendor token; it must not hold a document payload")
    end

    if fields_forwarded.to_json.match?(SSN_PATTERN)
      errors.add(:fields_forwarded, "appears to contain a Social Security number")
    end
  end

end
