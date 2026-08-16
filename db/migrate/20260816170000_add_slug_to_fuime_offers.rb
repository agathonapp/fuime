# frozen_string_literal: true

# Fuime: the operator picks their own link.
#
# ── Correcting the previous migration ───────────────────────────────────────
#
# AddPublicTokenToFuimeOffers gave every offer a random 12-character token and
# argued the random string was the *right* public identity, because `/pay/42`
# is enumerable and an enumerable catalogue of minors' businesses with prices
# attached is a targeting list.
#
# The enumeration half of that is still true and the conclusion was too strong.
# **`/fuime_directory` already lists ventures publicly, by name.** Business
# names are not secret and were never going to be; what a sequential integer
# leaks is the *complete catalogue* and its growth rate, and a name-shaped URL
# leaks neither — you cannot walk "sunset-lawn-care" to find the next business.
#
# So the random token was solving a real problem with the wrong tool, and the
# cost was paid by the operator: `fuime.com/pay/x7Kp2mQb9rTs` is not a link a
# 16-year-old wants in their Instagram bio, and "send it and get paid" is the
# entire product.
#
# ── Slug and token, and why both survive ────────────────────────────────────
#
#   /pay/sunset-lawn-care/mow      the link they choose, share, and print
#   /pay/sunset-lawn-care/x7Kp2…   the same page, by permalink
#
# The token is kept and is **not** dead weight: a slug is renameable and a link
# already sent is not. When an operator renames "mow" to "lawn-mowing", every
# flyer, bio and Replit button carrying the old slug breaks — the token is what
# stays valid forever, so the offer keeps one identifier that cannot be taken
# away by its own owner's edit.
#
# Both are scoped under the venture's slug, so `#find_offer` resolves within one
# venture and a token from another business still cannot buy here.
class AddSlugToFuimeOffers < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def change
    add_column :fuime_offers, :slug, :string

    # Unique per VENTURE, not globally. Two businesses may both sell "mow" and
    # neither should have to find out the other got there first — the venture's
    # own slug is already the namespace, and a global constraint would make one
    # teenager's link depend on a stranger's.
    add_index :fuime_offers, [:event_id, :slug],
              unique: true,
              where: "slug IS NOT NULL",
              name: "index_fuime_offers_on_event_and_slug",
              algorithm: :concurrently
  end
end
