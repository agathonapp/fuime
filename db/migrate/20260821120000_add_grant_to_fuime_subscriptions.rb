# frozen_string_literal: true

# Fuime: let an admin comp the family plan, and record who did it.
#
# ── Why this is needed ───────────────────────────────────────────────────────
#
# `Fuime::Subscription` had exactly one writer: Stripe. A row was created by
# `Fuime::SubscriptionService#checkout_session` and its status only ever moved
# when `Fuime::SubscriptionWebhookHandler` mirrored an event back. That is the
# right default — the model is a mirror, and ADMIN_OPS_QUEUES.md §4 says so — but
# it left no way at all to give somebody the plan. Comping a founder, a school
# partner, or a demo account meant opening a Rails console, and the console
# leaves no record of who decided or why.
#
# ── Why three columns rather than a boolean ──────────────────────────────────
#
# A comped family plan is Fuime giving away $19.99/month of its own revenue, and
# the thing that has to be reconstructable later is *who decided, when, and why*
# — the same argument as `Event#record_vetting_decision!`, which is why the shape
# matches it. `granted_by_id` present is also what distinguishes a comp from a
# paying subscriber, which is the distinction every admin action here has to
# respect: a Stripe-backed row must never be edited locally (the mirror would
# then disagree with the account that is actually being charged), while a comp
# has no Stripe side to disagree with.
#
# paper_trail is added on the model at the same time, so a later status change is
# attributable even when it arrives from a webhook.
class AddGrantToFuimeSubscriptions < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def change
    add_column :fuime_subscriptions, :granted_at, :datetime
    add_column :fuime_subscriptions, :grant_notes, :text

    # Reference and foreign key added separately, and the index built
    # concurrently: strong_migrations refuses the combined form because a
    # concurrent index and an ALTER TABLE ... ADD CONSTRAINT cannot share a
    # transaction. Same split as AddSaleTermsAcknowledgementToEvents.
    add_reference :fuime_subscriptions, :granted_by,
                  null: true,
                  index: { algorithm: :concurrently }

    # NOT VALID: a validated FK locks both tables. Nothing can violate it — the
    # column is new and null everywhere.
    add_foreign_key :fuime_subscriptions, :users,
                    column: :granted_by_id,
                    validate: false
  end
end
