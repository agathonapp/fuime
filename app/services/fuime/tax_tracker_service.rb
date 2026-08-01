# frozen_string_literal: true

# Fuime: Tax Tracker service
# Computes net income from ledger and tracks IRS $400 self-employment threshold
module Fuime
  class TaxTrackerService
    # IRS self-employment tax threshold
    SELF_EMPLOYMENT_THRESHOLD_CENTS = 400_00

    attr_reader :event

    def initialize(event:)
      @event = event
    end

    # Net income this year (money in - money out)
    def net_income_cents
      income_cents - expenses_cents
    end

    # Total money in this year
    def income_cents
      year_start = Date.current.beginning_of_year
      @income_cents ||= event.canonical_transactions
        .where("date >= ?", year_start)
        .where("amount_cents > 0")
        .sum(:amount_cents)
    end

    # Total money out this year (absolute value)
    def expenses_cents
      year_start = Date.current.beginning_of_year
      @expenses_cents ||= event.canonical_transactions
        .where("date >= ?", year_start)
        .where("amount_cents < 0")
        .sum(:amount_cents)
        .abs
    end

    # Progress toward $400 threshold (0.0 to 1.0+)
    def threshold_progress
      return 0.0 if net_income_cents <= 0
      net_income_cents.to_f / SELF_EMPLOYMENT_THRESHOLD_CENTS
    end

    # Percentage for display (capped at 100 for progress bar)
    def threshold_percentage
      [(threshold_progress * 100).round, 100].min
    end

    # Is over the $400 threshold?
    def over_threshold?
      net_income_cents >= SELF_EMPLOYMENT_THRESHOLD_CENTS
    end

    # Human-readable status
    def status_message
      if net_income_cents < 0
        "Your business has a net loss this year — no tax filing required."
      elsif over_threshold?
        "You'll owe self-employment tax — here's your parent packet."
      else
        remaining = (SELF_EMPLOYMENT_THRESHOLD_CENTS - net_income_cents) / 100.0
        "You're under the filing threshold — we're watching it for you. " \
          "$#{'%.2f' % remaining} until you reach $400."
      end
    end

    # Generate year-end packet data
    def year_end_packet
      {
        business_name: event.name,
        year: Date.current.year,
        total_income: income_cents / 100.0,
        total_expenses: expenses_cents / 100.0,
        net_income: net_income_cents / 100.0,
        threshold: SELF_EMPLOYMENT_THRESHOLD_CENTS / 100.0,
        over_threshold: over_threshold?,
        generated_at: Time.current.iso8601
      }
    end
  end
end
