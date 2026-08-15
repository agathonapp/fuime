# frozen_string_literal: true

FactoryBot.define do
  factory :fuime_payout_batch, class: "Fuime::PayoutBatch" do
    period_start { Date.current - 7 }
    period_end   { Date.current }
    payout_on    { Fuime::PayablesLedger.next_payout_on }

    # The defaults, copied the way Fuime::PayoutBatchService copies them. Specs
    # that care about a dial override it here rather than stubbing the env, which
    # is also how a batch behaves in production: it reads its own row, never the
    # configuration.
    hold_days            { Fuime::PayoutPolicy::DEFAULT_HOLD_DAYS }
    reserve_basis_points { Fuime::PayoutPolicy::DEFAULT_RESERVE_BASIS_POINTS }
    reserve_window_days  { Fuime::PayoutPolicy::DEFAULT_RESERVE_WINDOW_DAYS }
    maximum_cents        { Fuime::PayoutPolicy::DEFAULT_MAXIMUM_CENTS }
    minimum_cents        { Fuime::PayoutPolicy::DEFAULT_MINIMUM_CENTS }

    trait :approved do
      aasm_state { "approved" }
      approved_at { 1.minute.ago }
      association :approved_by, factory: [:user, :make_admin]
    end

    trait :paid do
      approved
      aasm_state { "paid" }
      paid_at { Time.current }
      association :paid_by, factory: [:user, :make_admin]
    end

    trait :cancelled do
      aasm_state { "cancelled" }
      cancelled_at { 1.minute.ago }
      cancellation_reason { "Generated against the wrong period." }
    end
  end
end
