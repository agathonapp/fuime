# frozen_string_literal: true

FactoryBot.define do
  factory :school_funding do
    # A School plan, not the event factory's FeeWaived default: SchoolFunding refuses
    # any event that is not institutionally sponsored, so the default has to be a
    # school or every use of this factory fails validation for the wrong reason.
    event { create(:event, plan_type: Event::Plan::School) }
    association :requested_by, factory: :user

    amount_cents { 50_000 }
    status { "pending" }

    # The honest default is a row with no Stripe id: that is what exists between
    # Fuime::SchoolFundingService creating it and Stripe answering.
    trait :submitted do
      stripe_topup_id { "tu_#{SecureRandom.hex(8)}" }
    end

    trait :succeeded do
      submitted
      status { "succeeded" }
      succeeded_at { Time.current }
    end

    trait :failed do
      submitted
      status { "failed" }
      failure_code { "debit_not_authorized" }
      failure_message { "The bank account on file could not be debited for this top-up." }
    end
  end
end
