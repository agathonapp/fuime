# frozen_string_literal: true

class GuardianshipsController < ApplicationController
  skip_before_action :signed_in_user, only: [:show, :accept]
  skip_before_action :redirect_to_onboarding, only: [:new, :create]
  before_action :set_guardianship, only: [:show, :accept]
  before_action :hide_footer, only: [:show, :new]

  def new
    # Teen needs to invite a guardian
    @guardianship = Guardianship.new(minor: current_user)
    authorize @guardianship
  end

  def create
    # Teen creating an invite for their parent/guardian
    @guardianship = Guardianship.new(guardianship_params)
    @guardianship.minor = current_user
    authorize @guardianship

    # Find or create guardian user by email
    guardian_email = params[:guardianship][:guardian_email]&.strip&.downcase

    if guardian_email.blank?
      flash[:error] = "Please enter your parent or guardian's email address."
      render :new, status: :unprocessable_content
      return
    end

    guardian = User.find_by(email: guardian_email)

    if guardian.nil?
      # Create a new user for the guardian (they'll onboard when accepting)
      guardian = User.create!(email: guardian_email)
    end

    if guardian.id == current_user.id
      flash[:error] = "You cannot invite yourself as a guardian."
      render :new, status: :unprocessable_content
      return
    end

    @guardianship.guardian = guardian

    if @guardianship.save
      # Send invite email
      GuardianshipMailer.invite(guardianship: @guardianship).deliver_later
      flash[:success] = "Invitation sent to #{guardian_email}! They'll need to accept to activate your account."
      redirect_to root_path
    else
      flash[:error] = @guardianship.errors.full_messages.join(", ")
      render :new, status: :unprocessable_content
    end
  end

  def show
    # Guardian viewing their invite to accept
    unless signed_in?
      skip_authorization
      return redirect_to auth_users_path(return_to: guardianship_path(@guardianship.invite_token)),
                         flash: { info: "Please sign in to accept this guardian invitation." }
    end

    authorize @guardianship

    if @guardianship.active?
      redirect_to root_path, flash: { success: "You've already accepted this guardianship." }
    elsif @guardianship.revoked?
      redirect_to root_path, flash: { error: "This guardianship invitation has been revoked." }
    end
  rescue Pundit::NotAuthorizedError
    if @guardianship.guardian != current_user
      flash[:error] = "This invitation was sent to #{@guardianship.guardian.redacted_email}, but you are currently logged in as #{current_user.email}."
      redirect_to root_path
    else
      raise
    end
  end

  def accept
    unless signed_in?
      skip_authorization
      return redirect_to auth_users_path(return_to: accept_guardianship_path(@guardianship.invite_token))
    end

    authorize @guardianship

    if @guardianship.guardian != current_user
      flash[:error] = "This invitation was not sent to you."
      redirect_to root_path
      return
    end

    if @guardianship.accept!
      flash[:success] = "You are now #{@guardianship.minor.name}'s guardian on Fuime!"
      redirect_to root_path
    else
      flash[:error] = "Failed to accept guardianship."
      redirect_to guardianship_path(@guardianship.invite_token)
    end
  end

  private

  def set_guardianship
    @guardianship = Guardianship.find_by_token(params[:id])
    unless @guardianship
      flash[:error] = "Invalid or expired invitation link."
      redirect_to root_path
    end
  end

  def guardianship_params
    params.require(:guardianship).permit(:guardian_email)
  end
end
