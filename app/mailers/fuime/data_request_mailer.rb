# frozen_string_literal: true

module Fuime
  # Fuime: tell Fuime that a parent has asked for their child's account to be
  # deleted, and tell the parent it was received.
  #
  # The deadline is the reason this exists as mail rather than only a queue
  # badge. A deletion request has a stated response window
  # (Fuime::DataRequest::RESPONSE_WINDOW_DAYS) that Fuime has promised in writing
  # on the page the parent clicked, and a queue nobody opens is how that promise
  # is broken without anyone deciding to break it.
  class DataRequestMailer < ApplicationMailer
    def ops_alert
      @data_request = params[:data_request]
      @subject_user = @data_request.subject
      @requester = @data_request.requested_by
      @admin_url = fuime_data_requests_admin_index_url

      mail(
        to: ::Fuime::DisputeMailer.ops_address,
        subject: "[Deletion request] #{@subject_user.name || @subject_user.email} — due #{@data_request.due_at.strftime('%b %-d')}"
      ) do |format|
        format.html
        format.text
      end
    end

  end
end
