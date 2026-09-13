# frozen_string_literal: true

module Fuime
  # Fuime: the single place an adult becomes the responsible adult.
  #
  # ── Why this class exists ───────────────────────────────────────────────
  #
  # `User#age_attestation` has a value that confers adulthood, and the rule the
  # whole minor-protection design rests on is that no form a user controls can
  # produce it: `adult_18_plus` is reachable ONLY by an adult ticking the box
  # on a guardian agreement. Until the family setup wizard there was exactly
  # one such box (`GuardianshipsController#accept`), so "the only path" was a
  # controller action and the comments said so.
  #
  # The wizard adds a second screen with the same box. Two copies of this
  # sequence would be two things to keep in step — and the thing they would
  # drift on is the order, which is load-bearing: the 18+ attestation has to
  # be written BEFORE `activation_blockers` is read, because the blocker it
  # clears is the 18+ one, and it has to be written through the association
  # (`guardianship.guardian`) rather than a second instance of the same user,
  # because `attest_adult_18_plus!` uses `update_columns` and a sibling object
  # would still be holding the old value when the blockers are checked.
  #
  # So both screens call this, and "the only path to adult_18_plus" is true of
  # one object again. ONBOARDING_PLAN §3 names this class.
  #
  # Returns a Result. Never raises for an expected refusal; callers render
  # `error` and stay on the page.
  class GuardianConsentService
    Result = Struct.new(:ok, :error, keyword_init: true) do
      def ok? = !!ok
    end

    def initialize(guardianship:, ip: nil, user_agent: nil, notify_minor: true)
      @guardianship = guardianship
      @ip = ip
      @user_agent = user_agent
      @notify_minor = notify_minor
    end

    def call
      return Result.new(ok: true) if @guardianship.active?

      # The tick the caller already confirmed carries three claims — "I am the
      # parent or legal guardian of X", "I am 18 or older", "I agree". This is
      # where the second one is recorded, and it is the only place in the
      # application that can record it.
      @guardianship.guardian.attest_adult_18_plus!(ip: @ip, user_agent: @user_agent)

      blockers = @guardianship.activation_blockers
      return Result.new(ok: false, error: blockers.to_sentence) if blockers.any?

      accepted = @guardianship.accept!(
        consent_ip: @ip,
        consent_user_agent: @user_agent,
        notify_minor: @notify_minor
      )

      return Result.new(ok: false, error: "We couldn't record your consent. Please try again.") unless accepted

      Result.new(ok: true)
    end

  end
end
