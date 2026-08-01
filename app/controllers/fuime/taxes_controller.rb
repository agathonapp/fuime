# frozen_string_literal: true

# Fuime: Tax Tracker controller
module Fuime
  class TaxesController < ApplicationController
    before_action :set_event
    before_action :authorize_event

    def show
      @tax_tracker = TaxTrackerService.new(event: @event)
    end

    def download_packet
      @tax_tracker = TaxTrackerService.new(event: @event)
      packet = @tax_tracker.year_end_packet

      respond_to do |format|
        format.csv do
          csv_data = generate_csv(packet)
          send_data csv_data,
                    filename: "fuime_tax_packet_#{packet[:year]}_#{@event.slug}.csv",
                    type: "text/csv"
        end
        format.json do
          render json: packet
        end
      end
    end

    private

    def set_event
      @event = Event.find_by!(slug: params[:event_slug])
    end

    def authorize_event
      authorize @event, :show?
    end

    def generate_csv(packet)
      CSV.generate(headers: true) do |csv|
        csv << ["Fuime Year-End Tax Packet"]
        csv << []
        csv << ["Business Name", packet[:business_name]]
        csv << ["Tax Year", packet[:year]]
        csv << ["Generated", packet[:generated_at]]
        csv << []
        csv << ["Summary"]
        csv << ["Total Income", "$#{'%.2f' % packet[:total_income]}"]
        csv << ["Total Expenses", "$#{'%.2f' % packet[:total_expenses]}"]
        csv << ["Net Income", "$#{'%.2f' % packet[:net_income]}"]
        csv << []
        csv << ["IRS Self-Employment Threshold", "$#{'%.2f' % packet[:threshold]}"]
        csv << ["Over Threshold?", packet[:over_threshold] ? "Yes" : "No"]
        csv << []
        csv << ["Note: This is a summary for your records. Consult a tax professional for filing requirements."]
      end
    end
  end
end
