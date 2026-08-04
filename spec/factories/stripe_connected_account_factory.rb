# frozen_string_literal: true

FactoryBot.define do
  factory :stripe_connected_account do
    association :event
    association :owner, factory: :user

    # Default is the honest starting point: a row created just before the Stripe
    # API call, with nothing mirrored yet. Traits below advance it through the
    # states Stripe actually puts an account in.
    stripe_id { "acct_#{SecureRandom.hex(8)}" }

    # Mirrors what Stripe returns for the default profile, with STRING keys as the
    # API delivers them. Set in the base factory so every existing trait satisfies
    # `controller_matches_requested_profile?` — an account whose controller does not
    # match its profile is a real and alarming state, and it should only appear in
    # tests that ask for it.
    controller_profile { "payments_only" }
    controller do
      {
        "losses"                 => { "payments" => "stripe" },
        "fees"                   => { "payer" => "account" },
        "requirement_collection" => "stripe",
        "stripe_dashboard"       => { "type" => "none" },
        "type"                   => "account"
      }
    end

    # The card cohort: Fuime carries the loss risk, collects the guardian's
    # identity details, and pays Stripe's processing fees. See
    # Fuime::ConnectOnboardingService::PROFILES for what each of those costs.
    trait :cards_enabled do
      controller_profile { "cards_enabled" }
      controller do
        {
          "losses"                 => { "payments" => "application" },
          "fees"                   => { "payer" => "application" },
          "requirement_collection" => "application",
          "stripe_dashboard"       => { "type" => "none" },
          "type"                   => "application"
        }
      end
    end

    # Card issuing live. Composed on top of :ready and :cards_enabled by callers.
    trait :cards_active do
      cards_enabled
      details_submitted { true }
      charges_enabled { true }
      payouts_enabled { true }
      onboarded_at { 1.day.ago }
      stripe_synced_at { 1.minute.ago }
      capabilities do
        { "card_payments" => "active", "transfers" => "active", "card_issuing" => "active" }
      end
    end

    # Stripe returned something other than what was requested — the failure mode
    # the mixed-fleet inference could actually produce.
    trait :profile_mismatch do
      controller_profile { "cards_enabled" }
      controller do
        {
          "losses"                 => { "payments" => "stripe" },
          "fees"                   => { "payer" => "account" },
          "requirement_collection" => "stripe",
          "stripe_dashboard"       => { "type" => "none" }
        }
      end
      capabilities { { "card_payments" => "active", "transfers" => "active" } }
    end

    # Guardian started the flow but has not submitted.
    trait :incomplete do
      details_submitted { false }
      charges_enabled { false }
      payouts_enabled { false }
      onboarding_started_at { 5.minutes.ago }
    end

    # Submitted, Stripe still checking. The state most onboarding flows forget
    # exists, and the reason `return` must re-ask Stripe rather than assume.
    trait :verifying do
      details_submitted { true }
      charges_enabled { false }
      payouts_enabled { false }
      onboarded_at { 1.minute.ago }
      requirements { { "pending_verification" => ["individual.verification.document"] } }
    end

    trait :ready do
      details_submitted { true }
      charges_enabled { true }
      payouts_enabled { true }
      onboarded_at { 1.day.ago }
      stripe_synced_at { 1.minute.ago }
      capabilities { { "card_payments" => "active", "transfers" => "active" } }
    end

    # Can charge, cannot yet pay out — a real and confusing state that must not
    # be collapsed into "not ready".
    trait :ready_no_payouts do
      ready
      payouts_enabled { false }
      capabilities { { "card_payments" => "active", "transfers" => "pending" } }
    end

    # Working, but Stripe has asked for more. Must NOT block payments.
    trait :ready_action_needed do
      ready
      requirements { { "currently_due" => ["individual.id_number"] } }
    end

    trait :disabled do
      details_submitted { true }
      charges_enabled { false }
      payouts_enabled { false }
      requirements { { "disabled_reason" => "requirements.past_due", "past_due" => ["individual.id_number"] } }
      disabled_reason { "requirements.past_due" }
    end

    trait :livemode do
      livemode { true }
    end
  end
end
