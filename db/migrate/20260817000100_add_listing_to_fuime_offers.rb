# frozen_string_literal: true

# Fuime: separate "this is for sale" from "this is in the shop window".
#
# ── The thing that did not fit ──────────────────────────────────────────────
#
# `Fuime::Offer` models a thing a teenager sells at a price they set, and every
# published offer appears on their storefront in the order they chose. That is
# exactly right for "Lawn mow — $35", which is a standing thing the business
# offers to anybody.
#
# It is exactly wrong for the thing an operator actually needs most often: a
# price agreed with ONE customer for ONE job. "Tutoring, 90 minutes, Thursday —
# $45." Publishing that puts a stranger's specific arrangement in the shop
# window; not publishing it means there is no link to send, because
# `Fuime::PaymentPagesController` and `Fuime::CheckoutsController` both resolve
# against `published` offers only and an unpublished offer is one deliberately
# taken off sale.
#
# The two questions were conflated because until now they had the same answer.
# `listed` splits them: `published` still means "a payment through this link will
# work", `listed` means "and show it in the shop". An unlisted published offer is
# a private pay link — the operator sends the URL to the person it is for.
#
# Defaults to true so every existing offer keeps behaving exactly as it does now.
#
# ── Why this rather than a second model ─────────────────────────────────────
#
# A `Fuime::PaymentLink` model would have had to restate all of it: the price
# range constraint, the "[fuime_…]" ledger-key refusal that stops a memo
# impersonating a platform fee, `only_a_selling_venture_may_publish`, the token
# and slug resolution, the sanitized `payment_description` that reaches the
# buyer's receipt. Every one of those is a control, and a parallel model is a
# second place for them to drift out of step — which on this path means a link
# that can be paid when the venture is suspended, or a memo that reclassifies a
# child's sale as a fee on their own earnings page.
#
# ── `created_via` ───────────────────────────────────────────────────────────
#
# Whether a person made this or a program did. Not bookkeeping: an operator
# looking at a list of links needs to see which ones their agent generated while
# they were asleep, and "an API key asked for $400" is the row that should be
# easy to find. It is also what makes a runaway key legible after the fact.
class AddListingToFuimeOffers < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def change
    add_column :fuime_offers, :listed, :boolean, null: false, default: true
    add_column :fuime_offers, :created_via, :string, null: false, default: "operator"

    # The venture's shop window, which is the query the storefront runs on every
    # public page load. Partial on the two states that can appear there at all.
    add_index :fuime_offers, [:event_id, :position],
              where: "(aasm_state)::text = 'published'::text AND listed = true",
              name: "index_listed_fuime_offers_on_event_and_position",
              algorithm: :concurrently

    # Which key made what, for the operator's own list and for revoking one that
    # has gone wrong.
    add_reference :fuime_offers, :fuime_api_key,
                  null: true, index: { algorithm: :concurrently }
    add_foreign_key :fuime_offers, :fuime_api_keys, column: :fuime_api_key_id, validate: false

    # A link a program made must say which program. Enforced in the database
    # rather than only in the model because the value drives what an operator is
    # shown about their own money, and a row that arrived by console or importer
    # claiming `api` with no key behind it is a claim nobody can check.
    add_check_constraint :fuime_offers,
                         "created_via IN ('operator', 'api')",
                         name: "fuime_offers_created_via_known",
                         validate: false
    add_check_constraint :fuime_offers,
                         "created_via <> 'api' OR fuime_api_key_id IS NOT NULL",
                         name: "fuime_offers_api_offers_name_their_key",
                         validate: false
  end

end
