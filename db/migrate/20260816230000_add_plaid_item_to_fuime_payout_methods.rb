# frozen_string_literal: true

# Fuime: the two things a Plaid connection needs that `provider_reference`
# cannot hold on its own.
#
# ── Why one reference column was not enough ─────────────────────────────────
#
# Plaid addresses a connected account with a PAIR: an `access_token` (the Item —
# one login at one bank) and an `account_id` (which account inside it). Later,
# when §4.3's originator question is answered, turning this destination into
# something that can actually be paid is `/processor/token/create`, and that call
# takes both. Storing only one of them would mean every operator re-linking their
# bank on the day Fuime picks a rail, which is the most expensive kind of
# avoidable migration: it needs a human at the other end of it.
#
# So `provider_reference` now holds the Plaid **item_id** — the non-secret,
# stable identifier you quote to Plaid support and see in their dashboard — and
# the pair lives in the two columns added here.
#
# ── The access token is a secret, and is stored like one ────────────────────
#
# CreateFuimePayoutMethods promised no bank credential lands in this table, and
# that promise is about account and routing NUMBERS: the digits that let anyone
# who has them pull money. A Plaid access token is not those digits — it is a
# revocable, scoped handle to an Item, which is exactly the "tokenized reference
# to an object at a processor" that migration described.
#
# But it is not nothing either: with the `auth` product on the Item, whoever
# holds this token can ASK Plaid for the numbers. So it is encrypted at rest
# through Lockbox rather than stored in the clear — the same treatment upstream
# gives `BankAccount#plaid_access_token`, and one step stronger than the
# guarantee the table was written to make.
#
# Fuime itself never makes that call. `/auth/get` appears nowhere in this
# codebase and Fuime::PlaidLinkService is written so that reading the numbers is
# not a thing it can accidentally do. The `auth` product is requested at Link
# time purely so the Item is CAPABLE of being handed to an originator later; the
# capability is Plaid's to exercise on the originator's behalf, not Fuime's to
# hold in a column.
class AddPlaidItemToFuimePayoutMethods < ActiveRecord::Migration[8.0]
  def change
    # `safety_assured`: strong_migrations cannot see inside a change_table block,
    # so it refuses rather than guesses. What is inside is two ADD COLUMNs with no
    # default and no NOT NULL — the one column operation Postgres does as a
    # metadata-only catalogue update, taking no table rewrite and holding
    # ACCESS EXCLUSIVE only for an instant. `bulk: true` is what makes it a single
    # ALTER TABLE rather than two.
    safety_assured do
      change_table :fuime_payout_methods, bulk: true do |t|
        # Which account inside the Item. Opaque and alphanumeric — never digits,
        # and the model's account-number validation covers it for the same reason
        # it covers `provider_reference`.
        t.string :provider_account_id

        # Lockbox ciphertext. See the header: encrypted because the plaintext
        # could be exchanged for the numbers this table exists not to hold.
        t.text :provider_access_token_ciphertext
      end
    end
  end

end
