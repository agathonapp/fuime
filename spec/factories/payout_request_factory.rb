# frozen_string_literal: true

FactoryBot.define do
  factory :payout_request do
    association :event
    association :requested_by, factory: :user, birthday: 15.years.ago.to_date

    amount_cents { 5_000 }

    # Approved states need an approver who is genuinely an overseeing guardian,
    # because PayoutRequest validates that. Callers that need a realistic
    # approval should build the guardianship and pass `approved_by:` themselves;
    # these traits exist for tests that only care about state.
    trait :approved do
      aasm_state { "approved" }
      approved_at { 1.minute.ago }
      stripe_payout_id { "po_#{SecureRandom.hex(8)}" }
    end

    trait :rejected do
      aasm_state { "rejected" }
      rejected_at { 1.minute.ago }
      rejection_reason { "Let's keep it in the business for now." }
    end

    trait :paid do
      approved
      aasm_state { "paid" }
      paid_at { Time.current }
    end

    trait :failed do
      approved
      aasm_state { "failed" }
      failure_code { "account_closed" }
      failure_message { "The bank account has been closed." }
    end
  end
end
