# frozen_string_literal: true

module LoginCodeService
  class Request
    def initialize(email:, ip_address:, user_agent:, sms: false)
      @email = email
      @sms = sms
      @ip_address = ip_address
      @user_agent = user_agent
    end

    def run
      user = User.find_or_initialize_by(email: @email)

      if @sms
        send_login_code_by_sms(user)
      else
        send_login_code_by_email(user)
      end
    end

    def send_login_code_by_sms(user)
      return { error: "no phone number provided", method: :sms } if user.phone_number.empty?

      begin
        TwilioVerificationService.new.send_verification_request(user.phone_number)
      rescue
        return send_login_code_by_email(user)
      end

      {
        id: user.id,
        email: user.email,
        status: "login code sent",
        method: :sms
      }
    end

    def send_login_code_by_email(user)
      user.save if user.new_record?
      if user.new_record? && !user.save
        return { error: user.errors, method: :email }
      end

      # Fuime: the newest code is the only code.
      #
      # `LoginCode.active` was every unused code from the last fifteen minutes,
      # so each request ADDED a working key rather than replacing one. Login
      # initiation is throttled at 5 per 20s per IP, which means roughly 225
      # codes could be made live at once against one account, and the verify
      # endpoint (`POST /logins/:id/complete`) had no attempt limit of its own —
      # only the 1000-per-five-minutes anti-scraper ceiling. 225 live keys out of
      # a million against thousands of guesses is not a lock.
      #
      # Superseding costs nothing a user would notice: every OTP system behaves
      # this way, and the person who clicks "resend" is reading the newest email.
      # It is the larger half of the fix — one live code instead of 225 — and the
      # throttle added in config/initializers/rack_attack.rb is the other.
      #
      # `used_at` is the only "no longer active" marker on the model and nothing
      # reads it as evidence of a successful login, so it carries this too.
      user.login_codes.active.update_all(used_at: Time.current)

      login_code = user.login_codes.create(
        ip_address: @ip_address,
        user_agent: @user_agent
      )

      begin
        LoginCodeMailer.send_code(user.email_address_with_name, login_code.pretty).deliver_now
      rescue => e
        # A misconfigured or unreachable SMTP server must not turn into a 500 on
        # the login page. Report it and surface a readable error instead, so the
        # cause shows up in Sentry rather than only as a failed login.
        Rails.error.report(e, handled: true, context: { email: user.email })

        return { error: "We couldn't send your login code right now. Please try again in a moment.", method: :email }
      end

      {
        id: user.id,
        email: user.email,
        status: "login code sent",
        method: :email,
        login_code:
      }
    end

  end
end
