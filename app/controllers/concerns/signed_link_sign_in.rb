# frozen_string_literal: true

# Fuime: finish a session for somebody who proved inbox control by opening a
# signed link, without inventing a second way to log in.
#
# Moved verbatim from `WaitlistInvitesController#show`, which has done this
# since the waitlist admit shipped, so that the family join link
# (`Fuime::FamilyInvitesController`) does the same thing rather than a similar
# thing. The rule it encodes: a signed link marks the EMAIL factor on a real
# `Login` row and then goes through `ProcessLoginService` and the ordinary
# session rules — so a user with 2FA still gets their second factor, and every
# session this creates is an ordinary `User::Session` with the same expiry,
# fingerprinting and audit trail as one from a login code.
#
# Returns the `Login`. Callers check `login.complete? && login.user_session` and
# send anyone who is not finished to `choose_login_preference_login_path`.
module SignedLinkSignIn
  extend ActiveSupport::Concern

  private

  def sign_in_from_signed_link!(user:, purpose:, return_to: nil)
    login = Login.create!(user:, state: { purpose:, return_to: })
    cookies.signed["browser_token_#{login.hashid}"] = {
      value: login.browser_token,
      expires: Login::EXPIRATION.from_now
    }

    ProcessLoginService.new(login:).process_signed_email_link
    login.reload

    login.with_lock do
      if login.complete? && login.user_session.nil?
        login.user.update(verified: true) unless login.user.verified?
        sign_out
        login.update(user_session: create_session(
          user: login.user,
          verified: true,
          fingerprint_info: { ip: request.remote_ip }
        ))
      end
    end

    login
  end
end
