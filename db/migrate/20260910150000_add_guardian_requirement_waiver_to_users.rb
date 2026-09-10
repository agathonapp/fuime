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
class AddGuardianRequirementWaiverToUsers < ActiveRecord::Migration[8.0]
  def change
    add_column :users, :guardian_requirement_waived_at, :datetime
    add_column :users, :guardian_requirement_waiver_notes, :text
    add_reference :users, :guardian_requirement_waived_by, foreign_key: { to_table: :users }, index: true
  end
end
