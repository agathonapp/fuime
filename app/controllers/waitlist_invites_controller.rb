# frozen_string_literal: true

# Fuime: the public end of a waitlist admit email.
#
# The token is a signed payload from Fuime::WaitlistInviteService, not a
# LoginCode. Clicking it is inbox control, so we mark the email factor on a
# real Login and finish through the same session rules LoginsController uses
# (including 2FA). We do not mint a User::Session any other way.
class WaitlistInvitesController < ApplicationController
  include SignedLinkSignIn

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

    # Do not write a cohort into the session until we know this browser is
    # (or is about to become) that user. A signed-in stranger who opens the
    # link must not inherit the invitee's event code on their next apply.
    if signed_in? && current_user.id != user.id
      flash[:error] = "You're signed in as #{current_user.email}. Sign out to use this invite."
      redirect_to root_path
      return
    end

    store_cohort_stamp(user, cohort_code)

    if signed_in?
      redirect_to after_waitlist_login_path(user)
      return
    end

    # Moved verbatim into SignedLinkSignIn so the family join link does the
    # same thing rather than a similar thing. Behaviour is unchanged.
    login = sign_in_from_signed_link!(user:, purpose: "waitlist_invite")

    if login.complete? && login.user_session.present?
      redirect_to after_waitlist_login_path(login.user)
    else
      redirect_to choose_login_preference_login_path(login)
    end
  rescue SessionsHelper::AccountLockedError => e
    redirect_to auth_users_path, flash: { error: e.message }
  end

  private

  def store_cohort_stamp(user, code)
    if code.present?
      session[:waitlist_cohort] = { "uid" => user.id, "code" => code }
    else
      session.delete(:waitlist_cohort)
    end
  end

  def after_waitlist_login_path(user)
    # Name only — the same test as LoginsController#complete and
    # User#onboarding?. Signup does not ask for a phone number (A2).
    # A name-less invitee goes to the family setup wizard, the one front door
    # for anybody who has not finished signing up.
    if user.full_name.blank?
      setup_path
    else
      root_path
    end
  end

end
