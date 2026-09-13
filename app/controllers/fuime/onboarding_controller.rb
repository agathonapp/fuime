# frozen_string_literal: true

# Fuime: the family setup wizard — both ways a family gets onto Fuime.
#
#   /setup              a teen starts, and invites a parent on the way
#   /setup/parent       a parent sets the family up, and invites the teen
#
# ── The rule that shapes everything here ────────────────────────────────────
#
# Under merchant-of-record the parent's signature gates PAYOUTS. It does not
# gate signing up, setting up a venture, listing what you sell, or selling.
# So the teen's parent step asks for an email address and moves on: the invite
# goes out, the teen keeps going, and the only thing that waits on the parent
# is money leaving. Every sentence on these screens has to say that and only
# that — `Event#payout_setup_blockers` is the gate, not `activate_event!`.
#
# The other gate, which is NOT the parent, is Fuime's own human vetting: a new
# venture is created `unvetted` and `Event#offer_publish_blockers` refuses to
# publish until a person approves it. So no screen may promise selling "now".
#
# ── What it reuses, and what it deliberately does not ───────────────────────
#
# Every record this wizard writes goes through the same interface the old flow
# uses: `User#attest_minor_13_plus`, `Event::Application` + `mark_submitted!`,
# `Fuime::FounderAdmission`, `Fuime::GuardianInviteService` (through the
# application's own after-hook), `Guardianship#accept!`. Nothing is duplicated
# and no model is edited to suit this controller.
#
# It does NOT post to `Event::ApplicationsController`. That controller is the
# adult application and the second-venture path and stays exactly as it is;
# sharing its actions would mean one flow's 422 could render the other's views.
# The four lines of cohort lookup both need live in `Fuime::CohortStamp`.
#
# ── Session state ───────────────────────────────────────────────────────────
#
# Nothing legally significant lives only in the session. Every attestation and
# every consent is written to its record in the same request it is given; the
# session holds a draft id and, on the parent side, an unvalidated first name
# and email that nothing is created from until the agreement is signed.
module Fuime
  class OnboardingController < ApplicationController
    include Pundit::Authorization

    layout "fuime_setup"

    # A name-less user is exactly who belongs here, so the redirect that sends
    # them to /setup must not fire once they arrive.
    skip_before_action :redirect_to_onboarding

    before_action :set_step

    TEEN_STEPS = %w[you business name family done].freeze
    PARENT_STEPS = %w[teen sign done].freeze

    TEEN_LABELS = {
      "you" => "You", "business" => "What you do", "name" => "Name it",
      "family" => "Family", "done" => "Done"
    }.freeze
    PARENT_LABELS = { "teen" => "Your teen", "sign" => "Sign", "done" => "Done" }.freeze

    # Long enough that a double-click or a refreshed confirmation cannot mail a
    # teen twice; short enough that "I sent it to the wrong address" is not a
    # support ticket. Mirrors GuardianshipsController::RENEW_COOLDOWN.
    JOIN_RESEND_COOLDOWN = 10.minutes

    MAX_FIRST_NAME_LENGTH = 30

    helper_method :wizard_path, :wizard_steps, :wizard_step, :wizard_step_index,
                  :wizard_progress, :wizard_labels

    # ── The dispatcher ────────────────────────────────────────────────────
    #
    # Everything that can send somebody to /setup arrives here: the login
    # code's completion, `redirect_to_onboarding`, a waitlist admit, a family
    # join link, and the founder typing the URL. It decides which of the two
    # paths they are on and where in it they belong, reading records rather
    # than the session wherever it can — a cleared cookie must not lose a
    # half-finished application.
    def start
      skip_authorization
      return_to = url_from(params[:return_to])

      # 1. The parent path, chosen by the URL or by the Login row's return_to.
      #    That value rides on a database row, not the session, so it survives
      #    the round trip through the emailed code.
      if params[:path] == "parent" || return_to.to_s.start_with?("/setup/parent")
        return redirect_to parent_setup_step_path(parent_state["guardianship_id"].present? ? "done" : "teen")
      end

      # 2. A parent who followed a teen's invite link and signed in on the way.
      #    The accept page collects their name now (guardianships#show), so
      #    there is nothing for this wizard to ask them.
      return redirect_to return_to if return_to.to_s.start_with?("/guardian/")

      if current_user.onboarding? && current_user.guardianships_as_minor.none? &&
         (pending = current_user.guardianships_as_guardian.pending.order(:created_at).last)
        return redirect_to guardianship_path(pending.invite_token)
      end

      # 3. No name yet — the first screen, for a teen starting alone and for a
      #    parent-first teen arriving from their join link.
      if current_user.onboarding?
        return redirect_to teen_setup_step_path("you", return_to: return_to.presence)
      end

      # 4. A parent who has finished and has no venture of their own.
      if current_user.guardianships_as_guardian.active.any? &&
         current_user.events.none? && current_user.applications.not_archived.none?
        return redirect_to guardianships_path
      end

      # 5. Resume a draft at its first incomplete step. Drafts from the old
      #    wizard resume here too — they are the same record.
      draft = current_user.applications.not_archived.draft.order(:id).last
      # A second venture is the old wizard's job: its `family` step says
      # nothing about the free plan's one-venture limit, so a founder would
      # discover it only at submit. `Event::Application#activation_blockers`
      # surfaces it on the status page instead.
      return redirect_to application_path(draft) if draft && current_user.events.any?

      if draft&.teen_led?
        write_teen_state("application_id" => draft.id)
        step = if draft.service_type.blank?
                 "business"
               elsif draft.name.blank? || draft.description.blank?
                 "name"
               else
                 "family"
               end
        return redirect_to teen_setup_step_path(step)
      end
      return redirect_to application_path(draft) if draft

      if current_user.events.any? || current_user.applications.not_archived.any?
        return redirect_to root_path
      end

      # 6. A known adult is never given a teen-led application by this wizard.
      #    `adult_18_plus` is only ever reached by accepting a guardian
      #    agreement, so this is a real answer about a real person.
      if current_user.known_adult?
        return redirect_to new_application_path,
                           flash: { info: "You're signed in as an adult — the standard application is the one for you." }
      end

      redirect_to teen_setup_step_path("business")
    end

    # ── Teen path ─────────────────────────────────────────────────────────

    def teen
      skip_authorization
      case @step
      when "you" then load_you
      when "business" then load_business
      when "name" then load_name
      when "family" then load_family
      when "done" then load_done
      end
      return if performed?

      render "fuime/onboarding/teen/#{@step}"
    end

    def teen_save
      case @step
      when "you" then save_you
      when "business" then save_business
      when "name" then save_name
      when "family" then save_family
      else
        skip_authorization
        redirect_to setup_path
      end
    end

    # ── Parent path ───────────────────────────────────────────────────────

    def parent
      skip_authorization

      refusal = parent_path_refusal
      return redirect_to(refusal[:path], alert: refusal[:alert]) if refusal

      case @step
      when "teen" then load_parent_teen
      when "sign" then load_parent_sign
      when "done" then load_parent_done
      end
      return if performed?

      render "fuime/onboarding/parent/#{@step}"
    end

    def parent_save
      if (refusal = parent_path_refusal)
        skip_authorization
        return redirect_to refusal[:path], alert: refusal[:alert]
      end

      case @step
      when "teen" then save_teen
      when "sign" then save_sign
      else
        skip_authorization
        redirect_to parent_setup_step_path("teen")
      end
    end

    private

    # Why this account may not set up a family, or nil.
    #
    # ── The one that matters ────────────────────────────────────────────
    #
    # `/setup/you` writes `minor_13_plus` for every founder who signs up, and
    # the parent path ends in `attest_adult_18_plus!`, which OVERWRITES it. So
    # without this, a teenager could finish their own signup, walk to
    # /setup/parent, invent an email address, tick the agreement, and come out
    # the other side a `known_adult?` — which is exactly the escalation
    # `Guardianship.signed_up_as_a_young_founder?` was written to stop at the
    # accept page.
    #
    # The test is the attestation itself, not `signed_up_as_a_young_founder?`.
    # That predicate deliberately also requires a venture or a guardianship,
    # because an INVITED parent who ticked 13+ at signup has to be able to
    # accept. Nobody invited this one: they walked in off their own dashboard,
    # so the box they ticked is the answer.
    #
    # A genuine parent-first parent never sees that checkbox — their signup
    # carries `return_to=/setup/parent` and goes straight to this path — so
    # this refuses nobody it should admit.
    def parent_path_refusal
      if current_user.guardianships_as_minor.exists?
        return {
          path: new_guardianship_path,
          alert: "This account is set up as a founder. To add a parent or guardian, invite them from here."
        }
      end

      if current_user.attested_minor_13_plus?
        return {
          path: root_path,
          alert: "This account signed up as a young founder, so it can't also be a parent or guardian. A parent needs their own Fuime account — sign out and sign up with their email."
        }
      end

      nil
    end

    def set_step
      @step = params[:step].to_s
      @path = params[:path].presence || (PARENT_STEPS.include?(@step) && action_name.start_with?("parent") ? "parent" : "teen")
    end

    # ── Teen loaders ──────────────────────────────────────────────────────

    def load_you
      @user = current_user
      @attested = @user.age_attestation.present? || @user.birthday.present?
      @guardian = @user.active_guardian
      @return_to = url_from(params[:return_to])

      # A returning user who already answered both questions has nothing to do
      # here. Without this, "continue setup" from anywhere lands on a form
      # asking a named, attested founder for their name again.
      redirect_to teen_setup_step_path("business") if @user.full_name.present? && @attested
    end

    def load_business
      @application = teen_application
      @starting_points = ::Fuime::ServiceCatalog::STARTING_POINTS
      @services = ::Fuime::ServiceCatalog.sellable
      @selected_point = @application&.starting_point.presence || "have_idea"
      @selected_service = @application&.service_type
    end

    def load_name
      @application = teen_application
      return redirect_to teen_setup_step_path("business") if @application.nil?

      @template = @application.service if @application.started_from_template?
    end

    def load_family
      @application = teen_application
      return redirect_to teen_setup_step_path("business") if @application.nil?
      if @application.name.blank? || @application.description.blank?
        return redirect_to teen_setup_step_path("name")
      end

      # The exact predicate `Event::Application#required_submission_fields` uses
      # to decide whether `cosigner_email` is required, so the screen and the
      # blocker cannot disagree about whether to ask.
      @needs_parent = current_user.needs_guardian? && !current_user.institutionally_vouched_for?
      @guardian = current_user.active_guardian
      @pending = current_user.guardianships_as_minor.pending.order(:created_at).last
      @cohort = @application.fuime_cohort
      @service = @application.service
      # Set by save_family on a 422; an empty list on an ordinary GET.
      @blockers = [] unless defined?(@blockers) && @blockers.is_a?(Array)
    end

    def load_done
      done = teen_state["done"]
      return redirect_to setup_path if done.blank?

      @application = current_user.applications.find_by(id: done["application_id"])
      return redirect_to setup_path if @application.nil?

      @event = @application.event
      return redirect_to application_path(@application) if @event.nil?

      @invite_error = done["invite_error"]
      @guardian = current_user.active_guardian
      @cohort_vetted = @application.fuime_cohort.present? && @event.operator_vetting_approved?
      clear_teen_state
    end

    # The draft this wizard is working on. Session first, then the user's own
    # most recent teen-led draft — so a cleared cookie resumes rather than
    # starting a second application.
    def teen_application
      scope = current_user.applications.not_archived.draft
      by_id = scope.find_by(id: teen_state["application_id"])
      by_id || scope.where(teen_led: true).order(:id).last
    end

    # ── Teen savers ───────────────────────────────────────────────────────

    def save_you
      @user = current_user
      authorize @user, :update?

      @user.assign_attributes(full_name: params.dig(:user, :full_name).to_s.strip)

      # Assigned, not saved: the single save below carries both, and
      # #attest_minor_13_plus deliberately does not persist for exactly this
      # reason (saving early flips `onboarding?` before the controller reads
      # it). This is the only age write in the wizard and it can express one
      # value — `adult_18_plus` is unreachable from any form a user controls.
      if ActiveModel::Type::Boolean.new.cast(params.dig(:user, :age_attestation_confirmed))
        @user.attest_minor_13_plus(ip: request.remote_ip, user_agent: request.user_agent)
      end

      if @user.save(context: :onboarding)
        return_to = url_from(params[:return_to])
        if return_to.present? && !return_to.start_with?("/setup")
          redirect_to return_to
        else
          redirect_to teen_setup_step_path("business")
        end
      else
        load_you_for_error
        flash.now[:alert] = @user.errors.full_messages.to_sentence
        render "fuime/onboarding/teen/you", status: :unprocessable_entity
      end
    end

    def load_you_for_error
      @attested = @user.age_attestation_in_database.present? || @user.birthday.present?
      @guardian = @user.active_guardian
      @return_to = url_from(params[:return_to])
    end

    def save_business
      point = params.dig(:setup, :starting_point).to_s
      service = params.dig(:setup, :service_type).to_s

      unless ::Fuime::ServiceCatalog::STARTING_POINT_KEYS.include?(point) &&
             ::Fuime::ServiceCatalog.sellable.any? { |s| s.key == service }
        @application = teen_application
        load_business
        @selected_point = point.presence || @selected_point
        skip_authorization
        flash.now[:alert] = "Pick where you're starting from and the closest match to what you do."
        return render "fuime/onboarding/teen/business", status: :unprocessable_entity
      end

      @application = teen_application || ::Event::Application.new(user: current_user, teen_led: true)
      is_new = @application.new_record?
      authorize @application, is_new ? :create? : :update?

      # business_category is derived from service_type in a before_validation on
      # the model; it is never assigned here. It decides whether a venture may
      # sell at all (Fuime::OperatorEligibility), so guessing it would be
      # guessing an approval.
      @application.assign_attributes(starting_point: point, service_type: service)
      @application.fuime_cohort ||= ::Fuime::CohortStamp.from_waitlist(session:, user: current_user) if is_new
      @application.save!

      write_teen_state("application_id" => @application.id)
      redirect_to teen_setup_step_path("name")
    end

    def save_name
      @application = teen_application
      return redirect_to teen_setup_step_path("business") if @application.nil?

      authorize @application, :update?
      name = params.dig(:setup, :name).to_s.strip
      description = params.dig(:setup, :description).to_s.strip

      # Placeholders are prompts, never values: a description Fuime wrote is a
      # description Fuime authored, and under merchant-of-record Fuime is
      # already the seller of record for whatever it describes.
      if name.blank?
        return render_name_error("Give it a name — your own words are fine.", name:, description:)
      end
      if description.blank?
        return render_name_error("Say what you do. One sentence is enough.", name:, description:)
      end

      @application.update!(name:, description:)
      redirect_to teen_setup_step_path("family")
    end

    def render_name_error(message, name:, description:)
      @application.assign_attributes(name:, description:)
      @template = @application.service if @application.started_from_template?
      flash.now[:alert] = message
      render "fuime/onboarding/teen/name", status: :unprocessable_entity
    end

    def save_family
      @application = teen_application
      return redirect_to teen_setup_step_path("business") if @application.nil?

      authorize @application, :update?
      @needs_parent = current_user.needs_guardian? && !current_user.institutionally_vouched_for?
      email = params.dig(:setup, :cosigner_email).to_s.strip.downcase.presence

      if ::Fuime::Playground.persona?(current_user.email) && email.present? && !email.end_with?("@fuime.test")
        return render_family_error("Playground personas can only invite @fuime.test addresses.")
      end

      @application.assign_attributes(
        address_country: params.dig(:setup, :address_country).to_s.presence,
        cosigner_email: (@needs_parent ? email : @application.cosigner_email)
      )

      if params[:setup]&.key?(:cohort_code)
        cohort, outcome = ::Fuime::CohortStamp.from_code(params[:setup][:cohort_code])
        @application.fuime_cohort = cohort if outcome != :unknown
        flash.now[:cohort_code_unknown] = true if outcome == :unknown
      end

      @application.save!

      @blockers = @application.submission_blockers
      return render_family_error(nil) if @blockers.any?

      @application.mark_submitted!
      # The same explicit second call Event::ApplicationsController#submit
      # makes: the after_commit hook also runs it, and a second call is a
      # no-op (`already_has_venture`). Kept so a submit still admits even if
      # the commit hook is skipped inside a wrapping transaction.
      ::Fuime::FounderAdmission.new(application: @application.reload).call

      # An attr_accessor set by the submit hook — read it on THIS instance,
      # before the reload below throws the object away.
      invite_error = @application.guardian_invite_error
      @application.reload

      if @application.event.present?
        confetti!
        write_teen_state("done" => { "application_id" => @application.id, "invite_error" => invite_error })
        redirect_to teen_setup_step_path("done")
      else
        clear_teen_state
        blocker = @application.activation_blockers.first.presence
        redirect_to application_path(@application),
                    flash: { error: "Your business is submitted — #{blocker || "we couldn't finish setting it up"}." }
      end
    rescue AASM::InvalidTransition
      @blockers = @application.submission_blockers
      render_family_error("Something's still missing — see the list.")
    end

    def render_family_error(message)
      load_family
      flash.now[:alert] = message if message.present?
      render "fuime/onboarding/teen/family", status: :unprocessable_entity
    end

    # ── Parent loaders ────────────────────────────────────────────────────

    def load_parent_teen
      @teen = parent_state["teen"] || {}
    end

    def load_parent_sign
      teen = parent_state["teen"]
      return redirect_to parent_setup_step_path("teen") if teen.blank?

      @teen_name = teen["first_name"]
      @teen_email = teen["email"]
      @existing = ::User.find_by(email: @teen_email)
      @guardianship = ::Guardianship.find_by(guardian: current_user, minor: @existing) if @existing

      if @guardianship&.active?
        write_parent_state("guardianship_id" => @guardianship.id)
        return redirect_to parent_setup_step_path("done")
      end

      # Unsaved and only for rendering the agreement, which reads the minor's
      # name and email. Nothing is created until the agreement is signed.
      @minor_preview = @existing || ::User.new(email: @teen_email, preferred_name: @teen_name)
      @agreement_partial = ::Guardianship.agreement_partial_for(::Guardianship::CURRENT_AGREEMENT_VERSION)
      @needs_name = current_user.full_name.blank?
      @structural_blockers =
        (@guardianship || ::Guardianship.new(guardian: current_user, minor: @minor_preview))
        .structural_activation_blockers
    end

    def load_parent_done
      id = parent_state["guardianship_id"]
      return redirect_to parent_setup_step_path("teen") if id.blank?

      @guardianship = current_user.guardianships_as_guardian.active.find_by(id:)
      return redirect_to parent_setup_step_path("teen") if @guardianship.nil?

      @teen = @guardianship.minor
      @teen_joined = !@teen.onboarding?
      sent_at = parent_state["join_sent_at"]
      @resend_cooldown = sent_at.present? && Time.zone.parse(sent_at.to_s).to_time > JOIN_RESEND_COOLDOWN.ago
      clear_parent_state
    end

    # ── Parent savers ─────────────────────────────────────────────────────

    # Session only. Nothing is created for a mistyped address before an adult
    # has read and signed the agreement.
    def save_teen
      skip_authorization
      first_name = params.dig(:setup, :teen_first_name).to_s.strip
      email = params.dig(:setup, :teen_email).to_s.strip.downcase
      thirteen_plus = ActiveModel::Type::Boolean.new.cast(params.dig(:setup, :teen_13_plus))

      @teen = { "first_name" => first_name, "email" => email }

      return render_teen_error("Tell us their first name.") if first_name.blank? || first_name.length > MAX_FIRST_NAME_LENGTH
      return render_teen_error("Use your teen's email address, not your own.") if email == current_user.email.to_s.downcase

      # Validated through User's own rules rather than a second definition of
      # "a valid email" — that is what the record will be held to at `sign`,
      # including the disposable-address check, and a rule that disagreed with
      # it would accept an address here and fail after the agreement is signed.
      if (email_error = new_teen_email_error(email))
        return render_teen_error(email_error)
      end

      # L6. The refusal happens here, before anything is signed or created, and
      # nothing about it is persisted — no date of birth, no record of a
      # refused child, and no promise of a younger tier.
      return render_teen_error("Fuime is for founders 13 and up.") unless thirteen_plus

      # Deliberately the same sentence as every other rejection of this field.
      # A distinct message here would confirm both that an account exists at a
      # guessed address and that it is an adult's — an existence oracle behind
      # one signed-in session.
      existing = ::User.find_by(email:)
      if existing&.known_adult?
        return render_teen_error("Use your teen's own email address.")
      end

      if ::Fuime::Playground.persona?(current_user.email) && !email.end_with?("@fuime.test")
        return render_teen_error("Playground personas can only add @fuime.test addresses.")
      end

      write_parent_state("teen" => @teen)
      redirect_to parent_setup_step_path("sign")
    end

    # nil when `email` would be accepted as a new user's address, else the
    # message to show. An address that already belongs to somebody is fine —
    # the parent may be adding themselves to an existing teen's account.
    def new_teen_email_error(email)
      return "Enter their email address." if email.blank?
      return nil if ::User.exists?(email:)

      candidate = ::User.new(email:)
      candidate.valid?
      candidate.errors[:email].first&.then { |message| "That email address #{message}." }
    end

    def render_teen_error(message)
      flash.now[:alert] = message
      render "fuime/onboarding/parent/teen", status: :unprocessable_entity
    end

    # The one transaction of the parent path. Same sequence as
    # GuardianshipsController#accept, with creation in front of it.
    def save_sign
      authorize ::Guardianship, :create_as_guardian?
      load_parent_sign
      return if performed?

      # The tick is the whole legal product of this request, so it is confirmed
      # here where it cannot be skipped, not only in the browser.
      unless ActiveModel::Type::Boolean.new.cast(params[:agree])
        return render_sign_error("Please confirm you agree to the guardian agreement.")
      end

      if @existing&.known_adult?
        return render_sign_error("Use your teen's own email address.")
      end

      # A previously revoked pair is deliberately NOT refused. Migration
      # 20260912120000 scoped the uniqueness index to live rows precisely so a
      # parent who withdrew consent can be asked again without support — the
      # parent signing again IS the recovery.

      failure = nil
      guardianship = nil

      ActiveRecord::Base.transaction do
        if current_user.full_name.blank?
          # A plain save, deliberately not `context: :onboarding` — that
          # validation demands a 13+ attestation, which is the wrong question
          # to put to the adult signing as the responsible party.
          current_user.update!(full_name: params.dig(:setup, :parent_full_name).to_s.strip)
        end

        teen = @existing || ::User.create!(email: @teen_email, creation_method: :family_invite)
        if teen.onboarding? && teen.preferred_name.blank?
          teen.update!(preferred_name: @teen_name.to_s.first(MAX_FIRST_NAME_LENGTH))
        end

        # A pending row from a teen-first invite is reused as it stands, so the
        # two entry orders converge on one guardianship rather than colliding
        # on the unique pair index. Its `initiated_by` stays `minor`, which is
        # true and decides which mail the teen gets.
        guardianship = ::Guardianship.find_by(guardian: current_user, minor: teen) ||
                       ::Guardianship.create!(guardian: current_user, minor: teen, initiated_by: :guardian)

        # The same service GuardianshipsController#accept calls, so there is
        # one path to `adult_18_plus` rather than two that must stay in step.
        # `notify_minor:` is false for a parent-first row: the mail it gates
        # says "your parent accepted your invitation", and this teen never
        # sent one — they get the join link instead.
        result = ::Fuime::GuardianConsentService.new(
          guardianship:,
          ip: request.remote_ip,
          user_agent: request.user_agent,
          notify_minor: guardianship.initiated_by_minor?
        ).call

        unless result.ok?
          failure = result.error
          raise ActiveRecord::Rollback
        end
      end

      return render_sign_error(failure) if failure.present?

      # Only a teen who did not send an invite needs the join link; a
      # teen-first teen already has one and gets the `accepted` mail instead.
      if guardianship.initiated_by_guardian?
        ::Fuime::FamilyMailer.teen_join(guardianship:)
                             .deliver_later(wait_until: ::Fuime::MinorMailWindow.earliest_send_time)
      end

      write_parent_state("guardianship_id" => guardianship.id, "join_sent_at" => Time.current.iso8601)
      confetti!
      redirect_to parent_setup_step_path("done")
    rescue ActiveRecord::RecordInvalid => e
      render_sign_error(e.record.errors.full_messages.to_sentence)
    end

    def render_sign_error(message)
      load_parent_sign unless @agreement_partial
      flash.now[:alert] = message
      render "fuime/onboarding/parent/sign", status: :unprocessable_entity
    end

    # ── Session state ─────────────────────────────────────────────────────

    def teen_state
      (session[:teen_setup] || {}).stringify_keys
    end

    def write_teen_state(attrs)
      session[:teen_setup] = teen_state.merge(attrs.stringify_keys)
    end

    def clear_teen_state
      session.delete(:teen_setup)
    end

    def parent_state
      (session[:parent_setup] || {}).stringify_keys
    end

    def write_parent_state(attrs)
      session[:parent_setup] = parent_state.merge(attrs.stringify_keys)
    end

    def clear_parent_state
      session.delete(:parent_setup)
    end

    # ── View helpers ──────────────────────────────────────────────────────

    def wizard_path
      @path
    end

    def wizard_steps
      wizard_path == "parent" ? PARENT_STEPS : TEEN_STEPS
    end

    def wizard_labels
      wizard_path == "parent" ? PARENT_LABELS : TEEN_LABELS
    end

    def wizard_step
      @step
    end

    def wizard_step_index
      wizard_steps.index(@step) || 0
    end

    def wizard_progress
      ((wizard_step_index + 1) * 100.0 / wizard_steps.length).round
    end

  end
end
