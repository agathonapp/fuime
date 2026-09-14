# frozen_string_literal: true

module Fuime
  # Fuime: what a founder's business actually did — the questions the ledger
  # cannot answer.
  #
  # ── Why this is not the ledger ───────────────────────────────────────────
  #
  # HCB's ledger is a record of transactions, aggregated by memo prefix. It can
  # tell a founder their balance and what they spent. It cannot tell them what
  # they SELL — which product earned most, whether last month beat this one, what
  # an average order is worth — because a sale's identity is in its memo string
  # and an offer has no association to the money it made.
  #
  # Fuime::Sale is the spine that fixes that, and this reads it. Every number
  # here is a COUNT or a SUM over rows the webhook handler wrote as a side effect
  # of posting a ledger line, so a figure here always has a ledger line behind it.
  #
  # ⚠️ This is reporting, and must never become a second source of truth for
  # money. What a founder is OWED is Fuime::PayablesLedger, computed from
  # canonical transactions with holds, reserves and refunds applied. A number
  # here is "what was sold", not "what you can be paid".
  #
  # ── What it deliberately does not answer ─────────────────────────────────
  #
  # **Refund rate.** Refunds are ledger reversals and are not written here, so a
  # refunded sale still appears as revenue. Adding a half-answer — refunds from
  # one source, sales from another — would produce a number that disagrees with
  # the payouts page for reasons nobody could explain. See #caveats.
  #
  # **Churn and cohorts.** Now possible in principle — Fuime::Customer exists —
  # but a churn number needs subscription STATE (who is currently active), and
  # only completed sales are stored. Guessing it from gaps between purchases
  # produces a figure that disagrees with Stripe.
  class SalesReport
    INTERVALS = %w[day week month].freeze

    # Frozen SQL per interval, looked up rather than interpolated.
    #
    # `revenue_series` validates its argument against INTERVALS first, so
    # interpolating was safe in practice — but it is the wrong shape: the guard
    # and the query are separated by enough lines that a future edit could move
    # one without the other, and a reader has to prove the safety rather than
    # see it. A lookup cannot express an injection at all, whatever the caller
    # passes. (Flagged by CodeQL `rb/sql-injection`, and it was right to.)
    INTERVAL_SQL = {
      "day"   => Arel.sql("date_trunc('day', occurred_at)"),
      "week"  => Arel.sql("date_trunc('week', occurred_at)"),
      "month" => Arel.sql("date_trunc('month', occurred_at)")
    }.freeze

    def initialize(event:, since: nil, until_time: nil)
      @event = event
      @since = since
      @until = until_time
    end

    def sale_count = scope.count

    def total_revenue_cents = scope.sum(:amount_cents)

    # Guarded rather than relying on Ruby's ZeroDivisionError semantics: this
    # renders on a dashboard a founder sees before their first sale, and the
    # empty state has to be a number rather than a crash.
    def average_sale_cents
      count = sale_count
      return 0 if count.zero?

      (total_revenue_cents.to_f / count).round
    end

    # {Time => cents}, one entry per bucket that HAS a sale.
    #
    # Sparse on purpose: filling empty buckets is a presentation decision — a
    # chart wants zeroes, a table wants them omitted — and a service that guesses
    # produces the wrong one half the time. #revenue_series_filled is the chart's
    # version.
    def revenue_series(interval: "month")
      grouping = INTERVAL_SQL[interval.to_s]
      if grouping.blank?
        raise ArgumentError, "interval must be one of #{INTERVALS.join(', ')}"
      end

      scope
        .group(grouping)
        .sum(:amount_cents)
        .transform_keys { |t| t.in_time_zone }
        .sort
        .to_h
    end

    # The same series with every empty bucket present as a zero, so a chart shows
    # a quiet month as a gap in revenue rather than closing it up and implying
    # sales that did not happen.
    def revenue_series_filled(interval: "month", from: nil, to: nil)
      actual = revenue_series(interval:)
      return {} if actual.empty? && from.blank?

      step = { "day" => 1.day, "week" => 1.week, "month" => 1.month }.fetch(interval.to_s)
      cursor = (from || actual.keys.first).beginning_of_day
      last = to || actual.keys.last

      series = {}
      while cursor <= last
        key = truncate(cursor, interval)
        series[key] = actual[key] || 0
        cursor += step
      end
      series
    end

    # [{offer:, offer_name:, revenue_cents:, sale_count:}], richest first.
    #
    # `offer_name` is carried separately from `offer` because an offer can be
    # archived or renamed after the sale, and a report of what a founder sold
    # last quarter should still name it. A nil `offer` with a present name is a
    # sale of something that no longer exists, which is a true thing to show.
    def top_offers(limit: 5)
      by_offer = scope.where.not(fuime_offer_id: nil)
                      .group(:fuime_offer_id)
                      .pluck(Arel.sql("fuime_offer_id, SUM(amount_cents), COUNT(*)"))

      offers = ::Fuime::Offer.where(id: by_offer.map(&:first)).index_by(&:id)

      by_offer
        .sort_by { |(_, revenue, _)| -revenue }
        .first(limit)
        .map do |offer_id, revenue, count|
          offer = offers[offer_id]
          {
            offer:,
            offer_name: offer&.name || "a product that has since been removed",
            revenue_cents: revenue,
            sale_count: count
          }
        end
    end

    # Sales with no offer — the free-amount path, where a customer was told a
    # price in person. Reported separately rather than bucketed into "other", so
    # a founder can see how much of their business happens off the storefront.
    def unattributed_revenue_cents = scope.where(fuime_offer_id: nil).sum(:amount_cents)

    # {"US-CA" => cents}. Fuime's nexus question, and a founder's "where are my
    # customers" question, are the same query.
    def revenue_by_jurisdiction
      scope.where.not(country: nil)
           .group(:country, :state)
           .sum(:amount_cents)
           .transform_keys { |(country, state)| [country, state].compact.join("-") }
           .sort_by { |_, cents| -cents }
           .to_h
    end

    # ── Who bought ──────────────────────────────────────────────────────────
    #
    # A founder needs this to run the business: you cannot mow a lawn without
    # knowing whose it is. See Fuime::Customer for whose customer this legally
    # is under merchant-of-record, and what that obliges the terms to say.
    def customers
      ::Fuime::Customer.where(event: @event)
                       .where(id: scope.select(:fuime_customer_id))
    end

    def customer_count = customers.count

    # The single most useful thing a small business can know. Counted from sales
    # in the window rather than from the customer row, so "repeat customers this
    # year" means what it says.
    def repeat_customer_count
      scope.where.not(fuime_customer_id: nil)
           .group(:fuime_customer_id)
           .having("COUNT(*) > 1")
           .count
           .size
    end

    # [{customer:, revenue_cents:, purchase_count:}], biggest spender first.
    def top_customers(limit: 5)
      rows = scope.where.not(fuime_customer_id: nil)
                  .group(:fuime_customer_id)
                  .pluck(Arel.sql("fuime_customer_id, SUM(amount_cents), COUNT(*)"))

      people = ::Fuime::Customer.where(id: rows.map(&:first)).index_by(&:id)

      rows.sort_by { |(_, revenue, _)| -revenue }
          .first(limit)
          .filter_map do |customer_id, revenue, count|
            person = people[customer_id]
            next if person.blank?

            { customer: person, revenue_cents: revenue, purchase_count: count }
          end
    end

    # Said out loud on any surface that renders these numbers, because a figure a
    # founder cannot reconcile against their payout is worse than no figure.
    def caveats
      [
        "Refunds and chargebacks are not subtracted — a refunded sale still counts here.",
        "This is what you sold, not what you're owed. Your payout is on the payouts page."
      ]
    end

    private

    def truncate(time, interval)
      case interval.to_s
      when "day" then time.beginning_of_day
      when "week" then time.beginning_of_week
      else time.beginning_of_month
      end
    end

    def scope
      rel = ::Fuime::Sale.where(event: @event)
      rel = rel.where(occurred_at: @since..) if @since
      rel = rel.where(occurred_at: ..@until) if @until
      rel
    end

  end
end
