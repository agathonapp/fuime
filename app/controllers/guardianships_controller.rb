# frozen_string_literal: true

class GuardianshipsController < ApplicationController
  skip_before_action :signed_in_user, only: [:show, :accept]
  skip_before_action :redirect_to_onboarding, only: [:new, :create]
  before_action :set_guardianship, only: [:show, :accept]
  before_action :hide_footer, only: [:show, :new]

  # The guardian's overview of the ventures they signed for.
  #
  # This exists because agreement §3 promises the signing adult visibility into
  # the minor's business activity and says it "cannot be turned off by the
  # minor" — a binding promise that had no surface behind it: `guardianships_as_guardian`
  # was referenced in exactly one view, the *admin* user page.
  #
  # Both directions are shown deliberately. A guardian needs their wards'
  # ventures; a teen needs to see the state of their own invite (and chase it),
  # which previously required keeping the emailed link.
  def index
    authorize Guardianship

    @guardianships_as_guardian = current_user
                                 .guardianships_as_guardian
                                 .includes(:minor)
                                 .order(created_at: :desc)

    @guardianships_as_minor = current_user
                              .guardianships_as_minor
                              .includes(:guardian)
                              .order(created_at: :desc)

    # Ventures this user oversees, grouped by the ward who puts them there, so
    # the page reads "Ada's ventures" rather than a flat list whose ownership a
    # guardian of two teens cannot tell apart.
    #
    # Keyed by id, not by the User object: the wards loaded here and the
    # `guardianship.minor` records the view iterates are different instances, and
    # relying on ActiveRecord's `hash`/`eql?` to make them the same Hash key is
    # the kind of subtlety that silently returns nil later. Sorted in Ruby so the
    # `includes(:events)` preload is not thrown away by an `order` on the
    # association.
    @overseen_events_by_ward_id = current_user
                                  .active_wards
                                  .includes(:events)
                                  .to_h { |ward| [ward.id, ward.events.sort_by { |e| e.name.to_s.downcase }] }
                                  .reject { |_id, events| events.empty? }
  end

  def new
    # Teen needs to invite a guardian
    @guardianship = Guardianship.new(minor: current_user)
    authorize @guardianship
  end

  def create
    # Teen creating an invite for their parent/guardian.
    #
    # `guardian_email` is a form-only field used to look up (or create) the
    # guardian — it is NOT a column on Guardianship, so it must not be passed
    # to the constructor.
    @guardianship = Guardianship.new(minor: current_user)
    authorize @guardianship

    # Find or create guardian user by email
    guardian_email = guardianship_params[:guardian_email]&.strip&.downcase

    if guardian_email.blank?
      flash[:error] = "Please enter your parent or guardian's email address."
      render :new, status: :unprocessable_content, formats: [:html]
      return
    end

    guardian = User.find_by(email: guardian_email)

    if guardian.nil?
      # Create a new user for the guardian (they'll onboard when accepting).
      # Rescued so an invalid address renders a form error instead of a 500.
      begin
        guardian = User.create!(email: guardian_email)
      rescue ActiveRecord::RecordInvalid => e
        flash[:error] = e.record.errors.full_messages.to_sentence
        render :new, status: :unprocessable_content, formats: [:html]
        return
      rescue => e
        Rails.error.report(e, handled: true, context: { guardian_email: })
        flash[:error] = "We couldn't create an account for that email address. Please check it and try again."
        render :new, status: :unprocessable_content, formats: [:html]
        return
      end
    end

    if guardian.id == current_user.id
      flash[:error] = "You cannot invite yourself as a guardian."
      render :new, status: :unprocessable_content, formats: [:html]
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
      render :new, status: :unprocessable_content, formats: [:html]
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
      # Return to the invite page, not to `accept` — that route is POST-only, so
      # a post-login GET redirect there would 404.
      return redirect_to auth_users_path(return_to: guardianship_path(@guardianship.invite_token))
    end

    authorize @guardianship

    if @guardianship.guardian != current_user
      flash[:error] = "This invitation was not sent to you."
      redirect_to root_path
      return
    end

    # The agreement checkbox is `required` in the form, but that is a client-side
    # hint only. Consent is the entire legal product of this action, so it is
    # confirmed again here where it cannot be skipped.
    unless ActiveModel::Type::Boolean.new.cast(params[:agree])
      flash[:error] = "Please confirm you agree to the guardian agreement."
      redirect_to guardianship_path(@guardianship.invite_token)
      return
    end

    # Preconditions for signing as the responsible adult — chiefly a confirmed
    # 18+ date of birth. A guardian invited by email starts as a stub user with
    # no birthday, so this is the common path, not an edge case.
    blockers = @guardianship.activation_blockers
    if blockers.any?
      flash[:error] = blockers.to_sentence
      # Return them to the invite page, not back here: `accept` is POST-only, so
      # a GET return_to would 404 the moment they finish filling in their DOB.
      redirect_to edit_user_path(current_user, return_to: guardianship_path(@guardianship.invite_token))
      return
    end

    accepted = @guardianship.accept!(
      consent_ip: request.remote_ip,
      consent_user_agent: request.user_agent
    )

    if accepted
      flash[:success] = "You are now #{@guardianship.minor.name}'s guardian on Fuime!"
      redirect_to root_path
    else
      flash[:error] = "Failed to accept guardianship."
      redirect_to guardianship_path(@guardianship.invite_token)
    end
  end

  # The permanent record of a signed agreement: what was agreed, when, under
  # which version, and by whom. A guardian must be able to go back and read the
  # thing they signed — consent you cannot review is not meaningful consent.
  def record
    @guardianship = Guardianship.find(params[:id])
    authorize @guardianship
  end

  # Withdraw consent. A guardian must be able to do this at any time — it is a
  # legal requirement, not a feature — and it takes effect immediately, because
  # `User#permitted_to_operate_business?` reads guardianship status live.
  def revoke
    @guardianship = Guardianship.find(params[:id])
    authorize @guardianship

    @guardianship.revoke!(revoked_by: current_user)

    flash[:success] = "Guardianship revoked. #{@guardianship.minor.name || @guardianship.minor.email} can no longer operate a business on Fuime."
    redirect_back_or_to post_action_path_for(@guardianship)
  end

  # Re-issue a fresh token for a pending invite whose link has gone stale.
  def resend_invite
    @guardianship = Guardianship.find(params[:id])
    authorize @guardianship

    if @guardianship.resend_invite!
      flash[:success] = "Invitation resent to #{@guardianship.guardian.email}."
    else
      flash[:error] = "This invitation is no longer pending, so it can't be resent."
    end

    redirect_back_or_to post_action_path_for(@guardianship)
  end

  private

  # Where to land after revoking or resending. Admins came from the admin user
  # page and should return to it; a guardian or teen cannot load that page at
  # all, so they get the agreement record instead.
  def post_action_path_for(guardianship)
    return admin_user_path(guardianship.minor) if current_user&.admin?

    record_guardianship_path(guardianship)
  end

  def set_guardianship
    @guardianship = Guardianship.find_by_token(params[:id])
    unless @guardianship
      flash[:error] = "Invalid or expired invitation link."
      redirect_to root_path
    end
  end

  def guardianship_params
    params.fetch(:guardianship, ActionController::Parameters.new).permit(:guardian_email)
  end

end
