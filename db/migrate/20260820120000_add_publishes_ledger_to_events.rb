# frozen_string_literal: true

# Fuime: split "my storefront is public" from "my ledger is public".
#
# ── The bug this closes ──────────────────────────────────────────────────────
#
# `is_public` is HCB's transparency flag, and in HCB it means one thing because a
# fiscally-sponsored nonprofit publishing its books IS the product. Fuime
# inherited the column and then reused it for something else: the Fuime UI labels
# it "Show my storefront publicly" (app/views/fuime/offers/index.html.erb), and
# `EventService::Create` sets it to true for every venture.
#
# `EventPolicy#show?` was `is_public || auditor_or_reader?`, with
# `transactions?`, `transactions_list?`, `team?`, `balance_transactions?`,
# `money_movement?`, `users_chart?`, `stats?` and `balance_by_date?` all aliased to
# or copying it. So a 16-year-old ticking a box labelled "show my storefront"
# published, to anyone holding their slug:
#
#   * every sale — amount, date, and the buyer-typed payment description
#   * the running balance
#   * the names and profile pictures of the minors who run the venture
#
# The storefront itself takes deliberate care about exactly this: it hides the
# owner's name unless the owner is a confirmed adult and never prints the exact
# balance, "because a minor's first name plus a live balance plus a transaction
# history is a targeting profile". One path segment away, all three were public.
# CLAUDE.md L7.
#
# ── Why a new column rather than defaulting is_public to false ───────────────
#
# Because `is_public` is load-bearing for the storefront now.
# `Fuime::StorefrontsController` and `Fuime::CheckoutsController` both refuse
# unless `event.is_public`, and `Event.indexable` drives the directory. Flipping it
# false would take every venture's shop window down along with its ledger — a
# worse outage than the leak, on launch week.
#
# So the two meanings get two columns. `is_public` keeps the meaning its label
# already claims (the storefront is public), and this one carries the meaning that
# was riding along on it.
#
# ── Why it exists at all, rather than deleting transparency ──────────────────
#
# CLAUDE.md Rule 2, and Milestone 5 lists transparency mode as a module to keep
# alive. A venture that genuinely wants to publish its books — a school programme
# demonstrating where its money went, say — can still do it. It just has to say so,
# and saying so is now a separate act from opening a shop.
#
# Default false, `null: false`: existing rows are the population the leak applied
# to, and "not answered" has to mean private for them, not "keep publishing".
class AddPublishesLedgerToEvents < ActiveRecord::Migration[8.0]
  def change
    add_column :events, :publishes_ledger, :boolean, default: false, null: false
  end
end
