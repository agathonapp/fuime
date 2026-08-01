# frozen_string_literal: true

class ErrorsController < ApplicationController
  skip_after_action :verify_authorized
  skip_before_action :signed_in_user, only: [:internal_server_error, :timeout]
  before_action :set_error_reference, only: [:internal_server_error]

  def not_found
    render status: :not_found
  end

  def bad_request
    render status: :bad_request, layout: "application"
  end

  def internal_server_error
    render status: :internal_server_error, layout: "application"
  end

  def timeout
    render status: :gateway_timeout, layout: "application"
  end

  def error
    @code = params[:code]
    render status: params[:code], layout: "application"
  end

  private

  def set_error_reference
    @error_reference = ErrorReference.from_request_id(request.uuid)

    # Log the reference alongside the underlying exception so a user-reported
    # code can be traced to a stack trace in `render logs --text ERR-XXXXXXXX`.
    exception = request.env["action_dispatch.exception"]
    Rails.logger.error(
      "[Fuime] #{@error_reference} path=#{request.env['action_dispatch.original_path'] || request.fullpath} " \
      "exception=#{exception&.class} message=#{exception&.message} " \
      "backtrace=#{exception&.backtrace&.reject { |l| l.include?('/gems/') }&.first(10)&.join(' | ')}"
    )
  end

end
