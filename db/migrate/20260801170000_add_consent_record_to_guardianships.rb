# frozen_string_literal: true

# Fuime: record what a guardian actually agreed to, and when consent ended.
#
# A guardianship is the legal basis for a minor operating a business on Fuime,
# so "they clicked accept" is not a sufficient record. We store the agreement
# version plus the request metadata at signature time — the standard evidence
# set for demonstrating informed consent — and a revocation trail, since a
# guardian withdrawing consent must be auditable after the fact.
class AddConsentRecordToGuardianships < ActiveRecord::Migration[8.0]
  def change
    add_column :guardianships, :agreement_version, :string
    add_column :guardianships, :agreement_ip, :string
    add_column :guardianships, :agreement_user_agent, :string

    add_column :guardianships, :revoked_at, :datetime
    add_reference :guardianships, :revoked_by, foreign_key: { to_table: :users }, null: true, index: true
  end
end
