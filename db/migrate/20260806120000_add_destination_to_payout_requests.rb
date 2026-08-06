# frozen_string_literal: true

# Fuime: where a student's money is actually going, which is not always the same
# place and can no longer be inferred from the venture.
#
# ── The problem this solves ──────────────────────────────────────────────────
#
# CreatePayoutRequests assumed one destination: the connected account's own bank,
# reached with Stripe::Payout. That is exactly right for a family venture, because
# the account owner and the person being paid are the same guardian.
#
# It does not work inside a school programme. There the school owns one connected
# account serving every student venture beneath it (Event#payment_account), so:
#
#   * a Stripe payout from that account goes to the SCHOOL's bank, not the
#     student's, and
#   * it moves the pooled balance, which belongs to every student in the
#     programme, on one student's say-so.
#
# So a school student asking for "my money in my own bank account" is a different
# operation with a different destination, and the record has to say which.
#
# ── Why Fuime does not send that money itself ────────────────────────────────
#
# The obvious implementation — Fuime instructs Stripe to pay the student's own
# bank out of the school's balance — is not available, and the reason is worth
# writing down so nobody spends a week trying.
#
# Stripe pays out only to external accounts belonging to the account holder. A
# student's personal account is not the school's. Attaching it anyway would be
# both a Stripe violation and, in substance, Fuime directing a third party's funds
# to a stranger — the money transmission problem CLAUDE.md L1 exists to keep the
# company out of. Fuime is never in the flow of funds; that is the whole
# architecture, and it does not get an exception for a sympathetic case.
#
# What is left, and what this models, is the truthful shape: the student asks, the
# school's business office approves, THE SCHOOL PAYS THE STUDENT through the same
# process it already uses to pay anyone, and Fuime records the instruction, the
# approval, and the settlement so the venture's ledger stays right. Fuime is the
# system of record, not the payment rail.
#
# ── Why no bank details are stored ───────────────────────────────────────────
#
# `destination_note` is deliberately free text ("my Chase account", "the account
# my paycheck goes to") and there is deliberately no routing or account number
# column anywhere in this migration.
#
# A school that is going to pay a student already holds whatever details it needs
# — it enrolled them and it has an AP process. Fuime collecting a minor's bank
# credentials to hand back to the school would create a store of exactly the data
# CLAUDE.md L4 says to avoid holding, for no capability at all. If a Fuime-native
# rail ever exists, it will be a tokenized reference to an object at a processor,
# not digits in this table.
class AddDestinationToPayoutRequests < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def change
    # "account_owner_bank" is the pre-existing behaviour, so every row already in
    # the table keeps meaning what it meant.
    add_column :payout_requests, :destination, :string,
               null: false, default: "account_owner_bank"

    # What the student says they want it sent to, in their own words. Never
    # account numbers — see the header.
    add_column :payout_requests, :destination_note, :text

    # Who at the school confirmed the money actually went, and when. Separate from
    # `approved_by`/`approved_at` because approving a disbursement and having
    # completed it are different claims, made at different times, and often by
    # different people (a guide approves, the business office pays).
    #
    # Unused by the account_owner_bank path, where Stripe's own `payout.paid`
    # webhook is the authority and no human assertion is involved or wanted.
    add_reference :payout_requests, :settled_by, index: { algorithm: :concurrently }
    add_column :payout_requests, :settled_at, :datetime

    # Unvalidated here and validated in the following migration, matching
    # AddLegalEntityPayoutMethodToReimbursementReports: adding a validated foreign
    # key takes a lock that scales with the table.
    add_foreign_key :payout_requests, :users, column: :settled_by_id, validate: false

    # Only the two destinations the app implements. A CHECK constraint rather than
    # model-only validation because this column decides whether a row means "Stripe
    # moved money" or "a school owes a student money", and a typo'd third value
    # would be a row nobody can interpret.
    add_check_constraint :payout_requests,
                         "destination IN ('account_owner_bank', 'personal_transfer')",
                         name: "payout_requests_destination_known",
                         validate: false
  end
end
