# frozen_string_literal: true

FactoryBot.define do
  factory :fuime_test_sale, class: "Fuime::TestSale" do
    association :event
    association :user
    amount_cents { 35_00 }
    description { "Front and back lawn mow" }
    occurred_at { Time.current }
  end
end
