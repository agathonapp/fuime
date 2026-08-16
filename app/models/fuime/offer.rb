# frozen_string_literal: true

# Fuime: a thing a teenager sells, at a price they set.
#
# See CreateFuimeOffers for why this object exists and why `price_cents` has no
# default. The short version: the storefront was a tip jar, an offer is what
# makes it a store, and the price is the operator's under §8.3 D2 — Fuime never
# writes one, never suggests one, and has nowhere to store a suggestion.
#
#   draft ──publish!──▶ published ──archive!──▶ archived
#     ▲                     │                      │
#     └──── unpublish! ─────┘                      │
#     └───────────── restore! ──────────────────────┘
#
# ── Why archived and not deleted ────────────────────────────────────────────
#
# A sold offer is referenced by a ledger memo and by a buyer's receipt. Deleting
# it leaves a payment nobody can explain, which is the same reason a cancelled
# payout run's lines are rejected rather than removed.
# == Schema Information
#
# Table name: fuime_offers
#
#  id           :bigint           not null, primary key
#  aasm_state   :string           default("draft"), not null
#  description  :text
#  name         :string           not null
#  position     :integer          default(0), not null
#  price_cents  :integer          not null
#  public_token :string
#  unit_label   :string
#  created_at   :datetime         not null
#  updated_at   :datetime         not null
#  event_id     :bigint           not null
#
# Indexes
#
#  index_fuime_offers_on_event_id                      (event_id)
#  index_fuime_offers_on_public_token                  (public_token) UNIQUE WHERE (public_token IS NOT NULL)
#  index_published_fuime_offers_on_event_and_position  (event_id,position) WHERE ((aasm_state)::text = 'published'::text)
#
# Foreign Keys
#
#  fk_rails_...  (event_id => events.id)
#
# Check Constraints
#
#  fuime_offers_price_in_range  (price_cents > 0 AND price_cents <= 1000000)
#  fuime_offers_state_known     (aasm_state::text = ANY (ARRAY['draft'::character varying, 'published'::character varying, 'archived'::character varying]::text[]))
#
module Fuime
  class Offer < ApplicationRecord
    include AASM

    self.table_name = "fuime_offers"

    belongs_to :event

    MAXIMUM_PRICE_CENTS = 1_000_000
    MAX_NAME_LENGTH = 80
    MAX_DESCRIPTION_LENGTH = 600
    MAX_UNIT_LABEL_LENGTH = 40

    validates :name, presence: true, length: { maximum: MAX_NAME_LENGTH }
    validates :description, length: { maximum: MAX_DESCRIPTION_LENGTH }
    validates :unit_label, length: { maximum: MAX_UNIT_LABEL_LENGTH }

    # No default and no suggestion — see the class header. The message says
    # "you decide" rather than naming a range, because naming a range is the
    # thing this is here to prevent.
    validates :price_cents,
              numericality: {
                only_integer: true,
                greater_than: 0,
                less_than_or_equal_to: MAXIMUM_PRICE_CENTS,
                message: "has to be an amount you've decided on, up to $10,000"
              }

    validate :only_a_selling_venture_may_publish, if: :published?
    validate :text_must_not_impersonate_a_ledger_key

    # The shareable link's identity. See AddPublicTokenToFuimeOffers for why this
    # is a random token and not the id — an enumerable catalogue of minors'
    # businesses with prices attached is a targeting list.
    TOKEN_LENGTH = 12

    before_create :assign_public_token

    # The token, generating one if this offer predates the column.
    #
    # Lazy rather than backfilled in a migration: generating unique random values
    # in a loop against a live table is the kind of migration that locks for
    # minutes and then half-fails. Anything older gets one the first time somebody
    # asks for its link, which is also what an importer gets for free.
    def public_token!
      return public_token if public_token.present?

      update_column(:public_token, self.class.generate_public_token)
      public_token
    end

    def self.generate_public_token
      loop do
        candidate = SecureRandom.alphanumeric(TOKEN_LENGTH)
        break candidate unless exists?(public_token: candidate)
      end
    end

    scope :published, -> { where(aasm_state: "published") }
    scope :live, -> { where.not(aasm_state: "archived") }
    # The storefront's order: the operator's own. See the migration for why an
    # operator ordering their OWN shop is not the ranking §8.3 D2 forbids.
    scope :in_operator_order, -> { order(:position, :id) }

    aasm do
      state :draft, initial: true
      state :published
      state :archived

      event :publish do
        transitions from: :draft, to: :published
      end

      event :unpublish do
        transitions from: :published, to: :draft
      end

      event :archive do
        transitions from: %i[draft published], to: :archived
      end

      # Back to draft rather than straight to published: an offer coming out of
      # the archive should be looked at before it is on sale again, and the price
      # is the reason — it may have been archived precisely because it was wrong.
      event :restore do
        transitions from: :archived, to: :draft
      end
    end

    # nil for an unsaved offer, deliberately.
    #
    # The new-offer form renders `Fuime::Offer.new` and reads this for the price
    # field's value. Returning 0 would put "0" in the box — a Fuime-written number
    # in the one field that must only ever contain the operator's own, which is
    # the whole point of the object having no default (see the header). Blank is
    # the honest starting state.
    def price
      return nil if price_cents.nil?

      price_cents / 100.0
    end

    # "$35" or "$35 per lawn". The unit is the operator's own words.
    def price_sentence
      return "No price set" if price_cents.nil?

      formatted = ActiveSupport::NumberHelper.number_to_currency(price)
      return formatted if unit_label.blank?

      "#{formatted} #{unit_label}"
    end

    # What reaches the Stripe product, the buyer's receipt and then the ledger
    # memo a teenager reads. The offer's name rather than a stranger's free text,
    # which is the other half of why this object is worth having — before it,
    # every ledger line said whatever the buyer typed.
    def payment_description
      raw = [name, unit_label.presence].compact.join(" — ")

      # Sanitised on the way out as well as validated on the way in. The
      # validation is what tells an operator; this is what protects the ledger
      # from a row that predates the validation, or one written by a console, an
      # importer, or a fixture. See VentureLedger.sanitize_memo_text.
      ::Fuime::VentureLedger.sanitize_memo_text(raw).truncate(120)
    end

    private

    def assign_public_token
      self.public_token ||= self.class.generate_public_token
    end

    # An offer can be drafted before a venture can sell — that is the point of
    # draft, and a teenager setting up their shop while a guardian finishes Stripe
    # onboarding is the ordinary case. Publishing is different: a published offer
    # is a public promise that a payment will work, and `#accepts_payments?`
    # covers vetting, the flag scope and payment setup in one place.
    # An offer's name reaches a ledger memo, and a bracketed "[fuime_…]" in a memo
    # is how Fuime::PayablesLedger decides what a line IS. An offer named
    # "Mow [fuime_fee_x" would make a $35 sale classify as a $35 platform fee on
    # the operator's own earnings page.
    #
    # Refused rather than silently stripped, because this is the path where there
    # is a person to tell. The buyer's free-text box on the public checkout has no
    # such person, so it is sanitised instead — see
    # VentureLedger.sanitize_memo_text.
    def text_must_not_impersonate_a_ledger_key
      offending = [name, description, unit_label].compact
                                                 .select { |t| ::Fuime::VentureLedger.memo_carries_key?(t) }
      return if offending.empty?

      errors.add(:base, "Text like \"[fuime_…]\" is reserved — Fuime uses it to label transactions. Try it without the brackets.")
    end

    def only_a_selling_venture_may_publish
      return if event.blank? || event.accepts_payments?

      errors.add(:base, "This business can't take payments yet, so its offers can't go live.")
    end

  end
end
