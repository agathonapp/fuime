# frozen_string_literal: true

# Fuime: who gets told when something happens.
#
# ── Why this is a table and not an environment variable ─────────────────────
#
# It was an environment variable — `FUIME_OPS_EMAIL`, read by
# `ApplicationMailer.ops_recipients` — and every property of that arrangement
# worked against the thing it was for:
#
#   * It was never set, so every operational alert went to `support@fuime.com`,
#     which is a shared inbox and not a person who is awake.
#   * It has to be set on BOTH the web service and the worker, because the
#     alerts are `deliver_later` and it is the worker that reads the variable.
#     Setting one of the two looks exactly like setting both.
#   * Nothing in the app can show you its value, so "am I being alerted?" is a
#     question you can only answer by breaking something and waiting.
#
# That is the same shape as the bug closed on 2026-09-16, where AdminMailer
# addressed Hack Club's credential and `deliver_mail` dropped the message
# without a word. An alert route that fails silently is worse than none, because
# it is believed.
#
# A row is visible, editable at 3am from a phone without a deploy, and can be
# asked "did this page actually land?" — see fuime_incident_notifications.
#
# ── user_id is nullable on purpose ──────────────────────────────────────────
#
# The previous `AdminMailer#engineers` required each address to resolve to a
# `User`, which meant an on-call engineer with no account on the platform they
# operate received nothing. Contractors, a co-founder's personal phone, and a
# shared escalation number are all legitimate and none of them is a user.
class CreateFuimeOncallResponders < ActiveRecord::Migration[7.2]
  def change
    create_table :fuime_oncall_responders do |t|
      t.references :user, null: true, foreign_key: true

      t.string :name, null: false
      t.string :email

      # E.164. Used for SMS and, at sev-1, for a voice call — the only channel
      # that reliably defeats a silent phone.
      t.string :phone_number

      # The "alarm ping": one HTTP POST to a push relay. `push_kind` selects the
      # payload shape (ntfy, Pushover, Slack, generic JSON) because each of them
      # spells priority differently and priority is the entire point — a normal
      # notification is suppressed by Do Not Disturb, and a page that arrives
      # silently at 3am is not a page.
      t.string :push_kind
      t.string :push_url
      # Pushover wants a user key alongside the app token; ntfy may want a bearer
      # token for a private topic. Encrypted: it is a credential, and alert
      # routing is not a place to start leaking them.
      t.text :push_credential_ciphertext

      # Ascending. Position 1 is paged first; the next position is only woken if
      # nobody acknowledges within the escalation window.
      t.integer :escalation_position, null: false, default: 1

      # Separate switches because they are different appetites. A founder wants
      # every page; an accountant wants the 6am digest and nothing at 3am.
      t.boolean :receives_pages, null: false, default: true
      t.boolean :receives_digest, null: false, default: true
      t.boolean :active, null: false, default: true

      t.timestamps
    end

    add_index :fuime_oncall_responders, [:active, :escalation_position]
  end
end
