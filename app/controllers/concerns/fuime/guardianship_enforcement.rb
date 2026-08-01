# frozen_string_literal: true

module Fuime
  # Fuime: minors may not operate a business without an active guardianship.
  #
  # This is the platform's central legal control, so it is enforced as a
  # deny-by-default filter on every authenticated request rather than as a
  # redirect on one happy path. Previously the only check was a redirect after
  # profile creation (users_controller.rb) — a suggestion, not a control: a teen
  # could dismiss it and then create and operate a business freely.
  #
  # Design notes:
  #   * Deny-by-default. Everything is blocked unless explicitly allowlisted, so
  #     a newly added controller is safe until someone thinks about it.
  #   * Unknown age counts as minor (User#minor_or_unknown_age?) — otherwise
  #     omitting a birthday disables the control entirely.
  #   * The allowlist covers only what a parked teen legitimately needs: reading
  #     Fuime's own static/legal pages, managing their profile, inviting a
  #     guardian, and signing out.
  #
  # This complements — does not replace — the checks in EventPolicy. Policies
  # guard the object; this guards the session.
  module GuardianshipEnforcement
    extend ActiveSupport::Concern

    included do
      before_action :enforce_guardianship_requirement
    end

    # Controllers a minor awaiting a guardian may still reach. Matched against
    # `controller_path`, so a namespace entry covers everything beneath it.
    ALLOWED_CONTROLLER_PATHS = [
      "guardianships",        # the whole point: invite your guardian
      "users",                # profile / settings / date of birth
      "logins",               # sign in
      "sessions",             # sign out
      "static_pages",         # home, legal, help
      "errors",
      "fuime/storefronts",    # public pages
      "rails/health",
      "active_storage/blobs",
      "active_storage/representations",
      "active_storage/disk",
    ].freeze

    private

    def enforce_guardianship_requirement
      return unless current_user
      return if current_user.permitted_to_operate_business?
      return if allowed_while_awaiting_guardian?

      # Don't fight the onboarding redirect — a user who hasn't set a name yet
      # is already being sent to settings, and needs to get there to enter a
      # date of birth in the first place.
      return if current_user.onboarding?

      respond_to do |format|
        format.html do
          redirect_to new_guardianship_path,
                      alert: guardianship_required_message
        end
        format.json do
          render json: { error: guardianship_required_message }, status: :forbidden
        end
        format.any do
          redirect_to new_guardianship_path, alert: guardianship_required_message
        end
      end
    end

    def allowed_while_awaiting_guardian?
      ALLOWED_CONTROLLER_PATHS.any? do |allowed|
        controller_path == allowed || controller_path.start_with?("#{allowed}/")
      end
    end

    def guardianship_required_message
      if current_user.birthday.blank?
        "Please add your date of birth so we know whether you need a parent or guardian on your account."
      else
        "Your parent or guardian needs to accept their invitation before you can use your Fuime business account."
      end
    end
  end
end
