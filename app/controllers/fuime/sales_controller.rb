# frozen_string_literal: true

module Fuime
  # Fuime: what the business actually sold.
  #
  # Separate from the venture dashboard on purpose. The dashboard answers "what
  # is my money doing" — owed, spent, tax — and is the page a founder checks
  # daily. This answers "what is my business doing", which is a different
  # question asked less often and deserving more room than a card.
  class SalesController < ApplicationController
    before_action :set_event
    before_action :authorize_event

    INTERVALS = Fuime::SalesReport::INTERVALS

    def show
      @interval = INTERVALS.include?(params[:interval]) ? params[:interval] : "month"
      @report = Fuime::SalesReport.new(event: @event)
      @series = @report.revenue_series_filled(interval: @interval)
      @top_offers = @report.top_offers
      @by_jurisdiction = @report.revenue_by_jurisdiction
      @top_customers = @report.top_customers
      @customer_count = @report.customer_count
      @repeat_customer_count = @report.repeat_customer_count
    end

    private

    def set_event
      @event = Event.find_by!(slug: params[:event_slug])
    end

    # `show?` rather than a manage-level check: a guardian reads the ledger and
    # this is the same class of information. The guardian reads and the operator
    # writes (EventPolicy) — there is nothing to write here.
    def authorize_event
      authorize @event, :show?
    end

  end
end
