# frozen_string_literal: true

# Fuime: a revoked guardianship must not block the same parent forever.
#
# `index_guardianships_on_guardian_id_and_minor_id` is UNIQUE over the pair with
# no status scope. The pair is also the natural key for "this parent, this teen",
# so once a guardianship was revoked — a parent withdrawing consent, which the
# accept page explicitly invites them to do, or an ops mis-click — that parent
# could never be invited again. The teen was told the invite "didn't go
# through", which is the one thing it had not done, and the only way back was a
# different email address for the same parent.
#
# The index is replaced rather than dropped: two LIVE guardianships for one pair
# would be a genuine bug, and the constraint that prevents it is worth keeping.
# What changes is that revoked rows no longer occupy the slot.
#
# Deliberately NOT solved by reusing the revoked row. L4 requires the consent
# record to be retained — method, timestamp, agreement version, IP — and a
# withdrawal is part of that record. Overwriting the revoked row to re-invite
# would destroy the evidence that consent was once withdrawn, which is exactly
# the fact a later dispute would turn on. So the old row stays, and a new one is
# created beside it.
class ScopeGuardianshipUniquenessToLiveRows < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  REVOKED = 2 # Guardianship.statuses[:revoked]

  def up
    add_index :guardianships, [:guardian_id, :minor_id],
              unique: true,
              where: "status <> #{REVOKED}",
              algorithm: :concurrently,
              name: "index_guardianships_on_live_guardian_and_minor"

    remove_index :guardianships,
                 name: "index_guardianships_on_guardian_id_and_minor_id",
                 algorithm: :concurrently
  end

  def down
    # Only reversible while no pair has more than one row, which is the state
    # the old index enforced. Left to fail loudly rather than silently deleting
    # a family's consent history to make room for an index.
    add_index :guardianships, [:guardian_id, :minor_id],
              unique: true,
              algorithm: :concurrently,
              name: "index_guardianships_on_guardian_id_and_minor_id"

    remove_index :guardianships,
                 name: "index_guardianships_on_live_guardian_and_minor",
                 algorithm: :concurrently
  end

end
