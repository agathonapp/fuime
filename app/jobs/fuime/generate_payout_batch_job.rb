# frozen_string_literal: true

module Fuime
  # Fuime: the weekly cadence, as a schedule rather than as a promise in a
  # paragraph.
  #
  # Runs on Wednesday for a Friday payout, so the gap between generation and
  # payment is where the manual review happens. Generating on the payout morning
  # would make the approval step theatre — nobody reads fifty lines properly with
  # the money due in an hour.
  #
  # ── Why this is safe to schedule before the model can go live ──────────────
  #
  # `Fuime::PayoutBatchService#generate!` calls `Fuime::Features.merchant_of_record!`,
  # which raises while the flag is off — and the flag cannot be switched on without
  # a counsel-memo reference at boot (config/initializers/fuime_safety_check.rb).
  # So on every environment that exists today this job runs, raises, and does
  # nothing, which is the correct behaviour for a cadence whose money model is not
  # yet legally live.
  #
  # Caught rather than propagated for exactly that reason: a flag being off is the
  # expected state, not an incident, and a weekly error page from the scheduler
  # trains people to ignore the one that matters.
  class GeneratePayoutBatchJob < ApplicationJob
    queue_as :low

    def perform(period_end: Date.current)
      Fuime::PayoutBatchService.new.generate!(period_end:)
    rescue Fuime::Features::Disabled => e
      Rails.logger.info("[Fuime] payout batch generation skipped: #{e.message}")
      nil
    end

  end
end
