# frozen_string_literal: true

# Fuime: a thing a teenager sells, at a price they set.
#
# ── Why this is the missing object ──────────────────────────────────────────
#
# Until now a venture's storefront showed a name, a tagline and a box where a
# stranger typed any amount they liked. That is a tip jar. It works for a
# donation and it does not work for a business: the buyer has to already know
# what they are buying and what it costs, which means the operator has told them
# somewhere else and the storefront is only collecting.
#
# An offer is the object that makes the storefront a store — "Lawn mow, front and
# back — $35" — and it is the same shape as the offer/product object at the
# centre of every platform of this kind. Everything downstream already works:
# `Fuime::PaymentLinkService` takes an amount and a description, the webhook
# posts to the ledger, `Fuime::PayablesLedger` explains it, and phase 6's batches
# pay it out. This is the piece that was missing at the front.
#
# ── The price is the operator's, and this schema is deliberate about it ─────
#
# `price_cents` is **not nullable and has no default**, and nothing in Fuime ever
# writes it except the operator. That is not fussiness — MOR_MIGRATION_PLAN §8.3
# D2's mitigation for worker misclassification is that *"operators must control
# their own pricing, clients, and hours. We never route work to them or set
# rates."* A default price would be a Fuime-set rate for every operator who never
# changed it, and a suggested one is a set rate with a softer verb.
#
# The same reasoning is why there is no `suggested_price_cents`, no
# `category_average_cents`, and no column that would let a future "price your
# work" feature quietly become Fuime quoting. `Fuime::ServiceCatalog` already
# carries this constraint for templates; this is the same rule at the schema
# level, where it is harder to talk yourself out of.
#
# ── Why `unit_label` is free text rather than an enum ───────────────────────
#
# "per lawn", "per hour", "per session", "per 30-minute lesson", "per dog, per
# walk". The unit is part of how a teenager describes their own work, and an enum
# would be Fuime deciding which shapes of business are expressible. A tutor
# charging per session and a dog walker charging per dog are both selling
# something Fuime should be able to render without a migration.
#
# ── What an offer is NOT ───────────────────────────────────────────────────
#
# Not inventory, and deliberately so. There is no stock count, no fulfilment
# state and no shipping — Phase 1 is services-only (§8.3 D3), and a service does
# not run out. When physical goods open, that is a different object with a
# different set of obligations (sales-tax nexus, product liability), not three
# more columns on this one.
class CreateFuimeOffers < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def change
    create_table :fuime_offers do |t|
      t.references :event, null: false, index: { algorithm: :concurrently }

      t.string :name, null: false
      t.text :description

      # Set by the operator, always. See the header.
      t.integer :price_cents, null: false

      # "per lawn", "per hour", "per session". Free text — see the header.
      t.string :unit_label

      # draft | published | archived.
      #
      # Archived rather than deleted: an offer that was bought is referenced by
      # ledger lines and by a buyer's receipt, and deleting it would leave a
      # payment nobody can explain. Same reasoning as PayoutRequest lines being
      # rejected rather than removed when a run is cancelled.
      t.string :aasm_state, null: false, default: "draft"

      # Operator-chosen ordering on the storefront.
      #
      # Operator-chosen, and that word is doing work: MOR_MIGRATION_PLAN §8.3 D2
      # requires neutral ordering wherever Fuime ranks anything, and the
      # directory already ships that way. Inside a single operator's OWN
      # storefront the constraint does not apply — an operator arranging their
      # own shop is not Fuime ranking operators — but the column is theirs to set
      # and Fuime never computes it.
      t.integer :position, null: false, default: 0

      t.timestamps
    end

    add_foreign_key :fuime_offers, :events, validate: false

    add_check_constraint :fuime_offers,
                         "aasm_state IN ('draft', 'published', 'archived')",
                         name: "fuime_offers_state_known",
                         validate: false

    # A price of zero is a free thing, which is not a sale and would produce a
    # Stripe session for nothing. The upper bound matches
    # Fuime::CheckoutsController::MAXIMUM_AMOUNT_CENTS — a teenager's service
    # priced above $10,000 is a data-entry error far more often than it is a
    # real offer, and the ceiling is where somebody notices.
    add_check_constraint :fuime_offers,
                         "price_cents > 0 AND price_cents <= 1000000",
                         name: "fuime_offers_price_in_range",
                         validate: false

    # The storefront's query: this venture's published offers, in the operator's
    # own order.
    add_index :fuime_offers, [:event_id, :position],
              where: "aasm_state = 'published'",
              name: "index_published_fuime_offers_on_event_and_position",
              algorithm: :concurrently
  end
end
