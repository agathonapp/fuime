# frozen_string_literal: true

# Fuime: the public end of a waitlist admit email.
#
# The token is a signed payload from Fuime::WaitlistInviteService, not a
# LoginCode. Clicking it is inbox control, so we mark the email factor on a
# real Login and finish through the same session rules LoginsController uses
# (including 2FA). We do not mint a User::Session any other way.
class WaitlistInvitesController < ApplicationController
  skip_before_action :signed_in_user
  skip_before_action :redirect_to_onboarding
  skip_after_action :verify_authorized

  def show
    verified = Fuime::WaitlistInviteService.verify_token(params[:token])
    unless verified
      flash[:error] = "This invite link has expired or is not valid. Enter your email to get a login code."
      redirect_to auth_users_path
      return
    end

    user, cohort_code = verified
    remember_cohort_code(cohort_code)

    if signed_in?
      if current_user.id == user.id
        redirect_to after_waitlist_login_path(user)
      else
        flash[:error] = "You're signed in as #{current_user.email}. Sign out to use this invite."
        redirect_to root_path
      end
      return
    end

    login = Login.create!(user:, state: { purpose: "waitlist_invite" })
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

    if login.complete? && login.user_session.present?
      redirect_to after_waitlist_login_path(login.user)
    else
      redirect_to choose_login_preference_login_path(login)
    end
  rescue SessionsHelper::AccountLockedError => e
    redirect_to auth_users_path, flash: { error: e.message }
  end

  private

  def remember_cohort_code(code)
    if code.present?
      session[:waitlist_cohort_code] = code
    end
  end

  def after_waitlist_login_path(user)
    if user.full_name.blank? || user.phone_number.blank?
      edit_user_path(user.slug)
    else
      root_path
    end
  end

end
