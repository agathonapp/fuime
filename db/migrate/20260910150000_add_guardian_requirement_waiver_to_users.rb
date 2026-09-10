# frozen_string_literal: true

# Fuime: admin-only bypass of the parent/guardian gate for a specific person.
#
# The gate itself is User#needs_guardian? (session filter, venture activation,
# EventPolicy). An admin must be able to let one founder through without a
# real parent accept — support, demos, edge cases — without weakening the
# default for everyone else. The waiver is a named record (who, when, notes),
# not a fake guardianship: fabricating an accept would look like a parent signed.
#
# Not a permitted user attribute. Only UsersController#waive_guardian_requirement
# / #restore_guardian_requirement write these columns, and both authorize admin.
#
# The waived_by foreign key is added separately (see the follow-up migrations)
# so users does not take a blocking lock on itself.
class AddGuardianRequirementWaiverToUsers < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def change
    add_column :users, :guardian_requirement_waived_at, :datetime
    add_column :users, :guardian_requirement_waiver_notes, :text
    add_reference :users, :guardian_requirement_waived_by, null: true, index: { algorithm: :concurrently }
  end
end
