# frozen_string_literal: true

class Event
  class ApplicationsController < ApplicationController
    before_action :set_application, except: [:apply, :new, :create, :index]
    before_action :prevent_access_after_submission, only: [:business_type, :project_info, :personal_info, :review]
    before_action :prevent_access_if_archived, only: [:business_type, :project_info, :personal_info, :review, :videos, :agreement]
    after_action :record_pageview
    skip_before_action :signed_in_user, only: [:new, :apply, :create]
    skip_after_action :verify_authorized, only: :create
    skip_before_action :redirect_to_onboarding

    layout "apply"

    def index
      skip_authorization

      @applications = current_user.applications.active
      @referral_code = params[:ref]
    end

    def apply
      skip_authorization

      if signed_in? && current_user.applications.not_archived.draft.one?
        redirect_to application_path(current_user.applications.not_archived.draft.first)
      elsif signed_in? && current_user.applications.not_archived.any?
        redirect_to applications_path(ref: params[:ref])
      else
        redirect_to new_application_path(ref: params[:ref])
      end
    end

    def new
      skip_authorization

      @referral_code = params[:ref]
    end

    def show
      authorize @application

      # Signees are redirected to this page right after signing, so let's make sure we have updated data
      @application.contract&.party(:signee)&.sync_with_docuseal

      contract_description = if @application.contract.nil?
                               "We'll send you the Fuime agreement, which sets the terms and conditions of your usage of Fuime."
                             elsif @application.contract.party(:cosigner)&.pending?
                               if @application.contract.party(:signee).signed?
                                 "Your parent or legal guardian (#{@application.cosigner_email}) needs to sign the agreement before we can review your application."
                               else
                                 "You (#{@application.user.email}) and your parent or legal guardian (#{@application.cosigner_email}) need to sign the agreement before we can review your application."
                               end
                             elsif @application.contract.party(:signee)&.pending?
                               "You (#{@application.user.email}) need to sign the agreement before we can review your application."
                             else
                               "Our team will sign and finalize the contract soon."
                             end

      # We allow teenagers to receive and sign the contract while applying. Adults must wait for HCB Operations' review.
      contract_signed = @application.contract&.parties&.not_hcb&.all?(&:signed?) && (@application.teen_led? || @application.contract&.party(:hcb)&.signed?)
      contract_step = {
        label: "Sign agreement",
        shorthand: "Sign",
        name: "Sign the Fuime agreement",
        description: contract_description,
        completed: contract_signed
      }

      unless @application.draft?
        @steps = []
        @steps << { label: "Submit application", shorthand: "Submit", completed: true }
        @steps << contract_step if @application.teen_led?
        @steps << {
          label: "Await review",
          shorthand: "Review",
          name: "Wait for a response from the Fuime team",
          description: "Our operations team will review your application and respond within #{helpers.pluralize(@application.response_business_days, "business day")}. You'll hear back soon on whether your application was approved or rejected.",
          completed: @application.approved? && (contract_signed || !@application.teen_led?)
        }
        @steps << contract_step unless @application.teen_led?
        @steps << {
          label: "Start spending",
          shorthand: "Spend",
          name: "Start spending!",
          description: "You'll have access to your organization to begin raising and spending money.",
          completed: false
        }
      end
    end

    def admin_approve
      authorize @application

      @application.mark_approved!
      flash[:success] = "Application approved."

      # Mirrors the guard in Event::Application's mark_approved callback: when no
      # Fuime agreement is configured there is no contract to countersign, so
      # send the approver to the submission summary instead of dereferencing nil.
      party = @application.contract&.party(:hcb) if @application.teen_led?

      if party
        party.update!(user: current_user)
        redirect_to contract_party_path(party)
      else
        redirect_to submission_application_path(@application)
      end
    end

    def admin_reject
      authorize @application

      @application.mark_rejected!(params[:rejection_message])

      flash[:success] = "Application rejected."
      redirect_back_or_to application_path(@application)
    end

    def admin_activate
      authorize @application

      @application.activate_event!(tags: params[:tags], risk_level: params[:risk_level], point_of_contact: current_user)

      redirect_to event_path(@application.event), flash: { success: "Successfully activated #{@application.event.name}!" }
    end

    def submission
      authorize @application
    end

    def create
      # The "Are you under 18?" radio on the intro screen is rendered by
      # form_with model:, so it arrives as event_application[teen_led], not as a
      # bare :teen_led param. Reading only params[:teen_led] silently created
      # every application as teen_led=false, which pushed teen applicants onto
      # the adult branch of `application_ready_to_submit?` and made the submit
      # button permanently unclickable.
      unless signed_in?
        redirect_to auth_users_path(return_to: start_applications_path(teen_led: teen_led_param), require_reload: true, purpose: "application") and return
      end

      authorize(@application = Event::Application.new(user: current_user, teen_led: teen_led_param == "true", referral_code: params[:referral_code] || params.dig(:event_application, :referral_code)))
      @application.save!

      # Fuime: the business-type fork is the first real question now — see
      # Fuime::ServiceCatalog.
      redirect_to business_type_application_path(@application)
    end

    def personal_info
      authorize @application
    end

    # Fuime: the three-card fork and the service picker, ahead of project_info.
    #
    # Both questions on one page rather than two steps: "how are you starting" and
    # "what do you do" are answered in the same breath by anybody who knows, and
    # splitting them would add a click for the majority to help the minority who
    # picked the template card.
    def business_type
      authorize @application

      @starting_points = Fuime::ServiceCatalog::STARTING_POINTS
      @services = Fuime::ServiceCatalog.sellable
    end

    def project_info
      authorize @application

      # A template's outline is offered as a PLACEHOLDER, never written into the
      # record on the operator's behalf. Two reasons, and the second is the one
      # that matters: a description Fuime wrote is a description Fuime is the
      # author of, and under merchant-of-record Fuime is already the seller of
      # record for whatever it describes. The operator's own words are the only
      # ones that should reach a buyer.
      @template = @application.service if @application.started_from_template?
    end

    def videos
      authorize @application

      # The upstream onboarding videos are Hack Club's, about HCB's fiscal
      # sponsorship rules. Skip the step until Fuime has its own — see
      # Event::Application::ONBOARDING_VIDEO_IDS.
      if Event::Application::ONBOARDING_VIDEO_IDS.empty?
        @application.update!(videos_watched: true)
        redirect_to agreement_application_path(@application)
        nil
      end
    end

    def agreement
      authorize @application

      if Event::Application::ONBOARDING_VIDEO_IDS.any? && !@application.videos_watched
        redirect_to videos_application_path(@application)
        return
      end

      @contract = @application.contract

      # No Fuime agreement is configured, so there is nothing to sign here.
      # See Event::Plan#contract_docuseal_template_id.
      if @contract.nil?
        redirect_to application_path(@application)
        return
      end

      @party = @contract.party :signee
    end

    def mark_videos_watched
      authorize @application

      @application.update!(videos_watched: true)

      redirect_to agreement_application_path(@application)
    end

    def review
      authorize @application
    end

    def edit
      authorize @application
    end

    def update
      @application.assign_attributes(application_params)

      authorize @application

      # Fuime: an event code is resolved, never assigned.
      #
      # `fuime_cohort_id` is deliberately absent from `application_params` and
      # must stay absent. A cohort is the authority that auto-approves, activates
      # and vets a venture, so a permitted `fuime_cohort_id` would let an
      # applicant put any id they liked into that field and admit themselves to
      # somebody else's event. The only way in is a code somebody typed, looked up
      # through Fuime::Cohort.for_code, which returns nil for unknown, archived
      # and expired alike.
      assign_cohort_from_code if params[:event_application]&.key?(:cohort_code)

      @application.save!

      if user_params.present?
        success = @application.user.update(user_params)
        if params[:autosave] != "true" && !success
          render turbo_stream: turbo_stream.replace(:user_errors, partial: "event/applications/error", locals: { user: @application.user })
          return
        end
      end

      if params[:autosave] != "true"
        @return_to = url_from(params[:return_to])
        flash[:success] = "Changes saved." if params[:confirm] == "true"

        return redirect_to @return_to if @return_to.present?

        # `return`, which was missing. `redirect_back_or_to` does not end the
        # action, so a non-autosave update that arrived without a `return_to`
        # fell through to `head :no_content` below and raised
        # AbstractController::DoubleRenderError. Latent until now only because
        # every step view passes `return_to` — surfaced by a spec that posts
        # without one, which is also what any hand-rolled or replayed request
        # does.
        return redirect_back_or_to application_path(@application)
      end

      head :no_content
    end

    def submit
      authorize @application

      begin
        @application.mark_submitted!
        confetti!
        redirect_to application_path(@application)
      rescue AASM::InvalidTransition
        flash[:error] = "This application is not ready to submit. See the summary for what's missing."
        redirect_to review_application_path(@application)
      end
    end

    def archive
      authorize @application

      @application.archive!
      flash[:success] = "Application archived"

      redirect_to applications_path
    end

    def unarchive
      authorize @application

      @application.unarchive!
      flash[:success] = "Application unarchived"
      redirect_to application_path(@application)
    end

    def resend_to_cosigner
      authorize @application

      new_cosigner_email = params[:event_application][:cosigner_email]&.strip

      if new_cosigner_email == @application.user.email
        flash[:error] = "You cannot use your own email as your parent's email"
      else
        @application.update!(cosigner_email: params[:event_application][:cosigner_email])

        # If the user resends to the same email, the after_save callback does not handle this
        unless @application.cosigner_email_previously_changed?
          @application.contract.party(:cosigner).notify
        end

        flash[:success] = "Resent agreement to parent"
      end

      redirect_back_or_to application_path(@application)
    end

    private

    def set_application
      @application = Application.find(params[:id])
    end

    # Accepts the answer from either shape: the nested form field the intro
    # screen actually submits, or the bare query param used when we bounce an
    # anonymous applicant through sign-in and back to `start`.
    def teen_led_param
      params.dig(:event_application, :teen_led).presence || params[:teen_led].presence
    end

    # Fuime: a typed event code becomes a cohort, or nothing.
    #
    # A blank field clears the cohort — somebody who pasted the wrong code needs a
    # way to undo it, and the alternative is an applicant permanently attached to
    # an event they are not at.
    #
    # An unrecognised code is NOT an error that blocks saving. The applicant can
    # always submit without one, and refusing to save their whole application over
    # a mistyped code would be a wall in front of the thing they actually came to
    # do. The flash tells them it did not take; the roster board tells the
    # organiser who is stuck.
    def assign_cohort_from_code
      typed = params[:event_application][:cohort_code].to_s.strip

      if typed.blank?
        @application.fuime_cohort = nil
        return
      end

      cohort = ::Fuime::Cohort.for_code(typed)
      if cohort.nil?
        flash[:cohort_code_unknown] = true
        return
      end

      @application.fuime_cohort = cohort
    end

    def application_params
      params.require(:event_application).permit(:name, :description, :political_description, :website_url, :address_line1, :address_line2, :address_city, :address_state, :address_postal_code, :address_country, :referrer, :referral_code, :accessibility_notes, :cosigner_email, :teen_led, :annual_budget, :committed_amount, :planning_duration, :team_size, :funding_source, :previously_applied, :starting_point, :service_type)
    end

    def user_params
      params.require(:event_application).permit(:full_name, :preferred_name, :phone_number, :birthday)
    end

    def record_pageview
      if Event::Application.last_page_vieweds.keys.include?(action_name.to_s) && @application.user == current_user
        @application&.record_pageview(action_name.to_s)
      end
    end

    def prevent_access_after_submission
      unless @application.draft? || current_user.auditor?
        redirect_to application_path(@application)
      end
    end

    def prevent_access_if_archived
      if @application.archived? && !current_user.auditor?
        redirect_to application_path(@application)
      end
    end

  end

end
