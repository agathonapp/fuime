# frozen_string_literal: true

# == Schema Information
#
# Table name: fuime_test_sales
#
#  id                         :bigint           not null, primary key
#  amount_cents               :integer          not null
#  description                :string
#  occurred_at                :datetime         not null
#  created_at                 :datetime         not null
#  updated_at                 :datetime         not null
#  event_id                   :bigint           not null
#  fuime_offer_id             :bigint
#  stripe_checkout_session_id :string
#  user_id                    :bigint           not null
#
# Indexes
#
#  index_fuime_test_sales_on_event_id                    (event_id)
#  index_fuime_test_sales_on_event_id_and_occurred_at    (event_id,occurred_at)
#  index_fuime_test_sales_on_fuime_offer_id              (fuime_offer_id) WHERE (fuime_offer_id IS NOT NULL)
#  index_fuime_test_sales_on_stripe_checkout_session_id  (stripe_checkout_session_id) UNIQUE WHERE (stripe_checkout_session_id IS NOT NULL)
#  index_fuime_test_sales_on_user_id                     (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (event_id => events.id)
#  fk_rails_...  (user_id => users.id)
#
module Fuime
  # Fuime: one row per test purchase a founder ran against their own storefront.
  #
  # ⚠️ NOT MONEY. This table exists so a teenager can watch the buying flow work
  # before they send the link to a customer. It is deliberately outside the
  # ledger — see CreateFuimeTestSales for why — and nothing here may ever be
  # summed into a balance, a payable, a payout, a fee or a platform statistic.
  #
  # Each row is a REAL Stripe Checkout Session, created with the test-mode key
  # and paid with a test card, which is why `stripe_checkout_session_id` exists
  # and is uniquely indexed. Fuime::SandboxCheckout writes these, and only after
  # Stripe itself reports `livemode: false` — the processor's own assertion that
  # no money moved, which is a stronger guarantee than any flag of Fuime's.
  #
  # If you are here because you want a "total earned" number, you want
  # Fuime::PayablesLedger. Every row in this table is a purchase that did not
  # happen.
  #
  # Rows are disposable by design: the founder clears them from the Sandbox page
  # whenever they like, and clearing them costs nothing because they never meant
  # anything.
  class TestSale < ApplicationRecord
    self.table_name = "fuime_test_sales"

    belongs_to :event
    belongs_to :user

    # Optional, and unenforced by a foreign key: the free-amount path has no
    # offer, and an offer tested and then archived is the normal case rather
    # than an error. Resolved lazily by #offer so a removed offer degrades to
    # its stored description instead of raising on a page a teenager is reading.
    belongs_to :offer, class_name: "Fuime::Offer", foreign_key: :fuime_offer_id,
                       optional: true, inverse_of: false

    validates :amount_cents, numericality: { only_integer: true }
    validates :occurred_at, presence: true

    # The same bounds Fuime::CheckoutsController enforces on a real checkout: a
    # rehearsal for an amount a customer could never pay is not a rehearsal.
    #
    # A method rather than a `numericality:` option so the controller constant
    # is read when the record is validated instead of when this class is loaded.
    # A model that resolves a CONTROLLER constant in its class body inverts the
    # dependency and makes the model's loadability depend on the controller's —
    # which bites under eager loading, in a rake task, and in a console, all
    # places where money records get created and none where a controller should
    # need to exist.
    validate :amount_within_real_checkout_bounds

    def amount_within_real_checkout_bounds
      return if amount_cents.blank?

      minimum = ::Fuime::CheckoutsController::MINIMUM_AMOUNT_CENTS
      maximum = ::Fuime::CheckoutsController::MAXIMUM_AMOUNT_CENTS
      return if amount_cents.between?(minimum, maximum)

      errors.add(:amount_cents, "must be between #{minimum} and #{maximum} cents")
    end

    monetize :amount_cents

    scope :newest_first, -> { order(occurred_at: :desc, id: :desc) }

    # Display only. Named so that it reads as a count of rehearsals rather than
    # as an amount earned, because the one thing this number must never be
    # mistaken for is income.
    def self.rehearsed_total_cents
      sum(:amount_cents)
    end

  end
end
