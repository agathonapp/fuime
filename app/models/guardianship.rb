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
  # Bump when the guardian agreement text changes materially. Stored per
  # signature so we can prove which version a given guardian actually agreed to.
  CURRENT_AGREEMENT_VERSION = "2026-08-01-v1"

  # Invite links are bearer tokens granting authority over a minor's account.
  # They expire so a forwarded or leaked email doesn't stay usable forever.
  INVITE_VALID_FOR = 7.days

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

  # Reasons this guardianship cannot go active yet, as user-facing sentences.
  # Empty array means it can. Activation is the moment Fuime starts telling the
  # public "parent-signed account", so every precondition is checked here.
  def activation_blockers
    blockers = []

    if guardian.blank?
      blockers << "This invitation has no guardian attached."
      return blockers
    end

    # Fail closed on unknown age: a stub user created from an email address has
    # no birthday, and must not be able to sign as the responsible adult until
    # they have told us they are one.
    unless guardian.known_adult?
      blockers << "Your date of birth is needed to confirm you're 18 or older before you can sign for this account."
    end

    if guardian.is_minor? == true
      blockers << "A guardian must be 18 or older."
    end

    if guardian_id == minor_id
      blockers << "You cannot be your own guardian."
    end

    blockers
  end

  def activatable?
    activation_blockers.empty?
  end

  # Activate the guardianship. Returns false (without changing state) if any
  # precondition fails — callers should surface #activation_blockers.
  #
  # NOTE: this records agreement to Fuime's guardian terms. Identity
  # verification is NOT yet implemented (docs/fuime/PRODUCTION_READINESS.md
  # §1.2) — until it is, an accepted guardianship proves control of an email
  # address and a self-asserted birthday, not a verified parental relationship.
  def accept!(consent_ip: nil, consent_user_agent: nil)
    return false unless activatable?

    result = update(
      status: :active,
      agreement_signed_at: Time.current,
      agreement_ip: consent_ip,
      agreement_user_agent: consent_user_agent,
      agreement_version: CURRENT_AGREEMENT_VERSION,
      invite_token: nil
    )

    if result
      GuardianshipMailer.accepted(guardianship: self).deliver_later
    end

    result
  end

  # A guardian must be able to withdraw consent — that is a legal requirement,
  # not a feature. Revoking immediately removes the minor's ability to operate
  # a business (see User#permitted_to_operate_business?).
  def revoke!(revoked_by: nil)
    update!(
      status: :revoked,
      revoked_at: Time.current,
      revoked_by_id: revoked_by&.id,
      invite_token: nil
    )
  end

  def invite_expired?
    return false if invite_sent_at.blank?

    invite_sent_at < INVITE_VALID_FOR.ago
  end

  # Re-issue a fresh token for a pending invite whose link has gone stale.
  def resend_invite!
    return false unless pending?

    update!(
      invite_token: SecureRandom.urlsafe_base64(32),
      invite_sent_at: Time.current
    )
    GuardianshipMailer.invite(guardianship: self).deliver_later
    true
  end

  def pending?
    status == "pending"
  end

  def active?
    status == "active"
  end

  # Look up a pending invite by its token. Returns nil for unknown, already
  # accepted, revoked, or EXPIRED tokens — callers surface a single generic
  # "invalid or expired" message so this doesn't become a token oracle.
  def self.find_by_token(token)
    return nil if token.blank?

    guardianship = find_by(invite_token: token, status: :pending)
    return nil if guardianship.nil?
    return nil if guardianship.invite_expired?

    guardianship
  end

  private

  def generate_invite_token
    self.invite_token ||= SecureRandom.urlsafe_base64(32)
    self.invite_sent_at ||= Time.current
  end

  # A guardianship may be CREATED for a guardian whose age we don't know yet —
  # the invite flow makes a stub user from an email address, and they enter
  # their birthday when they onboard to accept. What must never happen is that
  # guardianship going ACTIVE without a confirmed adult, so the strict check
  # lives in #activatable? / #accept! rather than here.
  def guardian_must_be_adult
    return unless guardian.present?

    if guardian.is_minor? == true
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
