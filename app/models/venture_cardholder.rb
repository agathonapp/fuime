# frozen_string_literal: true

# == Schema Information
#
# Table name: venture_cardholders
#
#  id                        :bigint           not null, primary key
#  requirements              :jsonb            not null
#  role                      :string           not null
#  status                    :string
#  stripe_synced_at          :datetime
#  terms_accepted_at         :datetime
#  terms_accepted_ip         :string
#  terms_accepted_user_agent :text
#  terms_version             :string
#  created_at                :datetime         not null
#  updated_at                :datetime         not null
#  event_id                  :bigint           not null
#  stripe_id                 :text
#  user_id                   :bigint           not null
#
# Indexes
#
#  index_venture_cardholders_on_event_id              (event_id)
#  index_venture_cardholders_on_event_id_and_user_id  (event_id,user_id) UNIQUE
#  index_venture_cardholders_on_stripe_id             (stripe_id) UNIQUE WHERE (stripe_id IS NOT NULL)
#  index_venture_cardholders_on_user_id               (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (event_id => events.id)
#  fk_rails_...  (user_id => users.id)
#
# Fuime: a person who can hold a card on a venture's own Stripe account.
#
# See the migration for the legal structure. The short version: the guardian is the
# ACCOUNTHOLDER (accepts the Accountholder Terms, carries the liability), the teen is
# an AUTHORIZED USER (accepts the Authorized User Terms, holds an access device).
# Stripe's cardholder floor is 13 and Celtic's Authorized User Terms have no minimum
# age, so what makes this legitimate is the role split and the acceptances — not the
# child's age, and not anything being withheld from Stripe.
#
# Like StripeConnectedAccount, this model does NOT use AASM: `status` is Stripe's
# answer about its own object, and a local state machine would give a second,
# authoritative-looking answer that can silently disagree.
class VentureCardholder < ApplicationRecord
  ACCOUNTHOLDER = "accountholder"
  AUTHORIZED_USER = "authorized_user"
  ROLES = [ACCOUNTHOLDER, AUTHORIZED_USER].freeze

  # Bumped when the card terms change. A cardholder on an old version has to
  # re-accept before a new card is issued, which is why the version is stored rather
  # than a bare boolean.
  CURRENT_TERMS_VERSION = "2026-08-card-v1"

  belongs_to :event
  belongs_to :user
  has_many :venture_cards, dependent: :destroy

  validates :role, inclusion: { in: ROLES }
  validates :stripe_id, uniqueness: true, allow_nil: true
  validates :user_id, uniqueness: { scope: :event_id, message: "already has a cardholder on this venture" }

  validate :accountholder_must_be_an_adult_guardian
  validate :authorized_user_must_be_on_the_team

  scope :accountholders, -> { where(role: ACCOUNTHOLDER) }
  scope :authorized_users, -> { where(role: AUTHORIZED_USER) }

  def accountholder?
    role == ACCOUNTHOLDER
  end

  def authorized_user?
    role == AUTHORIZED_USER
  end

  # Has this person accepted the CURRENT terms? An acceptance of a superseded
  # version does not carry forward — that is the whole reason the version is stored.
  def terms_accepted?
    terms_accepted_at.present? && terms_version == CURRENT_TERMS_VERSION
  end

  def accept_terms!(ip: nil, user_agent: nil)
    update!(
      terms_accepted_at: Time.current,
      terms_version: CURRENT_TERMS_VERSION,
      terms_accepted_ip: ip,
      terms_accepted_user_agent: user_agent
    )
  end

  # Can a card be issued to this person right now?
  #
  # Three independent conditions, deliberately not collapsed: the venture's account
  # must genuinely support cards (per Stripe, not per Fuime's intent), Stripe must
  # consider this cardholder usable, and the person must have accepted the terms.
  def issuable?
    event.payment_account&.ready_for_cards? &&
      status == "active" &&
      terms_accepted?
  end

  # Why not, as a sentence. Ordered most-blocking first.
  def issuance_blockers
    blockers = []

    account = event.payment_account
    if account.blank? || !account.cards_profile?
      blockers << "This venture's payment account wasn't set up to support cards. " \
                  "Stripe can't add them to an existing account, so it would need to be set up again."
    elsif !account.ready_for_cards?
      blockers << "Stripe hasn't enabled card issuing on this venture yet."
    end

    blockers << "Stripe hasn't activated this cardholder yet." if stripe_id.present? && status != "active"
    blockers << "The card terms haven't been accepted yet." unless terms_accepted?

    blockers
  end

  def sync_from_stripe!(cardholder)
    update!(
      stripe_id: cardholder.id,
      status: cardholder.status,
      requirements: stripe_hash(cardholder, :requirements),
      stripe_synced_at: Time.current
    )
  end

  private

  # The responsible adult, and only they, carry the card liability. Enforced here
  # as well as in the issuing service because a row asserting that a minor is the
  # Accountholder would misstate who is on the hook to anyone reading it later.
  #
  # Who that adult is depends on who took responsibility for the venture. For a
  # family venture it is the guardian. For one inside a school programme there is
  # no guardian by design, so requiring one here did not make schools safer — it
  # made cards unissuable, which in turn made "leave the money in the account and
  # reinvest it" unreachable for a school student, since spending the balance is
  # what a card is for.
  #
  # The adult check itself never relaxes. #known_adult? still applies on both
  # branches, so the substitution is only ever one adult for another.
  def accountholder_must_be_an_adult_guardian
    return unless accountholder?
    return if user.blank? || event.blank?
    return if user.admin?

    unless user.known_adult?
      errors.add(:user, "must be a confirmed adult to be the accountholder")
      return
    end

    if event.institutionally_sponsored?
      unless OrganizerPosition.role_at_least?(user, event, :manager)
        errors.add(:user, "must be a manager of the sponsoring school to be the accountholder")
      end

      return
    end

    unless event.overseeing_guardians.exists?(id: user_id)
      errors.add(:user, "must be a guardian overseeing this venture to be the accountholder")
    end
  end

  # An authorized user holds a card for the business, so they have to actually be
  # part of it. Guardians are excluded here rather than merely unnecessary: a
  # guardian holding an authorized-user card would put them in the operating role
  # the guardianship design keeps them out of.
  def authorized_user_must_be_on_the_team
    return unless authorized_user?
    return if user.blank? || event.blank?
    return if user.admin?

    unless OrganizerPosition.exists?(user_id:, event_id: event.id, deleted_at: nil)
      errors.add(:user, "must hold a position on this venture to be an authorized user")
    end
  end

  # Same normalisation as StripeConnectedAccount: Stripe returns nested fields as
  # StripeObject, and a field can be absent on a fresh object.
  def stripe_hash(object, field)
    return {} unless object.respond_to?(field)

    value = object.public_send(field)
    return {} if value.blank?

    value.to_h.deep_stringify_keys
  end

end
