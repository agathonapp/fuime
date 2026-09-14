# frozen_string_literal: true

# Fuime: what the admin actually sent, recorded alongside the claim that they sent it.
#
# `Fuime::PayoutBatchService#mark_paid!` debits every operator's ledger — it is
# the only thing in the system that does. But it moves no money: there is no
# Stripe::Payout, no Stripe::Transfer and no ACH originator behind it
# (STRIPE_FEATURE_AUDIT.md §4.3). The money is sent by a human, from a bank,
# outside this app.
#
# That is a legitimate way to run payouts at this volume. What was not legitimate
# is that the app took the human's word for it with nothing but a confirm dialog,
# so a misclick produced an operator ledger reading "paid" against a transfer
# that never happened — and no record anywhere of what was supposed to have been
# sent. The operator sees their payable go to zero either way.
#
# So the assertion now has to carry evidence: a bank reference, a wire
# confirmation, whatever the sending institution issued. Not validated for shape
# — Fuime does not know what a given bank's reference looks like, and a format
# rule would only teach people to type around it. Requiring somebody to go and
# find the reference is the control; the string is the audit trail.
#
# Nullable because the rows that exist predate the requirement. New rows cannot
# reach `paid` without one — that gate is in the service, where the state change
# happens, rather than a NOT NULL that would also block a draft.
class AddTransferReferenceToFuimePayoutBatches < ActiveRecord::Migration[8.1]
  def change
    add_column :fuime_payout_batches, :transfer_reference, :string
  end

end
