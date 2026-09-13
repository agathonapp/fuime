# frozen_string_literal: true

# Fuime: who started this guardianship — the minor, or the guardian.
#
# Until the family setup wizard there was one answer: a teen invited their
# parent, so `invite_sent_at` was always stamped at creation and "accepted
# quickly" meant something. A parent who sets the family up themselves creates
# and accepts the same row in one request, which would put every parent-first
# family on the payout reviewer's self-signed list
# (`Guardianship#accepted_suspiciously_fast?`, FAST_ACCEPTANCE = 2 minutes) —
# a fraud signal that would fire on the ordinary case and drown the real ones.
#
# It also decides one mail: `GuardianshipMailer#accepted` tells a teen their
# invitation was accepted, which is nonsense sent to a teen who never sent one.
#
# Additive and defaulted: every existing row is minor-initiated, which is what
# every existing row is. No backfill.
class AddInitiatedByToGuardianships < ActiveRecord::Migration[8.1]
  def change
    add_column :guardianships, :initiated_by, :integer, default: 0, null: false
  end

end
