# frozen_string_literal: true

FactoryBot.define do
  factory :guardianship do
    association :guardian, factory: :user, birthday: 40.years.ago.to_date
    association :minor, factory: :user, birthday: 15.years.ago.to_date

    status { :pending }

    trait :active do
      status { :active }
      agreement_signed_at { Time.current }
      agreement_version { Guardianship::CURRENT_AGREEMENT_VERSION }
      invite_token { nil }
    end

    trait :revoked do
      status { :revoked }
      revoked_at { Time.current }
      invite_token { nil }
    end

    # A pending invite whose link has aged past Guardianship::INVITE_VALID_FOR.
    trait :expired_invite do
      status { :pending }
      invite_sent_at { (Guardianship::INVITE_VALID_FOR + 1.day).ago }
    end
  end
end
