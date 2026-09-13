# frozen_string_literal: true

# Fuime: where an operator's money goes, under merchant-of-record.
#
# See CreateFuimePayoutMethods for why this exists and why it holds a token
# rather than an account number. The short version: under MoR there is no
# merchant account for an operator to open, only a destination — and Fuime has
# no business holding a minor's bank credentials (L4).
#
#   pending ──mark_verified!──▶ verified ──remove!──▶ removed
#      │                            │                    ▲
#      └──── mark_failed! ──▶ failed ────────────────────┘
# == Schema Information
#
# Table name: fuime_payout_methods
#
#  id                               :bigint           not null, primary key
#  aasm_state                       :string           default("pending"), not null
#  account_holder_name              :string
#  failure_reason                   :text
#  institution_name                 :string
#  last4                            :string
#  provider                         :string           not null
#  provider_access_token_ciphertext :text
#  provider_reference               :string
#  verified_at                      :datetime
#  created_at                       :datetime         not null
#  updated_at                       :datetime         not null
#  added_by_id                      :bigint           not null
#  event_id                         :bigint           not null
#  provider_account_id              :string
#
# Indexes
#
#  index_fuime_payout_methods_on_added_by_id  (added_by_id)
#  index_fuime_payout_methods_on_event_id     (event_id)
#  index_live_fuime_payout_methods_on_event   (event_id) UNIQUE WHERE ((aasm_state)::text <> 'removed'::text)
#
# Foreign Keys
#
#  fk_rails_...  (added_by_id => users.id)
#  fk_rails_...  (event_id => events.id)
#
# Check Constraints
#
#  fuime_payout_methods_last4_is_last4  (last4 IS NULL OR length(last4::text) <= 4) NOT VALID
#  fuime_payout_methods_provider_known  (provider::text = ANY (ARRAY['plaid'::character varying::text, 'stripe'::character varying::text, 'manual'::character varying::text])) NOT VALID
#  fuime_payout_methods_state_known     (aasm_state::text = ANY (ARRAY['pending'::character varying::text, 'verified'::character varying::text, 'failed'::character varying::text, 'removed'::character varying::text])) NOT VALID
#
module Fuime
  class PayoutMethod < ApplicationRecord
    include AASM

    self.table_name = "fuime_payout_methods"

    # The Plaid access token for this Item. Encrypted at rest rather than stored
    # in the clear, because with the `auth` product on the Item it can be
    # exchanged for the account and routing numbers this table exists not to
    # hold — see AddPlaidItemToFuimePayoutMethods. Fuime never makes that call
    # itself; the token is kept so an originator can be handed the account once
    # MOR_MIGRATION_PLAN §4.3 picks one, without every operator re-linking.
    has_encrypted :provider_access_token

    belongs_to :event
    belongs_to :added_by, class_name: "User"

    PLAID  = "plaid"
    STRIPE = "stripe"
    MANUAL = "manual"
    PROVIDERS = [PLAID, STRIPE, MANUAL].freeze

    validates :provider, inclusion: { in: PROVIDERS }
    validates :last4, length: { maximum: 4 }, allow_blank: true
    validates :last4, format: { with: /\A\d{2,4}\z/, message: "should be the last few digits only" },
                      allow_blank: true

    validate :must_not_hold_an_account_number

    scope :live, -> { where.not(aasm_state: "removed") }
    scope :usable, -> { where(aasm_state: "verified") }

    aasm do
      state :pending, initial: true
      state :verified
      state :failed
      state :removed

      # The provider says the account is real and belongs to who it should.
      event :mark_verified do
        transitions from: %i[pending failed], to: :verified
        after { self.verified_at = Time.current }
      end

      event :mark_failed do
        transitions from: %i[pending verified], to: :failed
      end

      # Removed rather than destroyed: a payout already sent to this destination
      # references it, and deleting the row leaves a payment nobody can trace to
      # a bank. Same reasoning as archived offers and rejected batch lines.
      event :remove do
        transitions from: %i[pending verified failed], to: :removed
      end
    end

    # "Chase ••1234", or just the bank when a provider gives no digits.
    def display_name
      [institution_name.presence, last4.presence && "••#{last4}"].compact.join(" ").presence ||
        "Bank account"
    end

    def usable?
      verified?
    end

    def plaid?
      provider == PLAID
    end

    # Whether this row still carries everything an originator would need to be
    # handed the account: the Item token and which account inside it. False for
    # a row written before the pair existed, and for `manual`.
    #
    # Read by the operator page rather than assumed, because "connected" and
    # "connected in a way we can act on" are different claims and only one of
    # them should be made to somebody waiting on money.
    def actionable_reference?
      plaid? && provider_access_token.present? && provider_account_id.present?
    end

    private

    # The belt to the migration's braces.
    #
    # The check constraint stops a full account number reaching `last4`. This
    # stops one reaching any of the free-text columns, because the realistic
    # mistake is not a malicious write — it is a future integration cheerfully
    # putting the account number in `provider_reference` or the bank's name
    # field because it had it to hand and the column was there.
    #
    # Nine digits is the shortest a US account number gets; a routing number is
    # exactly nine. Anything that long and all-numeric in these fields is a
    # credential, not a label.
    def must_not_hold_an_account_number
      # Two rules, because the fields are different kinds of thing.
      #
      # `provider_reference` and `provider_account_id` are machine tokens and
      # legitimately carry a long digit run — `ba_1QxYz0123456789` is an ordinary
      # Stripe id. Rejecting a digit run there would break real integrations to
      # catch a case that does not look like that, so they are refused only when
      # ENTIRELY digits, which is what a bare account or routing number is.
      #
      # `institution_name` and `account_holder_name` are human labels. A bank is
      # not called "Chase 000123456789" and nobody is named "Vansh Jain
      # 021000021", so an embedded nine-digit run there is a credential somebody
      # pasted into the nearest available box — which is the realistic failure
      # this validation exists for.
      [:provider_reference, :provider_account_id].each do |field|
        token = self[field].to_s.strip.gsub(/[\s-]/, "")
        next unless token.match?(/\A\d{9,}\z/)

        errors.add(field,
                   "looks like an account or routing number — Fuime stores a token, never the digits")
      end

      [:institution_name, :account_holder_name].each do |field|
        value = self[field].to_s
        next unless value.match?(/\d{9,}/)

        errors.add(field, "looks like an account or routing number — Fuime stores a token, never the digits")
      end
    end

  end
end
