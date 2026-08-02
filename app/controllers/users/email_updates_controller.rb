# frozen_string_literal: true

module Users
  class EmailUpdatesController < ApplicationController
    def authorize_change
      @request = User::EmailUpdate.active.find_by!(authorization_token: params[:authorization_token])

      authorize @request

      @request.update!(authorized: true)

      if @request.confirmed?
        return redirect_to root_path, flash: { success: "We've updated your email address to #{@request.user.email}." }
      else
        return redirect_to root_path, flash: { success: "Authorized; please check your new email's inbox (#{@request.replacement}) to verify this change." }
      end
    rescue ActiveRecord::RecordNotFound => e
      # `find_by!` raises before `authorize` runs, so Pundit's
      # `verify_authorized` after_action fires and turns a bad token into a
      # 500. There is no record to authorize against on this path.
      skip_authorization
      flash[:error] = "This authorization token has expired, please request another."
      redirect_to root_path
    rescue ActiveRecord::RecordInvalid => e
      flash[:error] = @request.errors.full_messages.to_sentence
      redirect_to root_path
    end

    def verify
      @request = User::EmailUpdate.active.find_by!(verification_token: params[:verification_token])

      authorize @request

      @request.update!(verified: true)

      if @request.confirmed?
        return redirect_to root_path, flash: { success: "We've updated your email address to #{@request.user.email}." }
      else
        return redirect_to root_path, flash: { success: "Verified; please check your old email's inbox (#{@request.original}) to authorize this change." }
      end
    rescue ActiveRecord::RecordNotFound => e
      # Both rescues must redirect: `verify` has no template (there is no
      # app/views/users/email_updates/), so falling through to an implicit
      # render raises MissingExactTemplate and the user sees a 500 instead of
      # the error message. An expired or already-used verification link is an
      # ordinary thing to click, not an exception.
      skip_authorization
      flash[:error] = "This verification token has expired, please request another."
      redirect_to root_path
    rescue ActiveRecord::RecordInvalid => e
      flash[:error] = @request.errors.full_messages.to_sentence
      redirect_to root_path
    end

  end
end
