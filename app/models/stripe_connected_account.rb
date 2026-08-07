# frozen_string_literal: true

# == Schema Information
#
# Table name: stripe_connected_accounts
#
#  id                    :bigint           not null, primary key
#  capabilities          :jsonb            not null
#  charges_enabled       :boolean          default(FALSE), not null
#  controller            :jsonb            not null
#  controller_profile    :string           default("payments_only"), not null
#  details_submitted     :boolean          default(FALSE), not null
#  disabled_reason       :string
#  livemode              :boolean          default(FALSE), not null
#  onboarded_at          :datetime
#  onboarding_started_at :datetime
#  payouts_enabled       :boolean          default(FALSE), not null
#  requirements          :jsonb            not null
#  stripe_synced_at      :datetime
#  created_at            :datetime         not null
#  updated_at            :datetime         not null
#  event_id              :bigint           not null
#  owner_id              :bigint           not null
#  stripe_id             :text
#
# Indexes
#
#  index_stripe_connected_accounts_on_event_id             (event_id) UNIQUE
#  index_stripe_connected_accounts_on_non_default_profile  (controller_profile) WHERE ((controller_profile)::text <> 'payments_only'::text)
#  index_stripe_connected_accounts_on_owner_id             (owner_id)
#  index_stripe_connected_accounts_on_stripe_id            (stripe_id) UNIQUE WHERE (stripe_id IS NOT NULL)
#
# Foreign Keys
#
#  fk_rails_...  (event_id => events.id)
#  fk_rails_...  (owner_id => users.id)
#
# Fuime: the Stripe account a guardian owns on behalf of one venture.
#
# See the migration for why this exists and why it is one-per-venture. In short:
# it replaces the pooled-account model, which is money transmission in production
# (CLAUDE.md L1). Stripe holds the funds; Fuime takes a platform fee and is never
# in the flow of funds.
#
# NOTE ON STATE: this model deliberately does NOT use AASM, even though the repo
# has it and most lifecycle models here do. Stripe owns this object's state —
# `charges_enabled`, `payouts_enabled` and `requirements.disabled_reason` change
# because of things that happen at Stripe (a verification clears, a document
# expires, a review opens), not because of transitions Fuime performs. A local
# state machine would give us a second, authoritative-looking answer that can
# silently disagree with Stripe's, and the failure mode is the worst one
# available: telling a family they can take payments when they cannot, or
# refusing payments Stripe would have accepted. So the Stripe fields are mirrored
# verbatim and `#status` is *derived* from them. The only genuinely local facts
# are the two onboarding timestamps.
class StripeConnectedAccount < ApplicationRecord
  belongs_to :event
  # The adult who owns the account at Stripe. Not `guardian` — the guardianship
  # can be revoked while this account continues to exist and belong to them.
  belongs_to :owner, class_name: "User"

  validates :stripe_id, uniqueness: true, allow_nil: true

  scope :ready, -> { where(charges_enabled: true) }

  # Anything Stripe tells us that isn't one of the columns above is kept in
  # `requirements` as-is. These readers exist so callers never dig into the raw
  # hash with string keys and get nil because Stripe renamed a field.
  def requirements_currently_due
    Array(requirements["currently_due"])
  end

  def requirements_past_due
    Array(requirements["past_due"])
  end

  def requirements_pending_verification
    Array(requirements["pending_verification"])
  end

  def card_payments_capability
    capabilities["card_payments"]
  end

  def transfers_capability
    capabilities["transfers"]
  end

  def card_issuing_capability
    capabilities["card_issuing"]
  end

  # ── Account profile (see the migration and Fuime::ConnectOnboardingService) ──
  #
  # `controller` is create-only at Stripe, so these questions have permanent
  # answers and a venture can never be converted from one profile to the other.

  def cards_profile?
    controller_profile == "cards_enabled"
  end

  # Did Stripe actually build the account the way Fuime asked?
  #
  # Compares only the four properties Fuime sets, not the whole object: Stripe
  # returns additional controller fields (`type`, `is_controller`) that are its own
  # business, and a strict equality check would report a mismatch on every account.
  #
  # Returns false when nothing has been mirrored yet — an unsynced row is not
  # evidence of agreement.
  def controller_matches_requested_profile?
    expected = ::Fuime::ConnectOnboardingService::PROFILES
               .dig(controller_profile.to_sym, :controller)
    return false if expected.blank? || controller.blank?

    controller.dig("losses", "payments") == expected[:losses][:payments] &&
      controller.dig("fees", "payer") == expected[:fees][:payer] &&
      controller["requirement_collection"] == expected[:requirement_collection] &&
      controller.dig("stripe_dashboard", "type") == expected[:stripe_dashboard][:type]
  end

  # Can this venture actually be issued a card right now?
  #
  # Deliberately derived from what STRIPE reports, not from `controller_profile`,
  # which is only Fuime's intent. The mixed-fleet approach that `:cards_enabled`
  # depends on is an inference rather than a documented Stripe pattern, so the
  # possibility that Stripe built something different from what was requested is
  # real and must not be papered over — telling a family they can have a card and
  # then failing at issuance is the worst available outcome.
  def ready_for_cards?
    cards_profile? &&
      controller_matches_requested_profile? &&
      card_issuing_capability == "active"
  end

  # The single question every caller actually has: can this venture accept a card
  # payment right now?
  #
  # `charges_enabled` is Stripe's own answer to exactly this, and the capability
  # check guards the case where charges are broadly enabled but the specific
  # capability Fuime requested has not gone active.
  #
  # Deliberately NOT `&& requirements_currently_due.empty?`. Stripe can leave
  # requirements outstanding on an account it is still happy to charge for — that
  # is a grace period, not an outage — so refusing payments would break ventures
  # Stripe would have accepted money for. Outstanding requirements are surfaced
  # separately via #requirements_outstanding? so a guardian is warned without the
  # teen's storefront going dark.
  def ready_for_payments?
    stripe_id.present? && charges_enabled? && card_payments_capability == "active"
  end

  # Can money actually reach the family's bank account?
  #
  # Separate from #ready_for_payments? on purpose. A venture can legitimately
  # collect before its bank details clear, and collapsing the two produces the
  # one failure a teenager cannot debug: money arrives, then appears stuck.
  def ready_for_payouts?
    payouts_enabled?
  end

  # Stripe wants more information, but has not (yet) switched anything off. Shown
  # as a warning alongside a working storefront rather than as a blocker.
  def requirements_outstanding?
    requirements_currently_due.any? || requirements_past_due.any?
  end

  # Has the guardian finished the Stripe-hosted flow? Distinct from
  # `ready_for_payments?` — Stripe can accept a submission and still be
  # verifying, so "they did their part" and "money can move" are two questions
  # and the UI needs to tell a parent which one is outstanding.
  def onboarding_submitted?
    details_submitted?
  end

  # For display and for choosing which call to action a guardian sees. Ordered
  # most-blocking first so the first true branch is the one worth telling them
  # about.
  def status
    return :not_started if stripe_id.blank?
    return :disabled if disabled_reason.present?
    return :incomplete unless details_submitted?
    return :verifying unless ready_for_payments?
    # Working, but Stripe has asked for something. Ordered after :verifying so a
    # venture that can trade is never described as blocked.
    return :ready_action_needed if requirements_outstanding?
    return :ready_no_payouts unless ready_for_payouts?

    :ready
  end

  # Human-readable, guardian-facing. Kept next to #status so the two cannot
  # drift, and phrased for a parent rather than an engineer — "we're waiting on
  # Stripe" is actionable, "capability inactive" is not.
  def status_description
    case status
    when :not_started then "Payment setup hasn't been started yet."
    when :disabled    then "Stripe has paused this account. #{disabled_reason_description}"
    when :incomplete  then "Payment setup was started but not finished."
    when :verifying   then "Stripe is reviewing the details submitted. This usually takes a few minutes."
    when :ready_action_needed
      "This venture can accept payments, but Stripe needs more information soon to keep it that way."
    when :ready_no_payouts
      "This venture can accept payments. Money can't be transferred out yet — Stripe is still confirming the bank details."
    when :ready then "This venture can accept payments."
    end
  end

  # Stripe's disabled_reason values are dotted identifiers meant for machines
  # (`requirements.past_due`, `rejected.fraud`, `platform_paused`, …) and are not
  # a fixed list, so this translates the ones a Fuime guardian could plausibly
  # hit and passes anything else through rather than pretending to know it.
  def disabled_reason_description
    case disabled_reason
    when "requirements.past_due", "requirements.pending_verification"
      "Some required information is missing or still being checked."
    when "listed", "rejected.fraud", "rejected.terms_of_service", "rejected.listed", "rejected.other"
      "Stripe has declined to support this account. Contact Stripe support — Fuime cannot reverse this."
    when "under_review", "platform_paused"
      "Stripe is reviewing the account."
    when nil
      nil
    else
      "Reason from Stripe: #{disabled_reason}."
    end
  end

  # Mirror a Stripe::Account onto this row. Takes the object rather than fetching
  # it so the same code path serves both a webhook payload and an explicit
  # refresh, and so it is testable without stubbing the network.
  #
  # `livemode` is mirrored too: Fuime runs test mode by default even in
  # production, so without it a test account and a real one are
  # indistinguishable here.
  def sync_from_stripe!(account)
    requirements_hash = stripe_hash(account, :requirements)

    update!(
      stripe_id: account.id,
      charges_enabled: !!account.charges_enabled,
      payouts_enabled: !!account.payouts_enabled,
      details_submitted: !!account.details_submitted,
      disabled_reason: requirements_hash["disabled_reason"],
      requirements: requirements_hash,
      capabilities: stripe_hash(account, :capabilities),
      # Mirrored so `controller_matches_requested_profile?` can compare what Stripe
      # built against what Fuime asked for. Immutable at Stripe, but still synced on
      # every refresh rather than only at create, because a row restored from backup
      # or created before this column existed would otherwise have an empty
      # controller forever and read as a mismatch.
      controller: stripe_hash(account, :controller),
      # v1 Account objects carry no `livemode` field — calling it raises
      # NoMethodError, which crashed sync on the FIRST account this codebase ever
      # created at Stripe (2026-08-05; every shape before that was
      # documentation-derived, and this line was derived wrong). The mode is a
      # property of the KEY that made the request, so record what StripeService
      # says rather than probing the object with try/respond_to?, either of which
      # would silently write false forever.
      livemode: StripeService.mode == :live,
      stripe_synced_at: Time.current,
      # First time Stripe reports a completed submission, record when. Never
      # overwritten, so the date survives a later re-verification cycle.
      onboarded_at: onboarded_at || (account.details_submitted ? Time.current : nil)
    )
  end

  private

  # Stripe objects respond to nested fields as StripeObject, not Hash, and a
  # field can be absent entirely on a freshly created account. Normalises both
  # into a plain string-keyed Hash so the jsonb columns have one shape.
  #
  # Goes through Fuime::StripeHash rather than `to_h` because `to_h` is SHALLOW:
  # nested values stay StripeObjects, and `deep_stringify_keys` does not recurse into
  # them. That mattered once `controller` was mirrored here, since it is two levels
  # deep (`controller.losses.payments`) and the previous implementation only produced
  # a diggable hash by accident of jsonb serialising it on the way to the database.
  def stripe_hash(object, field)
    return {} unless object.respond_to?(field)

    value = object.public_send(field)
    return {} if value.blank?

    ::Fuime::StripeHash.deep(value).deep_stringify_keys
  end

end
