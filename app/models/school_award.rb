# frozen_string_literal: true

# Fuime: a school putting its own money into a student's venture.
#
# Alpha School pays $100 per A. See the migration for why this needs no Stripe call
# (the school and its students share one account, so an award is a reattribution
# between subledgers), why the school's balance must cover it (or a student withdraws
# another student's sales revenue), and why there are no grades anywhere in here
# (FERPA — the school keeps the grades, Fuime keeps the money).
#
# ── Division of labour ──────────────────────────────────────────────────────
#
# This model owns the STATE and the rules that hold regardless of caller.
# Fuime::SchoolAwardService owns the two-sided ledger posting, because that has to
# be one transaction and a validation cannot span one.
# == Schema Information
#
# Table name: school_awards
#
#  id              :bigint           not null, primary key
#  amount_cents    :integer          not null
#  awarded_on      :date             not null
#  reference       :string
#  void_reason     :text
#  voided_at       :datetime
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  awarded_by_id   :bigint           not null
#  awarded_to_id   :bigint           not null
#  event_id        :bigint           not null
#  school_event_id :bigint           not null
#  voided_by_id    :bigint
#
# Indexes
#
#  index_school_awards_on_awarded_by_id                 (awarded_by_id)
#  index_school_awards_on_awarded_to_id                 (awarded_to_id)
#  index_school_awards_on_awarded_to_id_and_awarded_on  (awarded_to_id,awarded_on)
#  index_school_awards_on_event_id                      (event_id)
#  index_school_awards_on_school_event_id               (school_event_id)
#  index_school_awards_on_voided_by_id                  (voided_by_id)
#
# Foreign Keys
#
#  fk_rails_...  (awarded_by_id => users.id)
#  fk_rails_...  (awarded_to_id => users.id)
#  fk_rails_...  (event_id => events.id)
#  fk_rails_...  (school_event_id => events.id)
#  fk_rails_...  (voided_by_id => users.id)
#
# Check Constraints
#
#  school_awards_amount_positive     (amount_cents > 0) NOT VALID
#  school_awards_void_is_attributed  ((voided_at IS NULL) = (voided_by_id IS NULL)) NOT VALID
#
class SchoolAward < ApplicationRecord
  include Hashid::Rails
  has_paper_trail

  # The student venture receiving the money.
  belongs_to :event
  # The school funding it, as recorded at the time — not re-derived from today's tree.
  belongs_to :school_event, class_name: "Event"
  # The student who earned it. Named explicitly because the $600/year 1099-MISC
  # threshold is per person, and a venture can have two co-founders.
  belongs_to :awarded_to, class_name: "User"
  # The guide or business-office member who granted it.
  belongs_to :awarded_by, class_name: "User"
  belongs_to :voided_by, class_name: "User", optional: true

  # The IRS reporting threshold a school crosses at six A's. Not enforced — it is
  # the SCHOOL's filing obligation, not Fuime's, and Fuime is not the withholding
  # agent. Surfaced so nobody discovers it in January.
  REPORTABLE_CENTS = 600_00

  validates :amount_cents, numericality: { only_integer: true, greater_than: 0 }
  validates :awarded_on, presence: true

  validate :venture_must_be_funded_by_this_school
  validate :student_must_be_on_the_venture

  scope :active, -> { where(voided_at: nil) }
  scope :recent_first, -> { order(awarded_on: :desc, id: :desc) }
  scope :in_year, ->(year) { where(awarded_on: Date.new(year, 1, 1)..Date.new(year, 12, 31)) }

  def voided?
    voided_at.present?
  end

  def amount
    amount_cents / 100.0
  end

  # What this school has awarded this student in a calendar year, ignoring voided
  # awards. The figure that decides whether the school owes a 1099-MISC.
  def self.reportable_total_cents(awarded_to:, school_event:, year: Date.current.year)
    active.in_year(year)
          .where(awarded_to:, school_event:)
          .sum(:amount_cents)
  end

  def self.reportable?(awarded_to:, school_event:, year: Date.current.year)
    reportable_total_cents(awarded_to:, school_event:, year:) >= REPORTABLE_CENTS
  end

  private

  # An award may only come from the school whose account actually holds this
  # venture's money.
  #
  # Without this, an award could name any event as the payer, and the two ledger
  # lines would debit a subledger in one Stripe account while crediting one in
  # another — inventing money on the credit side and losing it on the debit side.
  # Conservation only holds inside a single account.
  def venture_must_be_funded_by_this_school
    return if event.blank? || school_event.blank?

    account = event.payment_account
    if account.blank?
      errors.add(:event, "isn't set up to hold money yet")
      return
    end

    unless account.event_id == school_event_id
      errors.add(:school_event, "doesn't hold this venture's money, so it can't fund an award to it")
    end
  end

  # The award names who earned it, so that person has to actually be on the venture.
  # Otherwise the 1099 total accrues against someone with no connection to the
  # business the money went into.
  def student_must_be_on_the_venture
    return if event.blank? || awarded_to.blank?

    unless OrganizerPosition.exists?(user_id: awarded_to_id, event_id: event.id, deleted_at: nil)
      errors.add(:awarded_to, "isn't a member of this venture")
    end
  end

end
