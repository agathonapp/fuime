# frozen_string_literal: true

# Fuime: cards on a venture's OWN Stripe account, with the guardian as the
# Accountholder and the teen as an Authorized User.
#
# ── Why not reuse HCB's stripe_cardholders / stripe_cards ────────────────────
#
# Those are PLATFORM-level Issuing: one shared Issuing balance topped up by
# `topup_stripe_job.rb`, with HCB approving each swipe against its own subledger.
# That works because a 501(c)(3) legally owns the funds as restricted charitable
# funds (CLAUDE.md, "What Fuime is"). A for-profit cannot copy it, and Rule 3
# forbids reaching into that pipeline. These are separate tables holding
# CONNECTED-ACCOUNT Issuing objects, where every Stripe call carries
# `stripe_account:` and the card is issued against the family's own balance.
#
# ── The legal structure, expressed as columns ───────────────────────────────
#
# Stripe's Issuing cardholder floor is 13, and Celtic Bank's Authorized User Terms
# carry no minimum age at all. What makes the arrangement legitimate is not the
# child's age — it is WHO HOLDS WHICH ROLE and that each accepted the right terms:
#
#   * the guardian is the ACCOUNTHOLDER, who accepts the Accountholder Terms and is
#     the party liable for the card;
#   * the minor is an AUTHORIZED USER, who accepts the Authorized User Terms and
#     holds an access device.
#
# That is the same structure every kid-money product settles on (parent is the
# accountholder, child holds the device — see the market table in
# LEGAL_RESEARCH.md, correlation 1.0), and it is disclosed to Stripe rather than
# hidden from it. So `role` is not descriptive metadata; it is the thing being
# asserted, and a minor must never hold `accountholder`.
#
# `terms_accepted_at` / `terms_version` exist because an unaccepted set of terms
# means there is no authorized user, only someone holding a card. The issuing
# service refuses without them.
class CreateVentureCardholdersAndCards < ActiveRecord::Migration[8.0]
  def change
    create_table :venture_cardholders do |t|
      t.references :event, null: false, foreign_key: true

      # The human. Not `owner`/`minor` — this table holds both roles and naming it
      # by role in the column would contradict the `role` column below.
      t.references :user, null: false, foreign_key: true

      # "accountholder" (the guardian) or "authorized_user" (the teen). See the
      # class comment: this is a legal assertion, not a label.
      t.string :role, null: false

      # ich_… . Nullable for the same reason StripeConnectedAccount#stripe_id is:
      # the row is written before the Stripe call so a crash cannot orphan a
      # cardholder Fuime has no record of.
      t.text :stripe_id

      # Which version of the terms this person accepted, and when. A card cannot be
      # issued to a cardholder without both.
      t.datetime :terms_accepted_at
      t.string :terms_version

      # Recorded alongside the acceptance for the same reason Guardianship records
      # them: an acceptance with no provenance is difficult to stand behind later.
      t.string :terms_accepted_ip
      t.text :terms_accepted_user_agent

      # Mirrored from Stripe: "active" | "inactive" | "blocked". Stripe owns this.
      t.string :status
      t.jsonb :requirements, null: false, default: {}
      t.datetime :stripe_synced_at

      t.timestamps
    end

    # One cardholder per person per venture. A second Stripe Cardholder for the
    # same human on the same venture would split their card history in two.
    add_index :venture_cardholders, %i[event_id user_id], unique: true

    add_index :venture_cardholders, :stripe_id,
              unique: true, where: "stripe_id IS NOT NULL"

    create_table :venture_cards do |t|
      t.references :venture_cardholder, null: false, foreign_key: true

      # ic_… . Nullable, same create-then-call ordering as above.
      t.text :stripe_id

      # "virtual" or "physical". Virtual only for now — a physical card mailed to a
      # minor raises questions (delivery address, who signs for it) that are not
      # answered yet.
      t.string :card_type, null: false, default: "virtual"

      # Display fields mirrored from Stripe. Never the full number, which Fuime
      # neither receives nor stores.
      t.string :last4
      t.string :brand
      t.integer :exp_month
      t.integer :exp_year

      # Mirrored: "active" | "inactive" | "canceled".
      t.string :status

      # The guardian's limit, mirrored back from what Stripe has. Stored so the
      # limit can be shown without a network call on every render, and so a
      # disagreement with Stripe is visible.
      t.integer :spending_limit_cents
      t.string :spending_limit_interval

      # Whether this card carries Fuime's commercial-purpose category allowlist.
      # Recorded per card rather than assumed globally: a card issued before the
      # policy existed, or one Stripe returned without the controls applied, must be
      # distinguishable from a card that is genuinely restricted.
      t.boolean :commercial_controls_applied, null: false, default: false

      t.datetime :stripe_synced_at

      t.timestamps
    end

    add_index :venture_cards, :stripe_id,
              unique: true, where: "stripe_id IS NOT NULL"
  end
end
