# frozen_string_literal: true

# Fuime: day-3 / day-6 guardian invite reminders (TEEN_GROWTH G5).
#
# The invite used to be one email and a 7-day token. Under MoR a teen can sell
# without a parent and cannot get paid until the guardianship is active, so a
# forgotten inbox is a stranded payout, not a missing signup. These columns
# record that a scheduled reminder went out, so a daily job can be idempotent
# and never re-blast an accepted, revoked, or already-reminded invite.
#
# They are NOT a second token. Reminders reuse `invite_token`. A manual
# `resend_invite!` (ops / the family) mints a new token, resets `invite_sent_at`,
# and clears these so the new 7-day window can be reminded on its own clock.
#
# The composite index is the badge query on /admin/guardianships: pending rows
# whose invite is older than 7 days. ADMIN_OPS_QUEUES.md §3 asked for that to
# be a single indexed count.
class AddInviteReminderTimestampsToGuardianships < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def change
    add_column :guardianships, :invite_day3_reminded_at, :datetime
    add_column :guardianships, :invite_day6_reminded_at, :datetime

    add_index :guardianships, [:status, :invite_sent_at],
              algorithm: :concurrently,
              name: "index_guardianships_on_status_and_invite_sent_at"
  end
end
