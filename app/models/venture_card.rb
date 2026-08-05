# frozen_string_literal: true

# == Schema Information
#
# Table name: venture_cards
#
#  id                          :bigint           not null, primary key
#  brand                       :string
#  card_type                   :string           default("virtual"), not null
#  commercial_controls_applied :boolean          default(FALSE), not null
#  exp_month                   :integer
#  exp_year                    :integer
#  last4                       :string
#  spending_limit_cents        :integer
#  spending_limit_interval     :string
#  status                      :string
#  stripe_synced_at            :datetime
#  created_at                  :datetime         not null
#  updated_at                  :datetime         not null
#  stripe_id                   :text
#  venture_cardholder_id       :bigint           not null
#
# Indexes
#
#  index_venture_cards_on_stripe_id              (stripe_id) UNIQUE WHERE (stripe_id IS NOT NULL)
#  index_venture_cards_on_venture_cardholder_id  (venture_cardholder_id)
#
# Foreign Keys
#
#  fk_rails_...  (venture_cardholder_id => venture_cardholders.id)
#
# Fuime: one card on a venture's own Stripe account.
#
# Fuime never receives or stores a full card number — only the display fields Stripe
# returns. The number is shown to the cardholder by Stripe's own client-side
# components, which is what keeps it out of Fuime's PCI scope entirely.
class VentureCard < ApplicationRecord
  VIRTUAL = "virtual"
  PHYSICAL = "physical"

  # Stripe's `spending_limits[].interval` values.
  INTERVALS = %w[per_authorization daily weekly monthly yearly all_time].freeze

  belongs_to :venture_cardholder

  has_one :event, through: :venture_cardholder
  has_one :user, through: :venture_cardholder

  validates :stripe_id, uniqueness: true, allow_nil: true
  validates :card_type, inclusion: { in: [VIRTUAL, PHYSICAL] }
  validates :spending_limit_interval, inclusion: { in: INTERVALS }, allow_nil: true
  validates :spending_limit_cents,
            numericality: { only_integer: true, greater_than: 0 },
            allow_nil: true

  scope :active, -> { where(status: "active") }

  def active?
    status == "active"
  end

  def spending_limit
    spending_limit_cents.present? ? spending_limit_cents / 100.0 : nil
  end

  # Is this card actually restricted to business purchases?
  #
  # Read from the recorded flag rather than assumed, because a card that reached
  # Stripe without the allowlist is a compliance problem that must be visible rather
  # than presumed away. `Fuime::CardIssuingService` sets it only after confirming
  # Stripe echoed the categories back.
  def commercial_controls?
    commercial_controls_applied?
  end

  # Mirror a Stripe::Issuing::Card. Takes the object rather than fetching it so the
  # same path serves a webhook payload and an explicit refresh.
  def sync_from_stripe!(card)
    # Deeply converted first. `to_h` alone is SHALLOW — nested values stay
    # StripeObjects, which have no `dig` — so it fails on the second key. See
    # Fuime::StripeHash.
    data = ::Fuime::StripeHash.deep(card)
    limits = Array(data.dig(:spending_controls, :spending_limits)).first
    allowed = Array(data.dig(:spending_controls, :allowed_categories))

    update!(
      stripe_id: card.id,
      last4: card.last4,
      brand: card.brand,
      exp_month: card.exp_month,
      exp_year: card.exp_year,
      status: card.status,
      card_type: card.type,
      spending_limit_cents: limits && limits[:amount],
      spending_limit_interval: limits && limits[:interval],
      # Recomputed from what Stripe reports on every sync, so a card whose controls
      # are changed in the Stripe dashboard stops claiming to be restricted.
      commercial_controls_applied: allowed.sort == ::Fuime::CardSpendPolicy.allowed_categories.sort,
      stripe_synced_at: Time.current
    )
  end

end
