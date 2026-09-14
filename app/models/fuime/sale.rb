# frozen_string_literal: true

# == Schema Information
#
# Table name: fuime_sales
#
#  id                       :bigint           not null, primary key
#  amount_cents             :integer          not null
#  country                  :string
#  occurred_at              :datetime         not null
#  postal_code              :string
#  state                    :string
#  created_at               :datetime         not null
#  updated_at               :datetime         not null
#  event_id                 :bigint           not null
#  fuime_offer_id           :bigint
#  stripe_payment_intent_id :string           not null
#
# Indexes
#
#  index_fuime_sales_on_country_and_state_and_occurred_at  (country,state,occurred_at)
#  index_fuime_sales_on_event_id                           (event_id)
#  index_fuime_sales_on_fuime_offer_id                     (fuime_offer_id)
#  index_fuime_sales_on_stripe_payment_intent_id           (stripe_payment_intent_id) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (event_id => events.id)
#
module Fuime
  # Fuime: one row per merchant-of-record sale.
  #
  # Written by Fuime::PaymentWebhookHandler as a side effect of posting the
  # ledger line, and by nothing else — so a row here always has a ledger line
  # behind it, and the two are keyed on the same PaymentIntent id.
  #
  # Two jobs, and they are deliberately the same table:
  #
  #   1. **Where the buyer was.** Under MoR every operator's sales aggregate
  #      under one legal entity, so state economic nexus accrues against Fuime
  #      (MOR_RISK_ACCEPTANCE.md §7). Nexus is measured on history, and history
  #      cannot be backfilled.
  #   2. **What was sold.** The ledger aggregates by memo prefix, not by offer,
  #      so nothing in the app could answer "what does this founder sell most
  #      of". This is the spine for that.
  #
  # This is a RECORD, not a calculation. It deliberately knows nothing about
  # thresholds, rates or registration — those belong in a report that reads it,
  # so the capture cannot start failing because the tax rules changed.
  #
  # ⚠️ It is NOT the ledger, and must never become a second source of truth for
  # money. What a founder is OWED is computed by Fuime::PayablesLedger from
  # canonical transactions. This table is for reporting.
  class Sale < ApplicationRecord
    self.table_name = "fuime_sales"

    belongs_to :event
    # Optional: the free-amount path has no offer — a customer who was told a
    # price in person is still a sale. No foreign key, so a sale survives its
    # offer being removed by any route; what was sold is a fact about money that
    # changed hands.
    # `inverse_of: false` rather than an inverse: Fuime::Offer deliberately has no
    # `has_many :sales`. An offer is a listing a founder edits; sales are an
    # append-only record of money that changed hands, and a sold offer outlives
    # its listing (it may be archived or renamed). Handing Offer an association
    # that could cascade or be counted from the edit screen invites exactly the
    # coupling this table was split out to avoid — reporting reads Sale.
    belongs_to :offer,
               class_name: "Fuime::Offer",
               foreign_key: :fuime_offer_id,
               inverse_of: false,
               optional: true

    validates :stripe_payment_intent_id, presence: true, uniqueness: true
    validates :amount_cents, presence: true
    validates :occurred_at, presence: true

    scope :in_year, ->(year) {
      where(occurred_at: Time.zone.local(year).all_year)
    }
    # Unknown-jurisdiction sales are the ones worth looking at, so they get a
    # scope rather than being filtered out of every query by default.
    scope :unknown_jurisdiction, -> { where(country: nil) }

    # What this founder sells most of, by revenue — the question the ledger
    # cannot answer, which is half of why this table exists. Returns
    # {offer_id => cents}; callers resolve names, because an offer may have been
    # archived since and the caller knows whether it wants to show that.
    scope :revenue_by_offer, -> {
      where.not(fuime_offer_id: nil).group(:fuime_offer_id).sum(:amount_cents)
    }

    # Capture is best-effort by design: a jurisdiction that cannot be written
    # must never prevent a sale from reaching a founder's ledger. The ledger is
    # what the founder sees and what the payout is computed from; this table is
    # a compliance record Fuime reads later, and a gap in it is recoverable from
    # Stripe while a missing ledger line is a churned founder (TEEN_GROWTH G10).
    # Hence the bare rescue: every failure here is swallowed and reported.
    #
    # Create-or-ENRICH, not create-or-ignore. The two success events carry
    # different data for the same sale: `checkout.session.completed` has
    # `customer_details.address`, and `payment_intent.succeeded` generally does
    # not. Whichever arrives first writes the row, so a plain insert-and-ignore
    # would permanently lose the address every time the PaymentIntent won the
    # race — silently, and on exactly the sales this table exists to count.
    #
    # Enrichment only ever fills blanks. A jurisdiction already recorded is never
    # overwritten by a later event, because the first address Stripe gave for a
    # sale is the one the buyer actually entered.
    def self.record!(payment_intent_id:, event:, amount_cents:, address:, occurred_at:, offer_id: nil)
      return nil if payment_intent_id.blank? || event.blank?

      attrs = {
        country: address&.try(:country).presence,
        state: address&.try(:state).presence,
        postal_code: address&.try(:postal_code).presence,
        fuime_offer_id: offer_id.presence
      }

      existing = find_by(stripe_payment_intent_id: payment_intent_id)
      return enrich(existing, attrs) if existing

      create!(
        stripe_payment_intent_id: payment_intent_id,
        event:,
        amount_cents:,
        occurred_at: occurred_at || Time.current,
        **attrs
      )
    rescue ActiveRecord::RecordNotUnique
      # Both success events landed in different threads and both missed the
      # find_by. The loser enriches the winner's row rather than dropping its
      # address on the floor.
      enrich(find_by(stripe_payment_intent_id: payment_intent_id), attrs)
    rescue => e
      Rails.error.report(e, handled: true, context: { payment_intent_id:, event_id: event&.id })
      nil
    end

    def self.enrich(row, attrs)
      return nil if row.blank?

      fills = attrs.select { |column, value| value.present? && row[column].blank? }
      row.update!(fills) if fills.any?
      row
    end
    private_class_method :enrich

  end
end
