# frozen_string_literal: true

# Fuime: record which account-configuration profile a venture was created under.
#
# ── Why this has to be stored at all ────────────────────────────────────────
#
# Stripe's `controller` property is **create-only**. The Account *update* endpoint
# accepts no `controller` parameters, and Stripe states plainly that a platform
# which needs different controller properties "must create new accounts to use
# Issuing or Treasury for platforms." So the choice made at
# `Stripe::Account.create` time is permanent for the life of that account, and a
# venture cannot be upgraded into card support later. It must be re-onboarded from
# scratch.
#
# That makes "which profile is this account on?" a question with real consequences
# that Fuime has to be able to answer without guessing:
#
#   * whether this venture can ever have a card;
#   * whether Fuime or Stripe absorbs a negative balance on it;
#   * whether the guardian's SSN and ID documents are in Fuime's systems;
#   * who pays Stripe's processing fees on its charges.
#
# All four differ between the two profiles, and all four are things support and
# finance need to look up per venture rather than infer from a global setting.
#
# ── Two columns, deliberately: intent and reality ───────────────────────────
#
# `controller_profile` is what Fuime ASKED FOR. It is written before the Stripe
# call (same reasoning as the nullable `stripe_id`: a crash mid-create must leave a
# retryable row, and the retry has to request the same profile or it would silently
# create the wrong kind of account).
#
# `controller` is what Stripe ACTUALLY DID, mirrored verbatim from the Account
# object like every other Stripe field on this table. It exists because the
# mixed-fleet approach this enables is an INFERENCE, not a documented Stripe
# pattern: `controller` is a per-account property, so in principle a platform can
# default to Stripe-liability and create only card-cohort ventures with
# `application`. Whether Stripe's "platforms under Stripe-liability cannot use
# Issuing" restriction is platform-wide or per-account is ambiguous in the docs
# (docs/fuime/LEGAL_RESEARCH.md, "The option worth asking Stripe about").
#
# If that inference is wrong, Stripe will either reject the create or quietly
# return an account configured differently from what was requested. Storing both
# sides means StripeConnectedAccount can detect the disagreement and refuse to tell
# a family they can have a card, instead of finding out at card-creation time.
class AddControllerProfileToStripeConnectedAccounts < ActiveRecord::Migration[8.0]
  # Adding an index to an existing table takes an ACCESS EXCLUSIVE lock unless it
  # is built concurrently, which strong_migrations enforces. Same shape as
  # db/migrate/20251115104532_add_event_tags_index_by_name.rb.
  disable_ddl_transaction!

  def change
    # Not null with a default so every existing row is correctly labelled: every
    # account created before this migration used the Stripe-liable configuration.
    add_column :stripe_connected_accounts, :controller_profile, :string,
               null: false, default: "payments_only"

    # Mirrored from Stripe's Account#controller. jsonb rather than columns because
    # the shape is Stripe's and they add sub-properties over time.
    add_column :stripe_connected_accounts, :controller, :jsonb,
               null: false, default: {}

    # Partial: card-cohort accounts are expected to be the minority for a long
    # time, and this is the index behind "which families are on the liability-
    # bearing profile?" — a question finance will ask before it is a large number.
    add_index :stripe_connected_accounts, :controller_profile,
              where: "controller_profile <> 'payments_only'",
              name: "index_stripe_connected_accounts_on_non_default_profile",
              algorithm: :concurrently
  end
end
