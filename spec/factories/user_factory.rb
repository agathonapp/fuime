# frozen_string_literal: true

FactoryBot.define do
  factory :user do
    email { Faker::Internet.email }
    full_name { Faker::Name.name }
    session_validity_preference { SessionsHelper::SESSION_DURATION_OPTIONS.fetch("3 days") }
    verified { true }
    # Fuime: users default to adults so specs exercise the behaviour they mean
    # to. Fuime treats unknown age as a minor requiring a guardian
    # (User#minor_or_unknown_age?), so a birthday-less factory user is barred
    # from operating a business — correct in production, but it would silently
    # turn unrelated specs into tests of the guardianship gate.
    #
    # Use the :minor / :minor_with_guardian traits to test that gate directly.
    birthday { 30.years.ago.to_date }

    trait :make_admin do
      access_level { :admin }
    end

    trait :make_auditor do
      access_level { :auditor }
    end

    # A teen with no guardian — cannot operate a business.
    trait :minor do
      birthday { 15.years.ago.to_date }
    end

    # A teen whose guardian has accepted — may operate a business.
    trait :minor_with_guardian do
      birthday { 15.years.ago.to_date }

      after(:create) do |user|
        create(
          :guardianship,
          :active,
          minor: user,
          guardian: create(:user, birthday: 40.years.ago.to_date)
        )
      end
    end

    # Age deliberately unknown, as for a user part-way through onboarding or a
    # guardian stub created from an email address.
    trait :unknown_age do
      birthday { nil }
      age_attestation { nil }
    end

    # ── Fuime: the checkbox users, from 2026-08-20 on ────────────────────────
    #
    # Signup asks for a confirmation rather than a date of birth
    # (AddAgeAttestationToUsers), so these are what a real new account looks like:
    # no `birthday`, one attestation. The `:minor` / adult traits above keep their
    # dates because plenty of specs want a specific age, and a stored date still
    # wins — but a spec about the ORDINARY user should reach for these.
    trait :attested_teen do
      birthday { nil }
      age_attestation { :minor_13_plus }
      age_attested_at { Time.current }
    end

    trait :attested_adult do
      birthday { nil }
      age_attestation { :adult_18_plus }
      age_attested_at { Time.current }
    end
  end
end
