# frozen_string_literal: true

require "net/http"
require "stringio"

module Twilio
  class ProcessWebhookJob < ApplicationJob
    queue_as :critical
    include Rails.application.routes.url_helpers

    # MediaUrlN is caller-supplied even after signature verification.
    # Only fetch HTTPS URLs on Twilio media hosts; never open the raw
    # string with OpenURI (it follows redirects to any host).
    TWILIO_MEDIA_HOSTS = %w[api.twilio.com media.twilio.com twilio.com].freeze
    TWILIO_MEDIA_HOST_SUFFIX = ".twilio.com"
    # Twilio serves the bytes via a single 307 to a short-lived signed S3 URL.
    # Allowed as a redirect target only — never as the original MediaUrl.
    S3_REDIRECT_HOST_PATTERN = /\A(?:.+\.)?s3(?:[.-][a-z0-9-]+)*\.amazonaws\.com\z/i

    def perform(webhook_params:)
      @params = webhook_params.with_indifferent_access
      @user = find_user
      @attachments = fetch_attachments
      @receiptable = find_receiptable
      @report = find_reimbursement_report

      if @user.nil?
        send_reply(<<~MSG.squish)
          Hey! We couldn't find your account on Fuime; if you're looking to upload
          receipts, make sure your phone number is set and verified in your account's settings
          (#{my_settings_url}).
        MSG
        return
      end

      if reimbursement?
        @report ||= @user.reimbursement_reports.create(inviter: @user)
        @receiptable = @report.expenses.create!(amount_cents: 0)
      end

      if @attachments.none?
        send_reply(<<~MSG.squish)
          Hey! Are you trying to upload receipts? We couldn't find any attachments in your message.
          If you're looking for Fuime support, please reach out to support@fuime.com.
        MSG
        return
      end

      receipts = ::ReceiptService::Create.new(
        receiptable: @receiptable,
        uploader: @user,
        attachments: @attachments,
        upload_method: reimbursement? ? "sms_reimbursement" : "sms"
      ).run!

      if reimbursement? && receipts.first.suggested_memo
        @receiptable.update(memo: receipts.first.suggested_memo, value: receipts.first.extracted_total_amount_cents.to_f / 100)
      end

      if reimbursement? && @report.previously_new_record?
        send_reply("Attached #{receipts.count} #{"receipt".pluralize(receipts.count)} to a new reimbursement report! #{reimbursement_report_url(@report)}")
      elsif reimbursement?
        send_reply("Attached #{receipts.count} #{"receipt".pluralize(receipts.count)} to your report named: #{@report.name}! #{reimbursement_report_url(@report)}")
      elsif @receiptable
        send_reply("Attached #{receipts.count} #{"receipt".pluralize(receipts.count)} to #{@receiptable.memo}! #{hcb_code_url(@receiptable)}")
      else
        send_reply("Added #{receipts.count} #{"receipt".pluralize(receipts.count)} to your Receipt Bin! #{my_inbox_url}")
      end
    end

    private

    def send_reply(message)
      TwilioMessageService::Send.new(@user, message, phone_number: @params["From"]).run!
    end

    def find_user
      potential_users = User.where(phone_number: @params["From"], phone_number_verified: true)
      return potential_users.first if potential_users.count == 1

      user_id = last_sent_message_hcb_code&.canonical_pending_transactions&.last&.stripe_card&.user&.id
      potential_users.find_by(id: user_id)
    end

    def fetch_attachments
      num_media = @params["NumMedia"].to_i
      return [] if num_media.zero?

      (0...num_media).filter_map do |i|
        io = download_twilio_media(@params["MediaUrl#{i}"])
        next if io.nil?

        {
          filename: "SMS_#{Time.now.strftime("%Y-%m-%d-%H:%M")}",
          content_type: @params["MediaContentType#{i}"],
          io: io
        }
      end
    end

    def download_twilio_media(url)
      uri = parse_twilio_media_uri(url)
      return if uri.nil?

      response = http_get(uri, authenticate: true)
      if response.is_a?(Net::HTTPRedirection)
        redirect = parse_redirect_uri(response["location"], origin: uri)
        return if redirect.nil?

        response = http_get(redirect, authenticate: false)
      end

      return unless response.is_a?(Net::HTTPSuccess)

      StringIO.new(response.body)
    end

    def parse_twilio_media_uri(url)
      parse_https_uri(url, host_allowed: method(:twilio_media_host?))
    end

    def parse_redirect_uri(location, origin:)
      return if location.blank?

      uri = URI.parse(location)
      uri = origin + uri if uri.relative?
      # Signed S3 URLs carry the signature in the query string.
      parse_https_uri(uri.to_s, host_allowed: method(:allowed_redirect_host?), allow_query: true)
    rescue URI::InvalidURIError
      nil
    end

    def parse_https_uri(url, host_allowed:, allow_query: false)
      return if url.blank?

      uri = URI.parse(url)
      return unless uri.is_a?(URI::HTTPS)
      return if uri.userinfo.present?
      return unless uri.port == 443
      return if uri.fragment.present?
      return if uri.query.present? && !allow_query
      return if uri.path.blank? || uri.path.include?("..") || uri.path.include?("//")
      return unless host_allowed.call(uri.host)

      components = { host: uri.host.downcase, path: uri.path }
      components[:query] = uri.query if allow_query && uri.query.present?
      URI::HTTPS.build(components)
    rescue URI::InvalidURIError
      nil
    end

    def twilio_media_host?(host)
      return false if host.blank?

      normalized = host.downcase
      TWILIO_MEDIA_HOSTS.include?(normalized) || normalized.end_with?(TWILIO_MEDIA_HOST_SUFFIX)
    end

    def allowed_redirect_host?(host)
      twilio_media_host?(host) || s3_redirect_host?(host)
    end

    def s3_redirect_host?(host)
      host.to_s.match?(S3_REDIRECT_HOST_PATTERN)
    end

    def http_get(uri, authenticate:)
      Net::HTTP.start(
        uri.hostname,
        uri.port,
        use_ssl: true,
        open_timeout: 5,
        read_timeout: 15
      ) do |http|
        request = Net::HTTP::Get.new(uri.request_uri)
        if authenticate
          account_sid = Credentials.fetch(:TWILIO, :ACCOUNT_SID)
          auth_token = Credentials.fetch(:TWILIO, :AUTH_TOKEN)
          request.basic_auth(account_sid, auth_token) if account_sid.present? && auth_token.present?
        end
        http.request(request)
      end
    end

    def find_receiptable
      return nil if reimbursement?

      if last_sent_message_hcb_code && last_sent_message_hcb_code.pt.created_at > 5.minutes.ago
        last_sent_message_hcb_code
      end
    end

    def last_sent_message_hcb_code
      @last_sent_message_hcb_code ||= OutgoingTwilioMessage
                                      .joins(:twilio_message)
                                      .where("twilio_messages.to" => @params["From"])
                                      .where.not(hcb_code: nil)
                                      .last&.hcb_code
    end

    def find_reimbursement_report
      @user&.reimbursement_reports&.where(event_id: nil, updated_at: 24.hours.ago..)&.order(created_at: :desc)&.first
    end

    def reimbursement?
      @params["To"] == "+18023004260"
    end

  end
end
