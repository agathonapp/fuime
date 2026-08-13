# frozen_string_literal: true

module Fuime
  # Fuime: create the guardian-owned Stripe account as soon as there is a
  # guardian to own it, rather than at the moment someone first clicks "Set up
  # payments".
  #
  # ── Why eagerly ──────────────────────────────────────────────────────────────
  #
  # Because the account is what everything else hangs off. With one in place the
  # moment a guardianship activates, the guardian's first visit to the payments
  # page is a form that is already half-filled with what Fuime knows about them
  # (ConnectOnboardingService#individual_prefill), Stripe's notification banner
  # has something to attach to, and `account.updated` webhooks start arriving
  # before anyone is waiting on them. Provisioning lazily means the first click
  # pays for an account create, a prefill and an Account Session in series, which
  # is the slowest possible version of the single highest-drop-off screen in the
  # product.
  #
  # Creating the account does NOT enable anything on its own. A Stripe account
  # with no submitted requirements has `charges_enabled: false`, so this changes
  # what the family sees and nothing about what money can do.
  #
  # ── Why it refuses more often than it acts ───────────────────────────────────
  #
  # Each skip below prevents a specific wrong account from existing, and because
  # Stripe's `controller` property is create-only, a wrong account cannot be
  # fixed — the family has to be onboarded again from scratch. So this errs
  # toward doing nothing and leaving the explicit flow to decide.
  #
  # Runs as a job, and every failure is logged rather than raised, because the
  # caller is Guardianship#accept!. A Stripe outage must never be able to stop a
  # parent from signing for their kid.
  class ProvisionConnectAccountJob < ApplicationJob
    queue_as :low

    # `guardianship_id` rather than the record, so a guardianship revoked between
    # enqueue and perform is re-read in its current state rather than acted on as
    # it was.
    def perform(guardianship_id)
      guardianship = ::Guardianship.find_by(id: guardianship_id)
      return if guardianship.blank?
      # Revoked between enqueue and run. The guardian is no longer the responsible
      # adult, so an account created in their name would be wrong from the moment
      # it existed.
      return unless guardianship.active?

      guardianship.minor.events.find_each do |event|
        provision(event, guardianship.guardian)
      end
    end

    private

    def provision(event, guardian)
      return unless provisionable?(event, guardian)

      Fuime::ConnectOnboardingService.new(event:, guardian:).find_or_create_account!

      Rails.logger.info(
        "[Fuime] provisioned connected account for event #{event.id} on guardianship activation"
      )
    rescue StandardError => e
      # Deliberately swallowed, and deliberately StandardError rather than a
      # narrow list. Nothing downstream depends on this job: the guardian can
      # still reach the payments page and create the account themselves through
      # the same idempotent service. So the only thing an escaping exception could
      # achieve is a retry loop hammering Stripe on behalf of a family who has not
      # asked for anything yet.
      #
      # Reported rather than silent, so a systematic failure — a missing key, a
      # Stripe config change — is visible as one alert instead of as a UI bug that
      # every family hits at once.
      Rails.error.report(e, handled: true, context: { event_id: event.id })
    end

    def provisionable?(event, guardian)
      # Already has one. `find_or_create_account!` is idempotent, but returning
      # early keeps this job from touching accounts it has no reason to.
      return false if event.stripe_connected_account&.stripe_id.present?

      # A school is the account holder for every venture beneath it, and the
      # school's own onboarding creates that account with the institution's
      # details. Neither of these ventures should get one of its own — doing so is
      # what splits a programme's balance in two.
      return false if event.institutionally_sponsored?
      return false if event.shares_payment_account?

      # More than one adult could be the owner. `controller` is create-only, so
      # picking wrong here permanently records the wrong parent as the owner of a
      # family's payment account, and `.first` is how one teen's parent ends up
      # owning another's business. The interactive flow refuses the same case
      # (PaymentSetupsController#acting_guardian) and asks; a background job has
      # nobody to ask, so it declines.
      guardians = event.overseeing_guardians.to_a
      return false unless guardians.one? && guardians.first.id == guardian.id

      true
    end

  end
end
