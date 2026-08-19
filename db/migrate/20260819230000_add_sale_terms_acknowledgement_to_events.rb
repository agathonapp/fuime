# frozen_string_literal: true

# Fuime: record that the operator was actually told what selling through Fuime
# means, and said so.
#
# Under merchant-of-record Fuime is the legal seller and the teen operator is a
# vendor. Until now that relationship existed only as a page: there is no signed
# vendor agreement (no DocuSeal template is configured, so
# Event::Plan#contract_available? is false and Event::Application#send_contract
# returns nil), and the application flow has no terms checkbox. So a 13-year-old
# could publish an offer, sell as Fuime's vendor, and have agreed to nothing.
#
# That is the concrete form of MOR_RISK_ACCEPTANCE.md §2 Q2 — the contractor
# characterisation rests on facts the operator has never been shown — and it runs
# into L2, where a teen-only clickwrap is voidable anyway.
#
# This is NOT a contract and does not pretend to be one. It is a record that a
# specific person, at a specific time, was shown a specific version of the terms
# and affirmed them. For an unreviewed structure that record is worth far more
# than its cost, and it is the difference between "we published a page" and "they
# acknowledged, and here is when".
#
# On the Event rather than the User: the obligations attach to a venture's sales,
# a venture can have more than one operator, and the venture is what publishes.
# `_by_id` records which human clicked so the record names a person.
class AddSaleTermsAcknowledgementToEvents < ActiveRecord::Migration[8.0]
  # Required by the concurrent index below: CREATE INDEX CONCURRENTLY cannot run
  # inside a transaction block. Same as CreateFuimeCohorts.
  disable_ddl_transaction!

  def change
    # Nullable with no default and no backfill: a venture that has never
    # acknowledged must read as never having acknowledged. Defaulting this to
    # anything would manufacture consent for every venture that already exists.
    add_column :events, :sale_terms_acknowledged_at, :datetime
    add_column :events, :sale_terms_version, :string

    # Reference and foreign key added separately: strong_migrations refuses the
    # combined form, because a concurrent index and an ALTER TABLE ... ADD
    # CONSTRAINT cannot share a transaction. Same split as CreateFuimeCohorts.
    add_reference :events, :sale_terms_acknowledged_by,
                  null: true,
                  index: { algorithm: :concurrently }

    # NOT VALID: adding a validated FK takes a lock on both tables and scans
    # `events`, which is the widest table in this schema. Nothing exists to
    # violate it, since the column is new and null.
    add_foreign_key :events, :users,
                    column: :sale_terms_acknowledged_by_id,
                    validate: false
  end
end
