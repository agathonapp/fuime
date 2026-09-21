# frozen_string_literal: true

# Fuime: proof that a page was actually delivered, or the reason it wasn't.
#
# This table exists because of a specific, repeated failure in this codebase:
# alerts that went nowhere and said nothing about it. `AdminMailer` was addressed
# to a credential that was never set; `ApplicationMailer.deliver_mail` returns
# early on an empty recipient list without raising; `EARMUFFED_USER_IDS` silently
# subtracted real users from every recipient list. In all three the alerting
# system reported perfect health precisely because it was doing nothing.
#
# An alerting system that cannot be audited is a belief, not a control. So every
# attempt to reach a human is written down: which channel, which responder, what
# the far end said. Two questions become answerable without an experiment —
# "did last night's page reach me?" and "is my push relay still alive?" — and
# the second one is answerable BEFORE the outage that depends on it.
#
# Deliberately not stored here: the incident detail. The body that goes to a push
# relay is content-free by design (see Fuime::Oncall::Pager), and this row should
# not become the copy of it that a relay never had.
class CreateFuimeIncidentNotifications < ActiveRecord::Migration[7.2]
  def change
    create_table :fuime_incident_notifications do |t|
      t.references :incident, null: false,
                              foreign_key: { to_table: :fuime_incidents },
                              index: false
      t.references :responder, null: true,
                               foreign_key: { to_table: :fuime_oncall_responders }

      t.string :channel, null: false           # push | sms | voice | email
      # Where it was sent, redacted for display (e.g. "+1••••••1234"). The full
      # destination is on the responder row; duplicating it here would spread a
      # phone number across a table that exists to be read casually.
      t.string :target_redacted

      t.integer :status, null: false, default: 0 # sent | delivered | failed
      t.string :response_code
      t.text :error

      t.datetime :attempted_at, null: false

      t.timestamps
    end

    add_index :fuime_incident_notifications, [:incident_id, :attempted_at]
  end
end
