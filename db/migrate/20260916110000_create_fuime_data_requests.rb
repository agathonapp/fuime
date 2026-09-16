# frozen_string_literal: true

# Fuime: a parent exercising a data right over their child's account.
#
# COPPA gives a parent the right to review what is held about their child and to
# have it deleted (16 CFR 312.6; CLAUDE.md L4/L6). Fuime had neither mechanism —
# a parent asking would have been answered by hand, or not at all, which is not
# a posture that survives a public launch.
#
# Both kinds are recorded, not only deletions. An export is served immediately
# and needs no queue, but the row is the proof it was served — which is the
# thing a regulator asks for and the thing nobody can reconstruct later.
class CreateFuimeDataRequests < ActiveRecord::Migration[7.2]
  def change
    create_table :fuime_data_requests do |t|
      # Who asked. Always an adult: a minor cannot make this request about
      # themselves, because the right COPPA creates belongs to the parent.
      t.references :requested_by, null: false, foreign_key: { to_table: :users }
      # Whose data. Usually the ward; the guardian may also ask about their own.
      t.references :subject, null: false, foreign_key: { to_table: :users }

      t.integer :kind, null: false
      t.integer :status, null: false, default: 0

      # What the parent said, and what Fuime did. Free text on both sides
      # because the interesting cases are the ones a dropdown would flatten.
      t.text :reason
      t.text :resolution_notes

      t.datetime :requested_at, null: false
      t.datetime :fulfilled_at
      t.references :fulfilled_by, foreign_key: { to_table: :users }

      # Recorded for the same reason Guardianship records them at signature: a
      # deletion request is an instruction with legal effect and "who asked,
      # from where" is the whole audit trail.
      t.string :request_ip
      t.string :request_user_agent

      t.timestamps
    end

    add_index :fuime_data_requests, [:status, :requested_at]
    add_index :fuime_data_requests, [:subject_id, :kind]
  end
end
