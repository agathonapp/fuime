# frozen_string_literal: true

# == Schema Information
#
# Table name: payout_requests
#
#  id               :bigint           not null, primary key
#  aasm_state       :string           not null, default("pending")
#  amount_cents     :integer          not null
#  approved_at      :datetime
#  failure_code     :string
#  failure_message  :text
#  paid_at          :datetime
#  rejected_at      :datetime
#  rejection_reason :text
#  stripe_payout_id :text
#  created_at       :datetime         not null
#  updated_at       :datetime         not null
#  approved_by_id   :bigint
#  event_id         :bigint           not null
#  requested_by_id  :bigint           not null
#
# Fuime: a teen's request to move money out of the venture, and the guardian's
# decision on it.
#
# See the migration for why the approval gate exists (short version: the guardian
# legally owns the account and the funds, so a minor cannot move money out of it
# unilaterally — CLAUDE.md L2).
#
# ── Division of labour ──────────────────────────────────────────────────────
#
# This model owns the STATE and the rules that must hold regardless of who is
# calling. Fuime::PayoutService owns the Stripe conversation and the live-balance
# check. The split matters because the balance is a network fact that can change
# between two reads, so it cannot be a validation here without making every
# `valid?` call hit Stripe.
class PayoutRequest < ApplicationRecord
  include AASM

  belongs_to :event
  # The teen who asked.
  belongs_to :requested_by, class_name: "User"
  # The guardian who approved. Absent while pending, and forever on a rejection.
  belongs_to :approved_by, class_name: "User", optional: true

  MINIMUM_CENTS = 100

  validates :amount_cents,
            numericality: {
              only_integer: true,
              greater_than_or_equal_to: MINIMUM_CENTS,
              message: "must be at least $#{MINIMUM_CENTS / 100}"
            }

  validate :one_pending_request_per_venture, on: :create
  validate :approver_must_be_an_overseeing_guardian

  scope :awaiting_approval, -> { where(aasm_state: "pending") }
  scope :recent_first, -> { order(created_at: :desc) }

  aasm do
    state :pending, initial: true
    state :approved
    state :rejected
    state :paid
    state :failed

    event :approve do
      transitions from: :pending, to: :approved
    end

    event :reject do
      transitions from: :pending, to: :rejected
    end

    # Stripe confirmed the money reached the bank.
    event :mark_paid do
      transitions from: %i[approved failed], to: :paid
    end

    # Stripe bounced it. Reachable from :paid because Stripe can reverse a payout
    # it previously reported as paid (a bank can return funds days later), and
    # modelling that as impossible would mean silently ignoring the webhook that
    # says a family did not get their money.
    event :mark_failed do
      transitions from: %i[approved paid], to: :failed
    end
  end

  def amount
    amount_cents / 100.0
  end

  # Still waiting on a human. Distinct from `pending?` only in intent, but reads
  # better at call sites deciding whether to show a parent a decision prompt.
  def awaiting_guardian?
    pending?
  end

  # A decision has been made and money is on its way or gone. Used to decide
  # whether the teen may open another request.
  def settled?
    paid? || rejected?
  end

  private

  # One open request at a time per venture.
  #
  # Not a UX simplification: several pending requests can each be individually
  # affordable and collectively exceed the balance, so approving them in any order
  # would produce a payout that fails at Stripe for reasons the guardian was never
  # shown. Serialising them means the balance check at approval is meaningful.
  def one_pending_request_per_venture
    return if event.blank?

    if self.class.awaiting_approval.where(event_id:).exists?
      errors.add(:base, "This venture already has a payout request waiting for a guardian's approval.")
    end
  end

  # Defence in depth behind the policy layer.
  #
  # Authorization lives in PayoutRequestPolicy, but "the adult who approved this
  # was actually a guardian overseeing this venture" is a claim the record itself
  # makes to anyone reading it later, so the record enforces it. Admins are
  # allowed through because Fuime support genuinely does have to resolve stuck
  # payouts, and that is visible here rather than hidden in a controller.
  def approver_must_be_an_overseeing_guardian
    return if approved_by.blank? || event.blank?
    return if approved_by.admin?
    return if event.overseeing_guardians.exists?(id: approved_by.id)

    errors.add(:approved_by, "must be a guardian overseeing this venture")
  end

end
