# frozen_string_literal: true

module Admin
  # Fuime: the marketing site's waitlist, readable by any signed-in admin.
  #
  # It lives here rather than on the site so that "who may see it" is the same
  # question the rest of the admin console already answers — Admin::BaseController's
  # `signed_in_admin`. The alternative was a shared token on the Render service,
  # which is a secret to distribute and revoke by hand and tells you nothing
  # about who looked.
  #
  # Read-only. Nothing in Rails writes to the waitlist; the site's
  # /api/waitlist owns that.
  class WaitlistController < Admin::BaseController
    def index
      load_roster

      respond_to do |format|
        format.html
        format.csv do
          send_data to_csv, filename: "fuime-waitlist-#{Date.current.iso8601}.csv",
                            type: "text/csv", disposition: :attachment
        end
      end
    end

    private

    def load_roster
      @goal = Fuime::WaitlistRoster.goal
      @configured = Fuime::WaitlistRoster.configured?
      @signups = []
      @total = 0
      @error = nil

      return unless @configured

      result = Fuime::WaitlistRoster.new.fetch
      @total = result[:total]
      @signups = result[:signups]
    rescue Fuime::WaitlistRoster::ReadFailed => e
      # A waitlist we cannot read is worth saying out loud on the page. It is
      # not worth a 500 that hides which part failed.
      @error = e.message
      Rails.error.report(e, handled: true)
    end

    def to_csv
      CSV.generate do |csv|
        csv << ["email", "source", "signed_up_at", "ip"]

        @signups.each do |s|
          csv << [
            csv_safe(s.email),
            csv_safe(s.source),
            s.signed_up_at&.iso8601,
            csv_safe(s.ip)
          ]
        end
      end
    end

    # Excel and Sheets execute a cell that opens with =, +, - or @. Every field
    # here was typed by an anonymous stranger into a public form, so none of
    # them may start one.
    def csv_safe(value)
      str = value.to_s
      str.match?(/\A[=+\-@\t\r]/) ? "'#{str}" : str
    end

  end
end
