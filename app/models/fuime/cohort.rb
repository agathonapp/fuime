# frozen_string_literal: true

# Fuime: a group of founders one person vouched for, once, in advance.
#
# See CreateFuimeCohorts for why this exists, why it is not a bypass of the
# vetting control, and why a code must carry both an expiry and a cap.
#
# == Schema Information
#
# Table name: fuime_cohorts
#
#  id            :bigint           not null, primary key
#  archived_at   :datetime
#  auto_approve  :boolean          default(TRUE), not null
#  code          :string           not null
#  expires_at    :datetime         not null
#  max_members   :integer          not null
#  name          :string           not null
#  rationale     :text             not null
#  risk_level    :string           default("slight"), not null
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#  created_by_id :bigint           not null
#
# Indexes
#
#  index_fuime_cohorts_on_created_by_id  (created_by_id)
#  index_fuime_cohorts_on_upper_code     (upper((code)::text)) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (created_by_id => users.id)
#
# Check Constraints
#
#  fuime_cohorts_capped  (max_members > 0) NOT VALID
#
module Fuime
  class Cohort < ApplicationRecord
    self.table_name = "fuime_cohorts"

    belongs_to :created_by, class_name: "User"

    has_many :applications, class_name: "Event::Application",
                            foreign_key: :fuime_cohort_id, inverse_of: false,
                            dependent: :nullify
    has_many :events, class_name: "::Event", foreign_key: :fuime_cohort_id,
                      inverse_of: false, dependent: :nullify

    MAX_NAME_LENGTH = 80
    MIN_CODE_LENGTH = 4
    MAX_CODE_LENGTH = 24

    # Letters and digits only, and no separators.
    #
    # This is read aloud in a room and typed by fifty people at once, so anything
    # that survives being misheard is worth removing: hyphens land as spaces,
    # spaces get trimmed inconsistently, and a code that differs from what the
    # organiser said is fifty people who cannot get in.
    CODE_FORMAT = /\A[A-Z0-9]+\z/

    validates :name, presence: true, length: { maximum: MAX_NAME_LENGTH }
    validates :rationale, presence: true
    validates :expires_at, presence: true
    validates :max_members, numericality: { only_integer: true, greater_than: 0 }
    validates :code,
              presence: true,
              length: { minimum: MIN_CODE_LENGTH, maximum: MAX_CODE_LENGTH },
              format: { with: CODE_FORMAT,
                        message: "can use letters and numbers only — no spaces or dashes"
}
    validates :risk_level, inclusion: { in: ::Event.risk_levels.keys }

    before_validation :normalise_code

    scope :live, -> { where(archived_at: nil).where(expires_at: Time.current..) }

    # Find a usable cohort for a code somebody typed.
    #
    # Returns nil for unknown, archived and expired alike — a founder who mistypes
    # and a founder holding a dead code both simply do not get in, and the
    # difference is not something the form needs to explain to a stranger.
    #
    # Case-insensitive to match the unique index, which is on UPPER(code).
    def self.for_code(typed)
      typed = typed.to_s.strip.upcase
      return nil if typed.blank?

      live.find_by(code: typed)
    end

    def archived? = archived_at.present?
    def expired?  = expires_at.present? && expires_at <= Time.current

    # Deliberately not `destroy`. Killing a code must not erase the record of who
    # was admitted under it — that record is the only way to review a decision
    # afterwards, which is what makes a bulk decision reviewable at all.
    def archive!
      update!(archived_at: Time.current) unless archived?
    end

    def member_count = applications.count

    def full? = member_count >= max_members

    # Why this code will not admit anybody right now, or nil.
    #
    # Reasons rather than a boolean for the same purpose as
    # Guardianship#activation_blockers and Fuime::OperatorEligibility#blockers:
    # every caller either shows this to an organiser or logs it, and a bare false
    # makes each of them re-derive the why. Shown on the admin roster, never to
    # the founder typing the code.
    def admission_blocker
      return "This code has been turned off." if archived?
      return "This code expired #{expires_at.to_fs(:long)}." if expired?
      return "This code has reached its limit of #{max_members}." if full?
      return "Automatic admission is off for this cohort." unless auto_approve?

      nil
    end

    def admitting? = admission_blocker.nil?

    # The sentence written into every vetting note this cohort produces.
    #
    # States what actually happened and nothing else. It does not say the venture
    # looks legitimate, is low risk, or was reviewed — because none of that
    # happened, and Event#record_vetting_decision! stamps this with a named human,
    # so anything more would be a judgement attributed to somebody who did not
    # make it. What IS true, and is the whole basis of the decision, is that a
    # named person vouched for this group in advance and wrote down why.
    def vetting_note
      "Approved automatically on admission to \"#{name}\" (code #{code}), " \
        "a cohort created by #{created_by.name} on #{created_at.to_fs(:long)}. " \
        "Their stated basis: #{rationale.strip}"
    end

    private

    def normalise_code
      self.code = code.to_s.strip.upcase.gsub(/[\s_-]+/, "") if code.present?
    end

  end
end
