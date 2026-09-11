# frozen_string_literal: true

class GuardianshipsController < ApplicationController
  # :show, :accept and :renew are token-addressed and reachable without a
  # session — a parent follows them from an email before they have an account.
  skip_before_action :signed_in_user, only: [:show, :accept, :renew]
  skip_before_action :redirect_to_onboarding, only: [:new, :create, :renew]
  before_action :set_guardianship, only: [:show, :accept]

  # Fuime: the footer is deliberately NOT hidden on :show or :new any more. It
  # carries the standing "financial technology company, not a bank" disclosure
  # (app/views/application/_footer.html.erb), and 12 CFR 328.102(b)(3)(ii) makes
  # the OMISSION the violation. The accept page is the one screen a new adult
  # reads before signing — exactly the reader the disclosure exists for — so
  # `hide_footer` here was the gap that mattered most. See
  # spec/requests/fuime/status_disclosure_spec.rb.

  # How soon after a send the token-addressed #renew will send again. Long
  # enough that a double-click or a refreshed confirmation page cannot mail the
  # parent twice; short enough that "I deleted it by mistake" is not a support
  # ticket. Chasing a parent on purpose is the signed-in #resend_invite.
  RENEW_COOLDOWN = 10.minutes

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
      # What the acceptance gates differs by money model (L8): payouts under
      # merchant-of-record, activation under Connect.
      flash[:success] =
        if ::Fuime::Features.merchant_of_record?
          "Invitation sent to #{guardian_email}. You can keep going — nothing is paid out until they accept."
        else
          "Invitation sent to #{guardian_email}. They'll need to accept before your venture can be activated."
        end
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
    else
      @venture_name = venture_name_for(@guardianship.minor)
    end
  rescue Pundit::NotAuthorizedError
    if @guardianship.guardian != current_user
      # Signed in as somebody else — typically a parent who shares a laptop with
      # the teen, or a teen opening the link they were about to text. A flash and
      # a bounce to the dashboard left them with nowhere to go (ONBOARDING_PLAN
      # §2 #10); this renders a page with the one action that helps. Only the
      # redacted address reaches the page — nothing about the teen or venture.
      @wrong_account = true
      @invited_email = @guardianship.guardian.redacted_email
      render :show, status: :forbidden
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

    # Fuime: that same tick is the 18+ assertion, so record it as one.
    #
    # The box reads "I confirm I am the parent or legal guardian of X, THAT I AM 18
    # OR OLDER, and I agree to the guardian agreement" — one sentence, three claims.
    # Since 2026-08-20 nobody is asked for a date of birth
    # (AddAgeAttestationToUsers), so this is where `known_adult?` becomes true for a
    # guardian, and it is deliberately the ONLY place: a user cannot reach
    # `adult_18_plus` from a form they control.
    #
    # Before #activation_blockers, because the blocker it clears is the 18+ one and
    # the whole point is that ticking the box is how you clear it.
    #
    # Written through `@guardianship.guardian` rather than `current_user`: they are
    # the same record, but #attest_adult_18_plus! uses update_columns, so a write to
    # the other instance would leave the object #activation_blockers is about to read
    # holding a stale value — and the blocker would fire on the request that just
    # cleared it.
    @guardianship.guardian.attest_adult_18_plus!(
      ip: request.remote_ip, user_agent: request.user_agent
    )

    # Remaining preconditions for signing as the responsible adult. The 18+ one is
    # satisfied by the tick above; what is left is the structural check that a
    # guardian exists and is not the minor themselves.
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
  # legal requirement, not a feature — and it takes effect immediately: under
  # Connect `User#permitted_to_operate_business?` reads guardianship status
  # live; under merchant-of-record `Event#payout_setup_blockers` does.
  def revoke
    @guardianship = Guardianship.find(params[:id])
    authorize @guardianship

    @guardianship.revoke!(revoked_by: current_user)

    # What revocation stops differs by money model (L8). Under merchant-of-record
    # User#permitted_to_operate_business? is unconditionally true, so the venture
    # keeps existing; what the withdrawal does is re-arm the guardian blocker in
    # Event#payout_setup_blockers, so no payout can be sent until an adult is on
    # the account again. Under Connect it removes the minor's ability to operate.
    minor_name = @guardianship.minor.name || @guardianship.minor.email
    flash[:success] =
      if ::Fuime::Features.merchant_of_record?
        "Guardianship revoked. No money will be paid out of #{minor_name}'s business until a parent or guardian is on the account again."
      else
        "Guardianship revoked. #{minor_name} can no longer operate a business on Fuime."
      end
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

  # The parent's own way out of a dead link: POST /guardian/:token/renew from
  # the expired page (#set_guardianship renders it). Token-addressed like
  # #show, and reachable without a session for the same reason — the person
  # holding the link is in front of an email, not a login form.
  #
  # Authorization is skipped rather than checked against current_user because
  # the bearer token IS the credential here, and a policy on the session would
  # refuse the common case (signed out) while stopping nothing: the only effect
  # is a mail to the guardian's own inbox, through Guardianship#resend_invite!,
  # the one resend path. Rotating the token is the natural rate limit — after
  # one renew the link that reached this page is dead — and RENEW_COOLDOWN
  # covers the fresh-token replay.
  #
  # Looked up WITHOUT the expiry check, unlike #set_guardianship: a still-live
  # token posted here is a double submit or a replay, and the cooldown is what
  # should answer it, not a second email.
  def renew
    skip_authorization

    guardianship = Guardianship.pending.find_by(invite_token: params[:id]) if params[:id].present?

    if guardianship.nil?
      flash[:error] = "Invalid or expired invitation link."
      redirect_to root_path
      return
    end

    if guardianship.invite_sent_at.present? && guardianship.invite_sent_at > RENEW_COOLDOWN.ago
      redirect_to root_path, flash: { info: "We sent a new link a few minutes ago — check your inbox." }
      return
    end

    @guardianship = guardianship
    @guardianship.resend_invite!
    @renewed = true
    render :expired
  end

  private

  # The venture the parent is being asked to sign for, for the accept page's
  # heading; nil when the teen has not named one. Same rule as
  # GuardianshipMailer#venture_name_for — keep the two in step.
  def venture_name_for(minor)
    minor.events.order(created_at: :desc).first&.name.presence ||
      minor.applications.not_archived.order(created_at: :desc).first&.name.presence
  end

  # Where to land after revoking or resending. Admins came from the admin user
  # page and should return to it; a guardian or teen cannot load that page at
  # all, so they get the agreement record instead.
  def post_action_path_for(guardianship)
    return admin_user_path(guardianship.minor) if current_user&.admin?

    record_guardianship_path(guardianship)
  end

  def set_guardianship
    @guardianship = Guardianship.find_by_token(params[:id])
    return if @guardianship

    # find_by_token is nil for unknown, accepted, revoked AND merely expired
    # tokens. Only the last of those has a way out: the row is still pending and
    # the parent still wants to sign, so offer to re-mint the link instead of
    # the dead end (ONBOARDING_PLAN §2 #9). Accepted and revoked tokens are
    # cleared on the row (Guardianship#accept! / #revoke!), so they never match
    # here and keep the single generic message below — this does not turn the
    # lookup into an oracle for anything but "this pending link aged out".
    #
    # Halting a before_action skips the after_action chain, but the policy flag
    # is set anyway so verify_authorized can never see this page as unauthorized.
    expired = expired_pending_invite(params[:id])
    if expired
      @guardianship = expired
      skip_authorization
      render :expired, status: :gone
      return
    end

    flash[:error] = "Invalid or expired invitation link."
    redirect_to root_path
  end

  # A pending invite whose token still matches but whose 7-day window has
  # passed. Nil for everything else.
  def expired_pending_invite(token)
    return nil if token.blank?

    guardianship = Guardianship.pending.find_by(invite_token: token)
    return nil unless guardianship&.invite_expired?

    guardianship
  end

  def guardianship_params
    params.fetch(:guardianship, ActionController::Parameters.new).permit(:guardian_email)
  end

end
