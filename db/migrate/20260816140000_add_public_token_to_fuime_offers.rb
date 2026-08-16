# frozen_string_literal: true

# Fuime: a link a teenager can paste anywhere and get paid through.
#
# ── The thing this unlocks ──────────────────────────────────────────────────
#
# A 16-year-old building a site on Replit, posting on Instagram, or sending a DM
# does not want to send someone to a storefront and hope they find the right
# button. They want one URL for one thing they sell: send it, get paid. That is
# the shape Stripe Payment Links have, and it is the missing half of the public
# side — the storefront is where a customer *browses*, and this is what an
# operator *sends*.
#
# ── Why a token and not the id ──────────────────────────────────────────────
#
# `/pay/42` is enumerable. Anybody could walk the integers and read the name,
# description and price of **every offer on the platform**, including drafts if
# the scoping were ever loosened, and infer how many businesses exist and how
# fast they are being created. None of that is catastrophic on its own; all of it
# is free to an attacker and free to prevent.
#
# It matters more here than it would elsewhere because these are minors' businesses.
# An enumerable list of teen-run ventures with prices attached is a targeting
# list, and `Event#selling_blockers`' whole design note is about not handing
# strangers a profile of a child. The same instinct applies to the catalogue.
#
# `SecureRandom.alphanumeric(12)` — 62^12, generated in Ruby rather than by a
# database default so the model owns it and a fixture, a console or an importer
# all get one.
#
# ── Why the column is nullable ──────────────────────────────────────────────
#
# Offers created before this migration have none, and backfilling inside a
# migration means generating unique random values in a loop against a table that
# is being written to. The model generates one on create and
# `Fuime::Offer#public_token!` fills it in lazily for anything older, which is
# also the behaviour a future importer gets for free. The unique index tolerates
# nulls, so the constraint that matters — no two offers share a token — holds
# from the first row.
class AddPublicTokenToFuimeOffers < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def change
    add_column :fuime_offers, :public_token, :string

    add_index :fuime_offers, :public_token,
              unique: true,
              where: "public_token IS NOT NULL",
              algorithm: :concurrently
  end
end
