# frozen_string_literal: true

# Fuime: something is broken, and here is whether anyone has picked it up.
#
# ── Why an incident is a row and not just an email ──────────────────────────
#
# Every operational alert in this app has been a mail send: a detector notices
# something, sends a message, and forgets. That has three consequences that only
# show up when it matters.
#
#   * **No deduplication.** A detector on a 5-minute schedule finding the same
#     broken thing sends 288 identical mails a day. The reader builds a filter
#     rule, and the filter rule is still there for the next, different outage.
#   * **No acknowledgement.** Nothing distinguishes "seen, I am on it" from
#     "nobody has opened their laptop", so the only escalation policy available
#     is to send more mail to the same person.
#   * **No memory.** After the fact there is no answer to "when did this start,
#     when did we notice, how long were families affected" — which is exactly
#     what a chargeback representment, a COPPA response, or a Stripe review asks
#     for in writing.
#
# A row fixes all three, and costs one insert per genuine incident.
#
# ── `key` is the identity of the PROBLEM, not of the occurrence ─────────────
#
# `sidekiq.dead_set` is one incident however many times the detector runs.
# Re-detection touches the existing open row; it does not create another. The
# partial unique index makes that a database guarantee rather than a convention
# somebody remembers, because the code path that violates it is the one running
# unattended at 3am.
class CreateFuimeIncidents < ActiveRecord::Migration[7.2]
  def change
    create_table :fuime_incidents do |t|
      # Stable identity of the failure, e.g. "sidekiq.dead_set",
      # "stripe.unreachable", "money_in.silent".
      t.string :key, null: false
      # Which detector raised it. Kept separately from `key` because one detector
      # can raise per-subject keys (a stuck payout batch is one incident per run).
      t.string :check_name, null: false

      t.integer :severity, null: false, default: 1
      t.integer :status, null: false, default: 0

      t.string :title, null: false
      # What the detector saw, as structured data. Renders on the admin page and
      # is the whole post-mortem record; deliberately NOT sent in the page body
      # (see Fuime::Oncall::Pager).
      t.jsonb :detail, null: false, default: {}

      t.datetime :opened_at, null: false
      t.datetime :acknowledged_at
      t.references :acknowledged_by, foreign_key: { to_table: :users }
      t.datetime :resolved_at

      # True when the detector stopped seeing the problem rather than a human
      # closing it. Worth distinguishing: a flapping check that auto-resolves
      # twenty times is itself the incident.
      t.boolean :auto_resolved, null: false, default: false

      # Escalation bookkeeping. `escalation_position` is how far up the roster
      # this has climbed; nobody is woken twice for the same rung.
      t.datetime :last_paged_at
      t.integer :page_count, null: false, default: 0
      t.integer :escalation_position, null: false, default: 0

      # One-tap acknowledgement from the notification itself. A page that can
      # only be acked by finding a laptop, signing in and navigating to an admin
      # page will not be acked — it will be silenced.
      t.string :ack_token, null: false

      t.timestamps
    end

    # One open incident per problem. Partial, so the history of resolved
    # incidents with the same key is kept in full.
    add_index :fuime_incidents, :key, unique: true, where: "resolved_at IS NULL",
                                      name: "index_fuime_incidents_one_open_per_key"
    add_index :fuime_incidents, :ack_token, unique: true
    add_index :fuime_incidents, [:status, :severity, :opened_at]
  end
end
