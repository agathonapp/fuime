# frozen_string_literal: true

# == Schema Information
#
# Table name: guardianships
#
#  id                   :bigint           not null, primary key
#  guardian_id          :bigint           not null
#  minor_id             :bigint           not null
#  status               :integer          default(0), not null
#  agreement_signed_at  :datetime
#  invite_token         :string
#  invite_sent_at       :datetime
#  created_at           :datetime         not null
#  updated_at           :datetime         not null
#
# Indexes
#
#  index_guardianships_on_guardian_id               (guardian_id)
#  index_guardianships_on_guardian_id_and_minor_id  (guardian_id, minor_id) UNIQUE
#  index_guardianships_on_invite_token              (invite_token) UNIQUE
#  index_guardianships_on_minor_id                  (minor_id)
#
# Foreign Keys
#
#  fk_rails_...  (guardian_id => users.id)
#  fk_rails_...  (minor_id => users.id)
#
class Guardianship < ApplicationRecord
  belongs_to :guardian, class_name: "User"
  belongs_to :minor, class_name: "User"

  enum :status, { pending: 0, active: 1, revoked: 2 }, default: :pending

  validates :guardian_id, uniqueness: { scope: :minor_id, message: "already has a guardianship with this minor" }
  validates :invite_token, uniqueness: true, allow_nil: true

  validate :guardian_must_be_adult
  validate :minor_must_be_under_18
  validate :guardian_and_minor_must_be_different

  before_create :generate_invite_token

  scope :for_minor, ->(user) { where(minor: user) }
  scope :for_guardian, ->(user) { where(guardian: user) }

  def accept!
    result = update!(
      status: :active,
      agreement_signed_at: Time.current,
      invite_token: nil
    )

    if result
      GuardianshipMailer.accepted(guardianship: self).deliver_later
    end

    result
  end

  def revoke!
    update!(status: :revoked)
  end

  def pending?
    status == "pending"
  end

  def active?
    status == "active"
  end

  def self.find_by_token(token)
    return nil if token.blank?

    find_by(invite_token: token, status: :pending)
  end

  private

  def generate_invite_token
    self.invite_token ||= SecureRandom.urlsafe_base64(32)
    self.invite_sent_at ||= Time.current
  end

  def guardian_must_be_adult
    return unless guardian.present?

    if guardian.is_minor?
      errors.add(:guardian, "must be 18 or older")
    end
  end

  def minor_must_be_under_18
    return unless minor.present?

    # Allow this validation to pass if minor has no birthday yet (will be set during signup)
    return if minor.birthday.blank?

    unless minor.is_minor?
      errors.add(:minor, "must be under 18")
    end
  end

  def guardian_and_minor_must_be_different
    if guardian_id.present? && guardian_id == minor_id
      errors.add(:guardian, "cannot be the same as minor")
    end
  end
end
