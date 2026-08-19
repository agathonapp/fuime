# frozen_string_literal: true

# Fuime: a key a venture hands to a program, so software can sell on its behalf.
#
# ── Why not the API token that already exists ───────────────────────────────
#
# `ApiToken` is Doorkeeper's OAuth access token: it belongs to a USER, it is
# minted through an authorization-code flow, and it needs a registered OAuth
# application behind it. That is the right shape for "another product acts as
# Rushil across everything Rushil can reach", and the wrong shape for every
# property this needs:
#
#   * scope — an OAuth token carries the user's whole account. A teenager pasting
#     a key into a chatbot, a Replit project or an agent framework is pasting it
#     somewhere they do not control, and the blast radius has to be ONE venture's
#     ability to ask for money. So this belongs to an Event, not a User.
#   * ceremony — a 16-year-old wiring an agent into their business at a weekend
#     event is not going to register an OAuth application. Copy a key, paste a
#     key.
#   * revocation — keys leak, and the answer has to be one button next to the key
#     rather than an OAuth grant screen somewhere else.
#
# ── The key is never stored ─────────────────────────────────────────────────
#
# Same construction as ApiToken and Fuime::PayoutMethod's access token: a Lockbox
# `_ciphertext` column plus a blind index for lookup. The plaintext is returned
# exactly once, at creation, and after that not even an admin can read it back —
# a support path that can recite a venture's live key is a support path that can
# be socially engineered into reciting it to the wrong person.
#
# ── What a key can do, and what it deliberately cannot ──────────────────────
#
# It can ask for money on behalf of its venture: create a pay link, list them,
# revoke them. That is the whole surface.
#
# It cannot move money OUT, read the ledger, see the operator's or their
# guardian's personal details, or touch any other venture. Those omissions are
# the point. The threat model here is not a hostile teenager — it is an agent
# behaving unpredictably with a key that got pasted into a prompt, and the
# correct blast radius for that is "issued a payment request somebody can ignore."
class CreateFuimeApiKeys < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def change
    create_table :fuime_api_keys do |t|
      t.references :event, null: false, index: { algorithm: :concurrently }

      # Who minted it. A key is an authority to ask for money in the venture's
      # name, so "who issued this" is the first question when one misbehaves —
      # same reasoning as Fuime::PayoutMethod#added_by.
      t.references :created_by, null: false, index: { algorithm: :concurrently }

      # The operator's own label — "my website bot", "Claude". Purely so a list of
      # three keys is legible enough to revoke the right one.
      t.string :name, null: false

      # Lockbox. There is no plaintext column, deliberately; see the header.
      t.text :token_ciphertext, null: false
      # Blind index, for looking a presented key up without decrypting the table.
      t.string :token_bidx, null: false

      # Last 4 of the plaintext, for display only ("fuime_sk_••••a9f2"). Four
      # characters of a 32-byte random token is not a meaningful head start on
      # guessing it, and without it a revoke screen cannot tell two keys apart.
      t.string :last4, null: false

      # Observability an operator can act on. "This key was last used an hour ago"
      # is what tells a teenager whether the key they are about to revoke is the
      # one their site is using.
      t.datetime :last_used_at
      t.integer :request_count, null: false, default: 0

      t.datetime :revoked_at

      t.timestamps
    end

    add_index :fuime_api_keys, :token_bidx, unique: true, algorithm: :concurrently
    add_foreign_key :fuime_api_keys, :events, validate: false
    add_foreign_key :fuime_api_keys, :users, column: :created_by_id, validate: false
  end

end
