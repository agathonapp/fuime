# frozen_string_literal: true

# == Schema Information
#
# Table name: guardianships
#
#  id                   :bigint           not null, primary key
#  agreement_ip         :string
#  agreement_signed_at  :datetime
#  agreement_user_agent :string
#  agreement_version    :string
#  invite_sent_at       :datetime
#  invite_token         :string
#  revoked_at           :datetime
#  status               :integer          default(0), not null
#  created_at           :datetime         not null
#  updated_at           :datetime         not null
#  guardian_id          :bigint           not null
#  minor_id             :bigint           not null
#  revoked_by_id        :bigint
#
# Indexes
#
#  index_guardianships_on_guardian_id               (guardian_id)
#  index_guardianships_on_guardian_id_and_minor_id  (guardian_id,minor_id) UNIQUE
#  index_guardianships_on_invite_token              (invite_token) UNIQUE
#  index_guardianships_on_minor_id                  (minor_id)
#  index_guardianships_on_revoked_by_id             (revoked_by_id)
#
# Foreign Keys
#
#  fk_rails_...  (guardian_id => users.id)
#  fk_rails_...  (minor_id => users.id)
#  fk_rails_...  (revoked_by_id => users.id)
#
class Guardianship < ApplicationRecord
  # Bump when the guardian agreement text changes materially. Stored per
  # signature so we can prove which version a given guardian actually agreed to.
  #
  # Bumping is additive and never destructive: add the new partial, change this,
  # and leave the old partial in place. `agreement_partial_for` resolves each
  # stored version to its own file, so a guardian who signed an earlier version
  # keeps seeing the text they actually signed.
  #
  # v2 (2026-08-06) names Ninth Street Labs, LLC as the counterparty. v1 was
  # "between Fuime and you", and Fuime is a product rather than a legal person,
  # so v1 recorded consent to an agreement with nobody.
  CURRENT_AGREEMENT_VERSION = "2026-08-06-v2"

  # Invite links are bearer tokens granting authority over a minor's account.
  # They expire so a forwarded or leaked email doesn't stay usable forever.
  INVITE_VALID_FOR = 7.days

  belongs_to :guardian, class_name: "User"
  belongs_to :minor, class_name: "User"
  # Who withdrew consent. Nil for guardianships revoked before this was
  # recorded, and for any revocation not attributable to a signed-in user.
  belongs_to :revoked_by, class_name: "User", optional: true

  enum :status, { pending: 0, active: 1, revoked: 2 }, default: :pending

  validates :guardian_id, uniqueness: { scope: :minor_id, message: "already has a guardianship with this minor" }
  validates :invite_token, uniqueness: true, allow_nil: true

  validate :guardian_must_be_adult
  validate :minor_must_be_under_18
  validate :guardian_and_minor_must_be_different

  before_create :generate_invite_token

  scope :for_minor, ->(user) { where(minor: user) }
  scope :for_guardian, ->(user) { where(guardian: user) }

  # Active guardianships held by `user` over a minor who holds a position on
  # `event` — i.e. "is this user entitled to oversee this venture?"
  #
  # §3 of the agreement ("You can see everything") promises the guardian
  # visibility that "cannot be turned off by the minor". That sentence is the
  # reason this derives from the guardianship rather than from an
  # OrganizerPosition granted at acceptance: an organizer position is org
  # membership, and a manager — the minor — can delete it, which would make the
  # one guarantee the guardian is asked to rely on revocable by exactly the
  # person it exists to be independent of. Revoking a *guardianship* is already
  # restricted to the guardian and admins (GuardianshipPolicy#revoke?).
  #
  # Positions are soft-deleted (acts_as_paranoid), so the join is scoped to
  # live ones; a removed team member's guardian loses oversight with them.
  scope :overseeing_event, ->(user, event) {
    return none if user.blank? || event.blank?

    active
      .where(guardian: user)
      .joins("INNER JOIN organizer_positions ON organizer_positions.user_id = guardianships.minor_id")
      .where(organizer_positions: { event_id: event.id, deleted_at: nil })
  }

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

  # Partial path for a given agreement version's text. Each version's wording
  # lives in its own file under app/views/guardianships/agreements/ and is never
  # edited in place, so a guardian who signed v1 always sees v1 — not whatever
  # the terms happen to say today.
  #
  # Returns nil for a version with no partial on disk (a guardianship signed
  # under a version whose file was later removed); callers must handle that
  # rather than blow up a record page.
  def self.agreement_partial_for(version)
    return nil if version.blank?

    slug = version.to_s.tr("-", "_")
    # Version strings come from the database, so the slug is checked against a
    # strict allowlist before it is ever interpolated into a path.
    return nil unless slug.match?(/\A[a-z0-9_]+\z/)

    file = Rails.root.join("app", "views", "guardianships", "agreements", "_#{slug}.html.erb")
    return nil unless file.exist?

    "guardianships/agreements/#{slug}"
  end

  # The text this guardianship was actually signed under (or, if unsigned, the
  # text it would be signed under now).
  def agreement_partial
    self.class.agreement_partial_for(agreement_version.presence || CURRENT_AGREEMENT_VERSION)
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
