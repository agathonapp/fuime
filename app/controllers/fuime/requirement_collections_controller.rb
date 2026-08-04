# frozen_string_literal: true

# Fuime: the guardian supplies their own identity details, for the cards profile.
#
# This is the onboarding surface for `:cards_enabled` ventures, where
# `requirement_collection = application` makes Fuime responsible for gathering what
# Stripe needs. Payments-only ventures do NOT come here — Stripe collects from them
# directly through the embedded component in Fuime::PaymentSetupsController, and
# Fuime::RequirementCollectionService refuses to run for them.
#
# ── Authorization is deliberately narrow ────────────────────────────────────
#
# `setup_payments?` is the guardian (plus admins), and that is exactly right here for a
# stronger reason than usual: the details being submitted ARE the guardian's own
# identity. A teen must never be on this screen, both because they cannot supply an
# adult's SSN and because asking them to would invite them to go and find it.
#
# ── Nothing sensitive is held by this controller ────────────────────────────
#
# Params go straight into the service and are never assigned to an instance variable
# that a view could render, never flashed, and never re-rendered into the form on
# error. A validation failure re-asks rather than echoing values back, which is a worse
# experience and the correct one: a re-rendered form puts an SSN into the HTML of an
# error page.
module Fuime
  class RequirementCollectionsController < ApplicationController
    before_action :set_event
    before_action :authorize_collection
    before_action :ensure_cards_profile

    def show
      @connected_account = @event.stripe_connected_account
      @outstanding = service.outstanding_descriptions
      @latest_verification = GuardianVerification
                             .where(event: @event, user: acting_guardian)
                             .recent_first
                             .first
      @doc_version_hash = disclosure_version_hash
    end

    def create
      service.submit!(
        details: identity_details,
        document: params[:id_document],
        verification_method: GuardianVerification::ID_AND_DATABASE,
        consent_ip: request.remote_ip,
        consent_user_agent: request.user_agent,
        doc_version_hash: disclosure_version_hash
      )

      redirect_to fuime_payment_setup_path(event_slug: @event.slug),
                  notice: "Thanks — we've sent your details to Stripe. They usually confirm " \
                          "within a few minutes, and this page will update when they do."
    rescue Fuime::RequirementCollectionService::NothingSubmitted
      redirect_to fuime_requirement_collection_path(event_slug: @event.slug),
                  alert: "Please fill in at least one of the details Stripe is asking for."
    rescue Fuime::RequirementCollectionService::CollectionNotRequired => e
      redirect_to fuime_payment_setup_path(event_slug: @event.slug), alert: e.message
    rescue Fuime::RequirementCollectionService::Error => e
      # The service has already stripped Stripe's message, which can echo a submitted
      # value. Redirect rather than re-render so nothing is repopulated into the form.
      redirect_to fuime_requirement_collection_path(event_slug: @event.slug), alert: e.message
    end

    private

    def set_event
      @event = Event.find_by!(slug: params[:event_slug])
    end

    def authorize_collection
      authorize @event, :setup_payments?
    end

    def ensure_cards_profile
      account = @event.stripe_connected_account
      return if account&.cards_profile?

      redirect_to fuime_payment_setup_path(event_slug: @event.slug),
                  alert: "This venture's payment details are collected by Stripe directly."
    end

    # Pulled out by name rather than with `permit!` so an unexpected param cannot
    # become an unplanned disclosure to Stripe. The service allowlists again on its
    # side; this is the outer of the two.
    def identity_details
      {
        first_name: params[:first_name],
        last_name: params[:last_name],
        dob: params[:dob],
        ssn_last_4: params[:ssn_last_4],
        id_number: params[:id_number],
        phone: params[:phone],
        address: {
          line1: params[:line1],
          line2: params[:line2],
          city: params[:city],
          state: params[:state],
          postal_code: params[:postal_code]
        }.compact_blank
      }.compact_blank
    end

    # Identifies WHICH version of the disclosure text the guardian was shown, so the
    # consent record proves what they agreed to without storing a copy per guardian
    # (L4). Derived from the template so editing the copy changes the hash — the point
    # is that it cannot silently drift.
    def disclosure_version_hash
      @disclosure_version_hash ||= begin
        path = Rails.root.join("app/views/fuime/requirement_collections/_disclosure.html.erb")
        Digest::SHA256.hexdigest(File.read(path))[0, 16]
      rescue Errno::ENOENT
        "unknown"
      end
    end

    def service
      @service ||= Fuime::RequirementCollectionService.new(event: @event, guardian: acting_guardian)
    end

    # Which adult is being verified. For a guardian doing their own ward's venture that
    # is simply them. An admin acting in support must not be recorded as the verified
    # party, so they resolve to the venture's actual overseeing guardian — the same
    # reasoning as Fuime::PaymentSetupsController#acting_guardian.
    def acting_guardian
      @acting_guardian ||=
        if @event.overseeing_guardians.exists?(id: current_user&.id)
          current_user
        else
          @event.overseeing_guardians.first
        end
    end

  end
end
