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
    # Matched against `controller_path`. Entries are EXACT — a namespace is not
    # implied, because "users" would otherwise pull in every controller beneath
    # it (users/wrapped, and anything added later) without anyone deciding it
    # belonged in a legal-control allowlist.
    ALLOWED_CONTROLLER_PATHS = [
      "guardianships",        # the whole point: invite your guardian
      "users",                # profile / settings / date of birth
      "users/email_updates",  # confirming an email change
      "logins",               # sign in AND sign out — there is no separate
      # sessions controller in this app
      "static_pages",         # home, legal, help
      "errors",
      "fuime/storefronts",    # public pages
      "rails/health",
      # Applying is how a teen STARTS, and the application itself is where the
      # parent's email is collected and the guardian agreement is sent. Blocking
      # it until a guardianship is already active deadlocks the exact user Fuime
      # exists for: they cannot apply without a guardian and cannot get one
      # attached without applying. The control still holds where it matters —
      # `activate_event!` requires the signed agreement, and EventPolicy guards
      # the business itself, so a teen can fill in an application but cannot
      # operate a business until a guardian has actually signed.
      "event/applications",
      "event/affiliations",   # the affiliations sub-form on the application
      "contracts",            # signing the agreement that creates the guardianship
      "contract/parties",
      # Active Storage's real routed controller names — "active_storage/blobs"
      # and "active_storage/representations" are NOT routed and matched nothing.
      "active_storage/blobs/proxy",
      "active_storage/blobs/redirect",
      "active_storage/representations/proxy",
      "active_storage/representations/redirect",
      "active_storage/disk",
    ].freeze

    private

    def enforce_guardianship_requirement
      return unless current_user
      # Staff are not teen business owners. EventPolicy already exempts them
      # (see EventPolicy#permitted_to_operate_business?); without the same
      # exemption here the filter bounces every admin to /guardian/new, because
      # "unknown age counts as minor" also captures staff accounts, which have
      # no birthday on file. That locked admins out of the admin console itself.
      return if current_user.admin? || current_user.auditor?
      return if current_user.permitted_to_operate_business?
      # A school student has no guardianship and never will — the school is the
      # responsible adult (Event::Plan::School). Without this, every student at
      # a school is redirected to "invite your parent" on every page. Their
      # ability to ACT is still enforced per record: EventPolicy allows them on
      # school ventures and continues to block a personal venture until a real
      # guardian accepts.
      return if current_user.institutionally_vouched_for?
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

    # Exact match only — see ALLOWED_CONTROLLER_PATHS. Adding a controller under
    # an already-allowed namespace should require listing it deliberately, not
    # inherit access from its parent.
    def allowed_while_awaiting_guardian?
      ALLOWED_CONTROLLER_PATHS.include?(controller_path)
    end

    def guardianship_required_message
      if current_user.birthday.blank?
        "Please add your date of birth so we know whether you need a parent or guardian on your account."
      else
        "Your parent or guardian needs to accept their invitation before you can run your venture on Fuime."
      end
    end
  end
end
