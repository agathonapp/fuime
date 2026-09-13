# frozen_string_literal: true

module Fuime
  # Fuime: the teen's end of a parent-first setup — `GET /join/:token`.
  #
  # Their parent signed for them before they had an account, so this link is
  # the only thing they have. Opening it proves inbox control, which is the
  # same proof a login code asks for, so it finishes a session through the
  # ordinary `Login` machinery (`SignedLinkSignIn`, shared with the waitlist
  # admit) — 2FA and session rules included. It is not a second way to log in.
  #
  # The token is a signed id with a purpose and a 7-day expiry
  # (`Fuime::FamilyInviteService`); there is no token column, nothing to
  # revoke, and an expired link cannot be revived by anybody, including us.
  # What a teen with a dead link does is ask their parent to send another
  # (`GuardianshipsController#resend_join`) or sign in with a code, and both
  # are named on the page that tells them.
  class FamilyInvitesController < ApplicationController
    include SignedLinkSignIn

    skip_before_action :signed_in_user
    skip_before_action :redirect_to_onboarding
    skip_after_action :verify_authorized

    def show
      user = ::Fuime::FamilyInviteService.verify_token(params[:token])

      if user.nil?
        return redirect_to auth_users_path(signup: true), flash: {
          error: "This link has expired or isn't valid. Ask your parent or guardian to send it again, or enter your email and we'll send you a login code."
        }
      end

      # Signed in as somebody else — usually the parent who sent it, on a
      # shared laptop. Refuse and reveal nothing but the redacted address the
      # link was sent to: this link signs its holder in AS THE TEEN.
      if signed_in? && current_user != user
        @invited_email = user.redacted_email
        return render :wrong_account, status: :forbidden
      end

      return redirect_to setup_path if signed_in?

      login = sign_in_from_signed_link!(user:, purpose: "family_join", return_to: setup_path)

      if login.complete? && login.user_session.present?
        redirect_to setup_path
      else
        # A second factor is still outstanding. Same landing as the waitlist
        # invite: the token proved the email factor, not the rest.
        redirect_to choose_login_preference_login_path(login)
      end
    rescue SessionsHelper::AccountLockedError => e
      redirect_to auth_users_path, flash: { error: e.message }
    end

  end
end
