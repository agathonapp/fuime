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
  # The site's /api/waitlist still owns new signups. Rails may stamp an
  # existing address as invited (G1) and mail a login link; it does not SADD.
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

    def invite
      result = Fuime::WaitlistInviteService
               .new(invited_by: current_user, cohort_code: invite_cohort_code)
               .invite!(params[:email])

      flash[:success] = invite_flash(result)
      redirect_to admin_waitlist_index_path
    rescue Fuime::WaitlistInviteService::Error => e
      flash[:error] = e.message
      redirect_to admin_waitlist_index_path
    end

    def invite_next
      outcome = Fuime::WaitlistInviteService
                .new(invited_by: current_user, cohort_code: invite_cohort_code)
                .invite_next!(count: params[:count])

      invited = outcome[:invited]
      errors = outcome[:errors]
      flash[:success] = "Sent #{helpers.pluralize(invited.size, "login invite")}." if invited.any?
      flash[:error] = errors.to_sentence if errors.any?
      redirect_to admin_waitlist_index_path
    rescue Fuime::WaitlistInviteService::Error => e
      flash[:error] = e.message
      redirect_to admin_waitlist_index_path
    end

    private

    def load_roster
      @goal = Fuime::WaitlistRoster.goal
      @configured = Fuime::WaitlistRoster.configured?
      @signups = []
      @total = 0
      @error = nil
      @live_cohorts = Fuime::Cohort.live.order(:name)

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
        csv << ["email", "source", "signed_up_at", "ip", "invited_at", "invited_by", "cohort_code"]

        @signups.each do |s|
          csv << [
            csv_safe(s.email),
            csv_safe(s.source),
            s.signed_up_at&.iso8601,
            csv_safe(s.ip),
            s.invited_at&.iso8601,
            csv_safe(s.invited_by),
            csv_safe(s.cohort_code)
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

    def invite_cohort_code
      params[:cohort_code].to_s.strip.presence
    end

    def invite_flash(result)
      sentence = "Sent a login invite to #{result.email}."
      sentence += " Cohort #{result.cohort.code}." if result.cohort
      sentence
    end

  end
end
