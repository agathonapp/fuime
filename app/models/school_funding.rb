# frozen_string_literal: true

# Fuime: a school moving its own money into its own Stripe balance.
#
# The migration carries the architectural reasoning (why a top-up and not a transfer,
# why this table exists when Stripe already has the Topup object). This model owns the
# STATE, and the one rule worth stating here is what "succeeded" is allowed to mean.
#
# `succeeded` means Stripe said the money landed. It is set from the webhook and
# nowhere else — never from the API response to creating the top-up, which only says
# Stripe accepted the instruction. The distinction is the same one
# Fuime::ConnectPayoutRecorder documents for payouts, and it matters more here,
# because Fuime::SchoolAwardService spends against the balance this produces. A
# funding row that optimistically called itself succeeded would let a school award
# money that is still in ACH transit and might bounce.
#
# The ledger line is written by Fuime::ConnectFundingRecorder, not by this model.
# Same reason: the webhook is Stripe stating what it did.
# == Schema Information
#
# Table name: school_fundings
#
#  id              :bigint           not null, primary key
#  amount_cents    :integer          not null
#  failure_code    :string
#  failure_message :text
#  status          :string           default("pending"), not null
#  succeeded_at    :datetime
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  event_id        :bigint           not null
#  requested_by_id :bigint
#  stripe_topup_id :string
#
# Indexes
#
#  index_school_fundings_on_event_id                 (event_id)
#  index_school_fundings_on_event_id_and_created_at  (event_id,created_at)
#  index_school_fundings_on_requested_by_id          (requested_by_id)
#  index_school_fundings_on_stripe_topup_id          (stripe_topup_id) UNIQUE WHERE (stripe_topup_id IS NOT NULL)
#
# Foreign Keys
#
#  fk_rails_...  (event_id => events.id)
#  fk_rails_...  (requested_by_id => users.id)
#
# Check Constraints
#
#  school_fundings_amount_positive         (amount_cents > 0) NOT VALID
#  school_fundings_status_known            (status::text = ANY (ARRAY['pending'::character varying::text, 'succeeded'::character varying::text, 'failed'::character varying::text, 'canceled'::character varying::text])) NOT VALID
#  school_fundings_succeeded_is_evidenced  (status::text <> 'succeeded'::text OR stripe_topup_id IS NOT NULL AND succeeded_at IS NOT NULL) NOT VALID
#
class SchoolFunding < ApplicationRecord
  include Hashid::Rails
  has_paper_trail

  # The school. Not "the venture" — a student venture is never funded directly, it
  # is awarded from the school's balance (SchoolAward).
  belongs_to :event
  # Nullable: a top-up created in the Stripe Dashboard has no Fuime user behind it.
  belongs_to :requested_by, class_name: "User", optional: true

  STATUSES = %w[pending succeeded failed canceled].freeze

  validates :amount_cents, numericality: { only_integer: true, greater_than: 0 }
  validates :status, inclusion: { in: STATUSES }
  validates :stripe_topup_id, uniqueness: true, allow_nil: true

  validate :school_must_be_institutionally_sponsored

  scope :recent_first, -> { order(created_at: :desc, id: :desc) }
  scope :succeeded, -> { where(status: "succeeded") }
  scope :in_flight, -> { where(status: "pending") }

  def succeeded?
    status == "succeeded"
  end

  def pending?
    status == "pending"
  end

  def failed?
    status == "failed"
  end

  def canceled?
    status == "canceled"
  end

  def amount
    amount_cents / 100.0
  end

  # Money the school has added and Stripe has confirmed. Deliberately NOT the number
  # awards are checked against — that is `Event#balance_v2_cents`, which is the ledger
  # and which also knows about sales revenue, payouts and awards already made. This is
  # only "how much has been topped up", for a business office reconciling its own
  # transfers.
  def self.total_succeeded_cents(event:)
    succeeded.where(event:).sum(:amount_cents)
  end

  private

  # A top-up belongs to a school's account. Nothing breaks if a family venture has one
  # — the money would be theirs and would land in their balance — but it would mean a
  # guardian was asked to ACH money into a venture, which is the "parents fund the
  # business" flow Fuime does not offer and has never designed for. Refused here so it
  # cannot appear by accident.
  def school_must_be_institutionally_sponsored
    return if event.blank?
    return if event.institutionally_sponsored?

    errors.add(:event, "isn't a school programme, so it can't be funded by top-up")
  end

end
