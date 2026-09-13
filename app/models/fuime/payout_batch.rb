# frozen_string_literal: true

# == Schema Information
#
# Table name: fuime_payout_batches
#
#  id                   :bigint           not null, primary key
#  aasm_state           :string           default("draft"), not null
#  approved_at          :datetime
#  cancellation_reason  :text
#  cancelled_at         :datetime
#  hold_days            :integer          not null
#  maximum_cents        :integer          not null
#  minimum_cents        :integer          not null
#  notes                :text
#  paid_at              :datetime
#  payout_on            :date             not null
#  period_end           :date             not null
#  period_start         :date             not null
#  reserve_basis_points :integer          not null
#  reserve_window_days  :integer          not null
#  created_at           :datetime         not null
#  updated_at           :datetime         not null
#  approved_by_id       :bigint
#  paid_by_id           :bigint
#
# Indexes
#
#  index_fuime_payout_batches_on_aasm_state       (aasm_state)
#  index_fuime_payout_batches_on_approved_by_id   (approved_by_id)
#  index_fuime_payout_batches_on_paid_by_id       (paid_by_id)
#  index_live_fuime_payout_batches_on_period_end  (period_end) UNIQUE WHERE ((aasm_state)::text <> 'cancelled'::text)
#
# Foreign Keys
#
#  fk_rails_...  (approved_by_id => users.id)
#  fk_rails_...  (paid_by_id => users.id)
#
# Check Constraints
#
#  fuime_payout_batches_period_ordered  (period_end >= period_start)
#  fuime_payout_batches_state_known     (aasm_state::text = ANY (ARRAY['draft'::character varying, 'approved'::character varying, 'paid'::character varying, 'cancelled'::character varying]::text[]))
#
# Fuime: one weekly payout run.
#
# See the migration header for why a batch is a stored record rather than a query,
# and why the policy dials are copied onto the row. This class is the lifecycle on
# top of that record:
#
#   draft ──approve!──▶ approved ──mark_paid!──▶ paid
#     │                    │
#     └──── cancel! ───────┘
#
# ── Where the money actually moves ──────────────────────────────────────────
#
# Nowhere, yet, and that is deliberate rather than unfinished. Under
# merchant-of-record paying an operator is ordinary accounts payable on Fuime's
# own money, and WHICH originator carries it is an open product decision blocked
# on diligence (MOR_MIGRATION_PLAN §4.3). So `mark_paid!` is a human asserting the
# transfers went out — the same shape as `Fuime::PayoutService#settle!` on the
# school path, and the same principle: the ledger records what happened, never
# what was authorised.
#
# The consequence to hold onto is that approving a batch moves no money and posts
# no ledger line. Only `mark_paid!` debits, and it debits inside one transaction
# with the state change, so a batch cannot be marked paid without its lines being
# posted or vice versa.
module Fuime
  class PayoutBatch < ApplicationRecord
    include AASM

    self.table_name = "fuime_payout_batches"

    has_many :payout_requests,
             class_name: "::PayoutRequest",
             inverse_of: :payout_batch,
             dependent: :nullify

    belongs_to :approved_by, class_name: "User", optional: true
    belongs_to :paid_by, class_name: "User", optional: true

    validates :period_start, :period_end, :payout_on, presence: true
    validates :hold_days, :reserve_basis_points, :reserve_window_days,
              :maximum_cents, :minimum_cents,
              presence: true,
              numericality: { only_integer: true, greater_than_or_equal_to: 0 }

    validate :period_must_be_ordered

    scope :live, -> { where.not(aasm_state: "cancelled") }
    scope :recent_first, -> { order(period_end: :desc, id: :desc) }
    scope :awaiting_approval, -> { where(aasm_state: "draft") }
    scope :awaiting_payment, -> { where(aasm_state: "approved") }

    aasm do
      state :draft, initial: true
      state :approved
      state :paid
      state :cancelled

      # A human has reviewed every line. The brief's control is manual approval of
      # every payout, and this is where that happens — once per run rather than
      # once per operator, because a reviewer comparing fifty lines against each
      # other catches the anomalous one, and fifty separate approvals is a queue
      # people learn to clear rather than read.
      event :approve do
        transitions from: :draft, to: :approved
      end

      # The transfers have gone out. See the class header for who asserts this and
      # why it is not Stripe.
      event :mark_paid do
        transitions from: :approved, to: :paid
      end

      # Reachable from `approved` as well as `draft`: a run can be approved on
      # Thursday and stopped on Friday morning, and modelling that as impossible
      # would mean the only way to stop it is to edit the database.
      event :cancel do
        transitions from: %i[draft approved], to: :cancelled
      end
    end

    def total_cents
      payout_requests.sum(:amount_cents)
    end

    def reserve_held_cents
      payout_requests.sum(:reserve_held_cents)
    end

    def operator_count
      payout_requests.count
    end

    def policy
      @policy ||= Fuime::PayoutPolicy.from(self)
    end

    # Everything a reviewer needs before saying yes, in one line.
    def summary
      "#{operator_count} operator#{'s' unless operator_count == 1} · " \
        "#{format_cents(total_cents)} · pays #{payout_on.strftime('%A %-d %B')}"
    end

    def editable?
      draft?
    end

    private

    def period_must_be_ordered
      return if period_start.blank? || period_end.blank?
      return if period_end >= period_start

      errors.add(:period_end, "can't be before the start of the period")
    end

    def format_cents(cents)
      ActiveSupport::NumberHelper.number_to_currency(cents.to_i / 100.0)
    end

  end
end
