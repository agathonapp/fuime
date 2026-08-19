# frozen_string_literal: true

FactoryBot.define do
  factory :fuime_payout_method, class: "Fuime::PayoutMethod" do
    association :event
    association :added_by, factory: :user
    provider { Fuime::PayoutMethod::PLAID }
    # A token, never digits — see the model. The factory models the real shape so
    # a spec cannot accidentally normalise a credential into being acceptable.
    provider_reference { "ba_#{SecureRandom.hex(6)}" }
    institution_name { "Chase" }
    last4 { "1234" }
    account_holder_name { "Alex Guardian" }

    trait :verified do
      after(:create) { |m| m.mark_verified! }
    end
  end
end
