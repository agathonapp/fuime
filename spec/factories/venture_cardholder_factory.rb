# frozen_string_literal: true

FactoryBot.define do
  # VentureCardholder validates real relationships rather than bare attributes: an
  # authorized user must hold a position on the venture, and an accountholder must be
  # an adult guardian overseeing it. Those cannot be expressed as column values, so
  # the hooks below build the surrounding context.
  #
  # Building records in `after(:build)` is unusual, and the alternative was worse:
  # every example needing a cardholder would otherwise repeat four lines of setup, and
  # the ones that forgot would fail on a validation message rather than on the thing
  # they were testing.
  factory :venture_cardholder do
    association :event
    association :user, factory: :user, birthday: 15.years.ago.to_date

    role { VentureCardholder::AUTHORIZED_USER }
    stripe_id { "ich_#{SecureRandom.hex(8)}" }
    status { "active" }

    # Accepted by default: an unaccepted cardholder cannot be issued a card, so
    # examples about issuance would all have to accept first. The :terms_pending trait
    # covers the refusal.
    terms_accepted_at { Time.current }
    terms_version { VentureCardholder::CURRENT_TERMS_VERSION }
    terms_accepted_ip { "203.0.113.7" }

    transient do
      # Set false to test the validations themselves. Without this the hook below
      # helpfully creates the very position an example is trying to prove is
      # required, and the negative case silently passes for the wrong reason —
      # which is exactly what happened the first time these specs ran.
      build_context { true }
    end

    after(:build) do |cardholder, evaluator|
      next unless evaluator.build_context
      next if cardholder.event.blank? || cardholder.user.blank?

      if (cardholder.role == VentureCardholder::AUTHORIZED_USER) && !OrganizerPosition.exists?(user_id: cardholder.user_id, event_id: cardholder.event_id, deleted_at: nil)
        create(:organizer_position, user: cardholder.user, event: cardholder.event)
      end
    end

    # The guardian. Needs a minor on the venture for the guardianship to make them an
    # overseeing guardian of it.
    trait :accountholder do
      role { VentureCardholder::ACCOUNTHOLDER }
      association :user, factory: :user, birthday: 40.years.ago.to_date

      after(:build) do |cardholder, evaluator|
        next unless evaluator.build_context
        next if cardholder.event.blank? || cardholder.user.blank?
        next if cardholder.event.overseeing_guardians.exists?(id: cardholder.user_id)

        minor = create(:user, :minor)
        create(:organizer_position, user: minor, event: cardholder.event)
        create(:guardianship, :active, guardian: cardholder.user, minor:)
      end
    end

    trait :terms_pending do
      terms_accepted_at { nil }
      terms_version { nil }
      terms_accepted_ip { nil }
    end

    # Accepted an older version. Must not count as accepted.
    trait :stale_terms do
      terms_accepted_at { 1.year.ago }
      terms_version { "2026-01-card-v0" }
    end

    trait :not_yet_on_stripe do
      stripe_id { nil }
      status { nil }
    end

    trait :inactive do
      status { "inactive" }
    end
  end

  factory :venture_card do
    association :venture_cardholder

    stripe_id { "ic_#{SecureRandom.hex(8)}" }
    card_type { VentureCard::VIRTUAL }
    last4 { "4242" }
    brand { "Visa" }
    exp_month { 12 }
    exp_year { Date.current.year + 3 }
    status { "active" }
    spending_limit_cents { 25_000 }
    spending_limit_interval { "monthly" }
    commercial_controls_applied { true }
    stripe_synced_at { 1.minute.ago }

    # A card Stripe returned without Fuime's category allowlist. The compliance
    # failure that must never be silent.
    trait :unrestricted do
      commercial_controls_applied { false }
    end

    trait :canceled do
      status { "canceled" }
    end
  end
end
