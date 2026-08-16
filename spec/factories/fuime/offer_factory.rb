# frozen_string_literal: true

FactoryBot.define do
  factory :fuime_offer, class: "Fuime::Offer" do
    association :event
    name { "Front and back lawn mow" }
    # Every caller supplies one implicitly through this factory, which is fine —
    # but note the MODEL has no default, deliberately (see Fuime::Offer's
    # header). A factory default is a test convenience; a schema default would be
    # Fuime setting an operator's rate.
    price_cents { 35_00 }
    unit_label { "per visit" }

    trait :published do
      after(:create) { |offer| offer.publish! }
    end

    trait :archived do
      aasm_state { "archived" }
    end
  end
end
