# frozen_string_literal: true

# Fuime: the RECORD of a guardian being verified. Never the evidence itself.
#
# ── Read this before adding a column ────────────────────────────────────────
#
# This table exists because `requirement_collection = application` (the cards
# profile) makes Fuime responsible for collecting the guardian's identity details
# and passing them to Stripe. That is a privacy reversal from the payments-only
# profile, where the SSN went straight to Stripe and never touched Fuime.
#
# The reversal is unavoidable. Becoming a store of identity documents is NOT.
#
# LEGAL_RESEARCH.md §5 is unambiguous: "ID images: verify then delete… Store the
# consent *record* (method, vendor ref, timestamp, doc-version hash, IP/UA) — never
# the image." The reasons stack:
#
#   * COPPA's verifiable-parental-consent methods REQUIRE prompt deletion;
#   * BIPA (IL) reaches face-matching with a $1K–5K per-violation PRIVATE RIGHT OF
#     ACTION, so a stored selfie is a plaintiff's exhibit;
#   * holding ID documents triggers state breach-notification statutes that Fuime
#     would otherwise be entirely outside.
#
# So this table is deliberately a metadata table. The design rule, which the model
# enforces and a spec pins:
#
#   NO COLUMN HERE MAY EVER HOLD A NAME, DATE OF BIRTH, ADDRESS, SSN (WHOLE OR
#   PARTIAL), DOCUMENT NUMBER, OR IMAGE.
#
# Those values pass through Fuime's process memory to Stripe and are never assigned
# to an ActiveRecord attribute. `Fuime::RequirementCollectionService` is the only
# thing that touches them, and it forwards rather than stores.
#
# If a future requirement seems to need one of those columns, the answer is almost
# certainly a Stripe API call plus a `vendor_ref`, not a column.
class CreateGuardianVerifications < ActiveRecord::Migration[8.0]
  def change
    create_table :guardian_verifications do |t|
      t.references :event, null: false, foreign_key: true
      # The guardian being verified. A reference, not their details.
      t.references :user, null: false, foreign_key: true

      # Which COPPA-grade method was used. See
      # GuardianVerification::METHODS — ID + database check, ID + selfie face-match,
      # or a card micro-transaction.
      t.string :verification_method, null: false

      # The vendor's identifier for the evidence Fuime does not keep: a Stripe File
      # token, or an identity-vendor reference. This is the "vendor ref" from L4 and
      # it is what makes deletion safe — the evidence still exists at the vendor and
      # can be re-fetched under subpoena without Fuime holding it.
      t.text :vendor_ref

      # Which vendor the ref belongs to, because a bare token is unresolvable later.
      t.string :vendor

      # WHICH fields were forwarded, by NAME ONLY — e.g. ["dob", "ssn_last_4",
      # "address", "id_document"]. Never their values. This is what lets support
      # answer "what did we send Stripe?" without Fuime holding any of it.
      t.jsonb :fields_forwarded, null: false, default: []

      # What Stripe said was outstanding at the moment of submission. Useful for
      # explaining, months later, why a particular field was asked for.
      t.jsonb :stripe_requirements_snapshot, null: false, default: {}

      # Hash of the disclosure/consent text version the guardian was shown. Proves
      # WHAT they agreed to without storing a copy per guardian.
      t.string :doc_version_hash

      t.datetime :submitted_at, null: false
      # Set when Stripe confirms it accepted the identity information. Distinct from
      # submitted_at because Stripe verifies asynchronously and "we sent it" is not
      # "they accepted it".
      t.datetime :accepted_at

      # Set when Fuime confirmed the uploaded document is no longer in its own
      # possession. Recorded rather than assumed: "we delete images" is a claim that
      # needs evidence, and a null here on an old row is a visible problem.
      t.datetime :evidence_released_at

      # IP/UA at consent, per L4. Same provenance fields Guardianship records.
      t.string :consent_ip
      t.text :consent_user_agent

      t.timestamps
    end

    # The current verification for a venture's guardian is looked up on every card
    # screen render.
    add_index :guardian_verifications, %i[event_id user_id]
  end
end
