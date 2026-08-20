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
    # told us nothing, and must not be able to sign as the responsible adult until
    # they have said they are one.
    #
    # ── Why this no longer asks for a date of birth ──────────────────────────
    #
    # It used to read `known_adult?` alone, which before 2026-08-20 could only be
    # satisfied by a stored date of birth — so a parent invited by email had to go
    # to their settings page and enter one before they could sign. Signup no longer
    # asks anybody for a date (AddAgeAttestationToUsers), so that would now be a
    # dead end: the field they were being sent to fill in is gone.
    #
    # The assertion has not been weakened, it has moved to where it was always
    # being made. The acceptance checkbox on this page reads "I confirm I am the
    # parent or legal guardian of X, that I am 18 or older, and I agree to the
    # guardian agreement" — the 18+ claim is IN the thing they are signing.
    # GuardianshipsController#accept records it as `adult_18_plus` when they tick
    # it, which is why this can be satisfied by the attestation.
    #
    # Still fail-closed, and still the one place adulthood can be claimed: a user
    # cannot reach `adult_18_plus` from their own settings form (see
    # User#attest_minor_13_plus!).
    unless guardian.known_adult? || guardian.attested_adult_18_plus?
      blockers << "Please confirm you're 18 or older by ticking the box below before you sign."
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

  # Fuime: reasons to suspect the "guardian" and the minor are the same person.
  #
  # ── The hole this exists for ────────────────────────────────────────────────
  #
  # #accept! below already says what an accepted guardianship proves: control of an
  # email address and a self-asserted birthday. What that note does not say is what
  # rests on it. EventPolicy#decide_payout? resolves to #guardian_reader?, and
  # PayoutRequest#approver_must_not_be_the_requester compares USER IDS — so a teen
  # who registers a second address, asserts an adult birthday on it and accepts
  # their own invitation satisfies both, and approves their own payouts. Every other
  # control on the money-out path is layered twice. This one was one email address
  # deep.
  #
  # ── Why signals and not a block ─────────────────────────────────────────────
  #
  # Because the obvious checks are all TRUE of real families. A parent and their
  # child share a house, so they share an IP; they may share a laptop, so they share
  # a user agent; a parent sitting next to their kid accepts in ninety seconds. Any
  # one of these as a hard gate would refuse the ordinary case, and a control that
  # fails for honest users gets switched off.
  #
  # What makes them useful is that Fuime ALREADY has a human in the money-out loop:
  # no payout leaves except in a batch a Fuime admin approves (Fuime::PayoutBatch).
  # That reviewer had no way to tell a family from one person with two inboxes. Now
  # they do, and they are looking at a list of maybe six lines, not fifty thousand.
  #
  # ── Why nothing is stored ───────────────────────────────────────────────────
  #
  # Every input is already persisted — the consent IP and user agent on this row, the
  # invite and signing timestamps, the two email addresses, and the guardian's own
  # sessions. Deriving on read means no migration, and it means an improved heuristic
  # applies to guardianships signed before it was written.
  #
  # Ordered strongest first. Presence of a signal is not proof; three of them on one
  # venture asking for its first payout is a conversation.
  def self_signed_signals
    return [] unless active?

    signals = []
    signals << "Consent came from the same browser the minor uses." if shared_user_agent?
    signals << "The guardian's email looks like an alias of the minor's." if aliased_email?
    signals << "The guardian has never signed in except to accept this." if no_independent_guardian_activity?
    signals << "Accepted #{ActiveSupport::Duration.build(accepted_within.to_i).inspect} after the invite was sent." if accepted_suspiciously_fast?
    signals << "Consent came from the same IP address the minor uses." if shared_ip?
    signals
  end

  def self_signed_suspected?
    self_signed_signals.size >= 2
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

      # Activation is the moment a venture of this minor's finally has an adult who
      # can legally own its payment account, so it is the earliest honest moment to
      # create one at Stripe. Enqueued rather than inline: a Stripe outage must
      # never be able to stop a parent from signing for their kid, and the job
      # refuses far more often than it acts — see
      # Fuime::ProvisionConnectAccountJob for every case it declines.
      Fuime::ProvisionConnectAccountJob.perform_later(id)
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

  # ── The signals behind #self_signed_signals ─────────────────────────────────
  #
  # Each is deliberately narrow. A signal that fires on ordinary families is worse
  # than no signal, because it trains the reviewer to ignore the column.

  # How long the guardian took to accept.
  def accepted_within
    return nil if invite_sent_at.blank? || agreement_signed_at.blank?

    agreement_signed_at - invite_sent_at
  end

  # Two minutes. A parent who was sitting next to their kid takes a few minutes;
  # under two means the acceptance email was opened by somebody already waiting for
  # it, which is one person with two inboxes far more often than it is a very fast
  # parent. The weakest signal here, and last in the list for that reason.
  FAST_ACCEPTANCE = 2.minutes

  def accepted_suspiciously_fast?
    within = accepted_within
    within.present? && within < FAST_ACCEPTANCE
  end

  # Session fingerprints belonging to a user.
  #
  # `fingerprint` is the client-side browser fingerprint LoginsController collects;
  # User::Session already treats a new one as a new device (see
  # #notify_of_new_device). Comparing fingerprint to fingerprint keeps this
  # apples-to-apples — the alternative would be comparing this row's
  # `agreement_user_agent` header against a fingerprint, which are different kinds
  # of thing.
  #
  # `not_expired` is deliberately not applied: what matters is which browsers the
  # person has ever used, and an expired session is still evidence of that.
  def session_fingerprints_for(user)
    return [] if user.blank?

    user.user_sessions.not_impersonated.where.not(fingerprint: nil).distinct.pluck(:fingerprint)
  end

  # The same browser signed in as both people.
  #
  # Stronger than the IP check below: a household shares one IP through NAT while
  # sharing nothing else, whereas the same fingerprint means the same browser
  # profile on the same machine — which a parent's phone and a teen's laptop are
  # not. This is the signal that actually distinguishes "two people at one address"
  # from "one person with two accounts".
  def shared_user_agent?
    ours = session_fingerprints_for(guardian)
    return false if ours.empty?

    ours.intersect?(session_fingerprints_for(minor))
  end

  # Consent came from an address the minor has signed in from.
  #
  # True of every family at home, so on its own it means nothing — it is here to
  # corroborate, and it is last in the list for that reason. Worth keeping because
  # "same IP AND same browser AND accepted in ninety seconds" is not a family.
  def shared_ip?
    ours = agreement_ip.presence
    return false if ours.blank?

    minor.user_sessions.not_impersonated.where(ip: ours).exists?
  end

  # An email address that looks like the minor's with something appended.
  #
  # Catches the cheapest version of this: `ada@example.com` inviting
  # `ada+mum@example.com`, or `ada.parent@example.com`. Compares the local part
  # with any `+tag` stripped, on the same domain, and asks whether one is a prefix
  # of the other.
  #
  # Bounded to avoid firing on genuinely different people at the same domain: a
  # family sharing `surname.com` with `ada@` and `john@` does not match, because
  # neither local part is a prefix of the other.
  def aliased_email?
    minor_email = minor&.email.to_s.downcase
    guardian_email = guardian&.email.to_s.downcase
    return false if minor_email.blank? || guardian_email.blank?

    minor_local, minor_domain = minor_email.split("@", 2)
    guardian_local, guardian_domain = guardian_email.split("@", 2)
    return false if minor_domain.blank? || minor_domain != guardian_domain

    minor_base = minor_local.split("+").first.to_s
    guardian_base = guardian_local.split("+").first.to_s
    return false if minor_base.blank? || guardian_base.blank?

    # A `+tag` on the same base is the clearest case; otherwise one local part
    # extending the other.
    return true if minor_base == guardian_base

    longer, shorter = [minor_base, guardian_base].sort_by(&:length).reverse
    shorter.length >= 3 && longer.start_with?(shorter)
  end

  # The guardian account exists only to have accepted this.
  #
  # A real parent signs in again — to read the ledger the agreement promises them,
  # to approve a payout, to look at their kid's storefront. An account with one
  # session and no other guardianship is an account that was created to click a
  # button.
  #
  # Deliberately not fired for a guardian of several minors: somebody with two
  # wards is doing something a self-signer has no reason to do.
  def no_independent_guardian_activity?
    return false if guardian.blank?
    return false if guardian.guardianships_as_guardian.active.where.not(id: id).exists?

    guardian.user_sessions.count <= 1
  end

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

    # A minor who has positively asserted adulthood is not somebody who needs a
    # guardian. Checked before the birthday branch because it is the case a
    # checkbox can produce and a date cannot.
    if minor.attested_adult_18_plus?
      errors.add(:minor, "has confirmed they're 18 or older, so they don't need a guardian")
      return
    end

    # Passes when the minor has no birthday on file, which since 2026-08-20 is the
    # ordinary state — signup asks for a confirmation rather than a date, and a
    # "13 or older" tick is consistent with being under 18.
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
