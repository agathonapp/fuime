# frozen_string_literal: true

# == Schema Information
#
# Table name: fuime_customers
#
#  id                 :bigint           not null, primary key
#  email              :string           not null
#  first_purchased_at :datetime         not null
#  last_purchased_at  :datetime         not null
#  name               :string
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#  event_id           :bigint           not null
#  stripe_customer_id :string
#
# Indexes
#
#  index_fuime_customers_on_event_id            (event_id)
#  index_fuime_customers_on_event_id_and_email  (event_id,email) UNIQUE
#  index_fuime_customers_on_stripe_customer_id  (stripe_customer_id) WHERE (stripe_customer_id IS NOT NULL)
#
# Foreign Keys
#
#  fk_rails_...  (event_id => events.id)
#
module Fuime
  # Fuime: someone who bought from a venture.
  #
  # ── Whose customer is this, legally ──────────────────────────────────────
  #
  # Fuime's. Under merchant-of-record Ninth Street Labs, LLC is the seller on the
  # receipt, so the contract is between the buyer and Fuime, and Fuime is the
  # party that collected this data.
  #
  # The operator still sees it, and should: a teenager mowing a lawn needs to
  # know whose lawn it is, and a founder who cannot contact a customer cannot run
  # a business. Every marketplace works this way.
  #
  # ⚠️ What that means OUTSIDE this file: because Fuime collects and then shares
  # with the operator, the terms and privacy policy have to say so plainly. That
  # is a disclosure obligation, and it is not satisfied by this comment.
  #
  # ── Scoped to one venture ────────────────────────────────────────────────
  #
  # Keyed on (event_id, email). One person buying from two ventures is two rows,
  # deliberately — see the migration. Venture A must not be able to learn that
  # its customer also buys from venture B.
  class Customer < ApplicationRecord
    self.table_name = "fuime_customers"

    belongs_to :event
    has_many :sales, class_name: "Fuime::Sale", foreign_key: :fuime_customer_id,
                     dependent: :nullify, inverse_of: :customer

    validates :email, presence: true
    validates :first_purchased_at, :last_purchased_at, presence: true

    # Best-effort and never raises, for the same reason Fuime::Sale.record! does
    # not: this is a record Fuime reads later, and a founder's ledger line must
    # never be lost because a customer row could not be written.
    #
    # Upsert on (event_id, email) rather than find-then-create: two webhooks for
    # the same buyer can land in different threads, and the unique index is what
    # actually decides.
    def self.record!(event:, email:, name: nil, stripe_customer_id: nil, purchased_at: nil)
      return nil if event.blank? || email.blank?

      normalized = email.to_s.strip.downcase
      at = purchased_at || Time.current

      customer = find_or_initialize_by(event:, email: normalized)
      customer.first_purchased_at ||= at
      # A backfilled or out-of-order webhook must not make the most recent
      # purchase look older than it is.
      customer.last_purchased_at = at if customer.last_purchased_at.blank? || at > customer.last_purchased_at
      customer.name = name.presence || customer.name
      customer.stripe_customer_id = stripe_customer_id.presence || customer.stripe_customer_id
      customer.save!
      customer
    rescue ActiveRecord::RecordNotUnique
      find_by(event:, email: normalized)
    rescue => e
      Rails.error.report(e, handled: true, context: { event_id: event&.id })
      nil
    end

    def display_name = name.presence || email

    def total_spent_cents = sales.sum(:amount_cents)

    def purchase_count = sales.count

    # Two or more purchases. The single most useful thing a small business can
    # know about a customer, and the reason this table earns its place beyond
    # analytics.
    def repeat? = purchase_count > 1

  end
end
