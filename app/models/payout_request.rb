# frozen_string_literal: true

# == Schema Information
#
# Table name: payout_requests
#
#  id               :bigint           not null, primary key
#  aasm_state       :string           default("pending"), not null
#  amount_cents     :integer          not null
#  approved_at      :datetime
#  destination      :string           default("account_owner_bank"), not null
#  destination_note :text
#  failure_code     :string
#  failure_message  :text
#  paid_at          :datetime
#  rejected_at      :datetime
#  rejection_reason :text
#  settled_at       :datetime
#  created_at       :datetime         not null
#  updated_at       :datetime         not null
#  approved_by_id   :bigint
#  event_id         :bigint           not null
#  requested_by_id  :bigint           not null
#  settled_by_id    :bigint
#  stripe_payout_id :text
#
# Indexes
#
#  index_payout_requests_on_approved_by_id    (approved_by_id)
#  index_payout_requests_on_event_id          (event_id)
#  index_payout_requests_on_requested_by_id   (requested_by_id)
#  index_payout_requests_on_settled_by_id     (settled_by_id)
#  index_payout_requests_on_stripe_payout_id  (stripe_payout_id) UNIQUE WHERE (stripe_payout_id IS NOT NULL)
#  index_pending_payout_requests_on_event     (event_id,created_at) WHERE ((aasm_state)::text = 'pending'::text)
#
# Foreign Keys
#
#  fk_rails_...  (approved_by_id => users.id)
#  fk_rails_...  (event_id => events.id)
#  fk_rails_...  (requested_by_id => users.id)
#  fk_rails_...  (settled_by_id => users.id)
#
# Check Constraints
#
#  payout_requests_destination_known  (destination::text = ANY (ARRAY['account_owner_bank'::character varying, 'personal_transfer'::character varying]::text[]))
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
  # The responsible adult who approved. Absent while pending, and forever on a
  # rejection.
  belongs_to :approved_by, class_name: "User", optional: true
  # Who confirmed a personal_transfer actually went out. See the migration.
  belongs_to :settled_by, class_name: "User", optional: true

  MINIMUM_CENTS = 100

  # Stripe sends it, to the bank the account owner attached. The only destination a
  # family venture has, because there the account owner IS the person being paid.
  ACCOUNT_OWNER_BANK = "account_owner_bank"

  # The school pays the student directly and confirms it here. Fuime records the
  # authorisation and the settlement and never touches the money — see the
  # migration for why there is no third option where Fuime sends it.
  PERSONAL_TRANSFER = "personal_transfer"

  DESTINATIONS = [ACCOUNT_OWNER_BANK, PERSONAL_TRANSFER].freeze

  validates :amount_cents,
            numericality: {
              only_integer: true,
              greater_than_or_equal_to: MINIMUM_CENTS,
              message: "must be at least $#{MINIMUM_CENTS / 100}"
            }

  validates :destination, inclusion: { in: DESTINATIONS }

  validate :one_pending_request_per_venture, on: :create
  validate :approver_must_be_the_responsible_adult
  validate :approver_must_not_be_the_requester
  validate :destination_must_suit_the_account

  scope :awaiting_approval, -> { where(aasm_state: "pending") }
  scope :recent_first, -> { order(created_at: :desc) }
  # Approved personal transfers the school has not yet confirmed paying. This is
  # the business office's to-do list, and the reason `settled_at` is a column
  # rather than an inference from aasm_state.
  scope :awaiting_settlement, -> { where(aasm_state: "approved", destination: PERSONAL_TRANSFER) }

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

  def account_owner_bank?
    destination == ACCOUNT_OWNER_BANK
  end

  def personal_transfer?
    destination == PERSONAL_TRANSFER
  end

  # Approved, but the school has not yet said it paid the student. Only ever true
  # on the personal_transfer path — a Stripe payout has no equivalent waiting room,
  # because Stripe acts the moment it is approved.
  def awaiting_settlement?
    approved? && personal_transfer?
  end

  # Still waiting on a human. Distinct from `pending?` only in intent, but reads
  # better at call sites deciding whether to show an adult a decision prompt.
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
  # Authorization lives in EventPolicy#decide_payout?, but "the adult who approved
  # this was actually the one responsible for this venture" is a claim the record
  # itself makes to anyone reading it later, so the record enforces it. Admins are
  # allowed through because Fuime support genuinely does have to resolve stuck
  # payouts, and that is visible here rather than hidden in a controller.
  #
  # Who the responsible adult is depends on the venture. A family venture has a
  # guardian. One inside a school programme has no guardian by design, and the
  # school's manager stands in its place — the same substitution EventPolicy makes,
  # for the same reason. Before this branch existed a school venture's request
  # could be approved by literally nobody except a Fuime admin.
  def approver_must_be_the_responsible_adult
    return if approved_by.blank? || event.blank?
    return if approved_by.admin?

    if event.institutionally_sponsored?
      unless OrganizerPosition.role_at_least?(approved_by, event, :manager)
        errors.add(:approved_by, "must be a manager of the sponsoring school")
      end

      return
    end

    return if event.overseeing_guardians.exists?(id: approved_by.id)

    errors.add(:approved_by, "must be a guardian overseeing this venture")
  end

  # Nobody releases their own money request.
  #
  # On a family venture this is already true structurally: requesting needs
  # `member?` and deciding needs `guardian_reader?`, and a guardian is read-only by
  # construction. On a school venture it is not — a manager is >= member, so the
  # same guide could file a request and approve it in two clicks. Segregation of
  # duties is the entire content of an approval gate, so it is asserted here rather
  # than left to the shape of the role hierarchy.
  #
  # No admin exemption: an admin approving a request an admin filed is precisely
  # the self-approval this refuses.
  def approver_must_not_be_the_requester
    return if approved_by.blank?
    return unless approved_by_id == requested_by_id

    errors.add(:approved_by, "can't approve their own payout request")
  end

  # A request must ask for something the venture's account can actually do.
  #
  # On a shared (school-owned) account, `account_owner_bank` would send the pooled
  # balance of every student in the programme to the school's bank on one student's
  # request. That is a school treasury operation, not a student one, and it stays
  # available on the school org itself — which owns its account and so does not
  # reach this branch.
  #
  # Conversely `personal_transfer` on a family venture would be Fuime recording
  # that a guardian owes their own child money out of an account the guardian
  # already owns, which is not a thing Fuime has any business being the ledger for.
  # The family path is a Stripe payout to the guardian's bank, full stop.
  def destination_must_suit_the_account
    return if event.blank?
    # No account anywhere in the tree yet, so neither destination is reachable and
    # neither message would be true. Fuime::PayoutService raises NotSetUp, which
    # says the useful thing ("payment setup isn't finished").
    return if event.payment_account.blank?

    if personal_transfer? && !event.shares_payment_account?
      errors.add(:destination,
                 "isn't available on this venture — money goes to the bank account " \
                 "attached to its own Stripe account.")
    end

    if account_owner_bank? && event.shares_payment_account?
      errors.add(:destination,
                 "isn't available on a venture inside a school programme, because the " \
                 "balance is held in the school's account. Request a transfer to your " \
                 "own account instead.")
    end
  end

end
