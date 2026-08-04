# frozen_string_literal: true

# Fuime: collect the guardian's identity details and forward them to Stripe.
#
# Needed only by the `:cards_enabled` profile, where `requirement_collection =
# application` makes Fuime responsible for gathering what Stripe needs. On the default
# `:payments_only` profile Stripe collects directly and this service REFUSES to run —
# see #ensure_fuime_must_collect!. That refusal is the point: collecting an SSN Fuime
# has no need for would be taking on breach liability for nothing.
#
# ── The one rule ────────────────────────────────────────────────────────────
#
# IDENTITY VALUES PASS THROUGH. They arrive as method arguments, go into a Stripe API
# call, and are never assigned to an ActiveRecord attribute, written to disk, cached, or
# logged. What persists is a GuardianVerification holding metadata only: the method, the
# vendor ref, timestamps, the doc-version hash, and IP/UA (L4).
#
# For the ID document specifically, the image goes STRAIGHT TO STRIPE via the Files API
# and Fuime keeps only the returned token. That is what makes "verify then delete"
# structurally true rather than a deletion job that might not have run: Fuime never
# persists the bytes in the first place, and the evidence still exists at the vendor if
# it is ever needed under subpoena.
#
# ── An API asymmetry that fails silently ────────────────────────────────────
#
# Uploading a file FOR a connected account needs the `Stripe-Account` header, because
# the file must belong to that account. Updating a connected account does NOT — the
# account id is the first argument and the call is made with the platform key. Passing
# `stripe_account` to Account.update, or omitting it from File.create, produces errors
# that read like permission problems rather than like the wrong header. Hence two
# distinct option builders below, named for what they do.
module Fuime
  class RequirementCollectionService
    class Error < StandardError; end
    class CollectionNotRequired < Error; end
    class NothingSubmitted < Error; end

    # Mapped to Stripe's `individual` shape. Keys are what callers pass; values are how
    # they are nested for Stripe. Anything not in here is not forwarded, so a stray
    # param cannot become an unplanned disclosure to Stripe.
    SIMPLE_FIELDS = {
      first_name: :first_name,
      last_name: :last_name,
      email: :email,
      phone: :phone,
      # Last four only. Stripe requires the full SSN (`id_number`) above $500K in
      # processing, which Fuime is nowhere near; until then last-4 is both sufficient
      # and the smaller thing to be trusted with.
      ssn_last_4: :ssn_last_4,
      id_number: :id_number
    }.freeze

    def initialize(event:, guardian:)
      @event = event
      @guardian = guardian
    end

    # What Stripe is still waiting for, as raw Stripe field identifiers.
    def outstanding_requirements
      return [] if account.blank?

      (account.requirements_currently_due + account.requirements_past_due).uniq
    end

    # Guardian-facing sentences for those requirements.
    #
    # Stripe's identifiers are dotted machine strings (`individual.id_number`,
    # `individual.verification.document`) and are not a fixed list, so unknown ones are
    # passed through humanised rather than dropped — a requirement nobody can see is a
    # venture that silently never activates.
    def outstanding_descriptions
      outstanding_requirements.map { |req| describe_requirement(req) }
    end

    # Forward the guardian's details to Stripe and record that it happened.
    #
    # `details` holds identity values and is never persisted. `document` is an uploaded
    # file (anything responding to #read) and goes straight to Stripe.
    def submit!(details: {}, document: nil, verification_method: GuardianVerification::ID_AND_DATABASE,
                consent_ip: nil, consent_user_agent: nil, doc_version_hash: nil)
      ensure_fuime_must_collect!

      individual = build_individual(details)
      forwarded = individual_field_names(details)

      # Uploaded before the account update so the token can be attached in one call,
      # and so a failed upload does not leave a half-updated account.
      document_token = nil
      if document.present?
        document_token = upload_document!(document)
        individual[:verification] = { document: { front: document_token } }
        forwarded << "id_document"
      end

      raise NothingSubmitted, "There was nothing to send to Stripe." if individual.blank?

      # Snapshotted BEFORE the update, because afterwards Stripe has already cleared
      # whatever was satisfied and the record would not show what was asked for.
      requirements_snapshot = { "currently_due" => account.requirements_currently_due,
                                "past_due"      => account.requirements_past_due
}

      updated = Stripe::Account.update(
        account.stripe_id,
        { individual: individual },
        platform_request_options
      )
      account.sync_from_stripe!(updated)

      record_verification!(
        verification_method:,
        forwarded:,
        requirements_snapshot:,
        consent_ip:,
        consent_user_agent:,
        doc_version_hash:,
        document_token:
      )
    rescue Stripe::StripeError => e
      # Deliberately does NOT interpolate the params into the message. A Stripe
      # validation error can echo the submitted value, and a message containing an SSN
      # would end up in logs and error reports — reintroducing exactly the exposure
      # this service exists to avoid.
      Rails.logger.error("[Fuime] requirement submission failed for event #{@event.id}: #{e.class}")
      raise Error, "Stripe could not accept these details. Please check them and try again."
    end

    private

    def account
      @account ||= @event.stripe_connected_account
    end

    # Fuime collects ONLY where Stripe has made it Fuime's job. On the payments-only
    # profile Stripe collects directly, so running this would gather an SSN Fuime has no
    # use for and no obligation to hold.
    def ensure_fuime_must_collect!
      if account.blank? || account.stripe_id.blank?
        raise CollectionNotRequired, "This venture has no Stripe account yet."
      end

      unless account.cards_profile?
        raise CollectionNotRequired,
              "This venture collects its requirements through Stripe directly, so Fuime must not " \
              "gather identity details for it."
      end
    end

    def build_individual(details)
      details = (details || {}).symbolize_keys
      individual = {}

      SIMPLE_FIELDS.each do |param, stripe_key|
        value = details[param]
        individual[stripe_key] = value if value.present?
      end

      if details[:dob].present?
        individual[:dob] = normalize_dob(details[:dob])
      end

      address = normalize_address(details[:address])
      individual[:address] = address if address.present?

      individual
    end

    # Field NAMES for the audit record. Derived from what was actually sent rather than
    # from what the caller intended, so the record cannot overstate the disclosure.
    def individual_field_names(details)
      details = (details || {}).symbolize_keys
      names = SIMPLE_FIELDS.keys.select { |k| details[k].present? }.map(&:to_s)
      names << "dob" if details[:dob].present?
      names << "address" if normalize_address(details[:address]).present?
      names
    end

    # The image goes to Stripe and Fuime keeps the token. Nothing is written to disk by
    # this method; the tempfile behind an uploaded file is Rails' own and is reaped with
    # the request.
    def upload_document!(document)
      file = Stripe::File.create(
        {
          purpose: "identity_document",
          file: document
        },
        connected_account_request_options
      )
      file.id
    end

    def record_verification!(verification_method:, forwarded:, requirements_snapshot:,
                             consent_ip:, consent_user_agent:, doc_version_hash:, document_token:)
      GuardianVerification.create!(
        event: @event,
        user: @guardian,
        verification_method:,
        vendor: "stripe",
        # The Stripe File token, when there was a document. This is the L4 "vendor ref":
        # it resolves to evidence Stripe holds, and holds nothing itself.
        vendor_ref: document_token,
        fields_forwarded: forwarded.uniq,
        stripe_requirements_snapshot: requirements_snapshot,
        doc_version_hash:,
        submitted_at: Time.current,
        # Stripe verifies asynchronously, so acceptance is recorded later by the
        # account.updated webhook, not claimed here.
        accepted_at: nil,
        # Fuime forwarded the bytes and kept none, so the release is simultaneous with
        # the submission rather than a later deletion job that might not run.
        evidence_released_at: document_token.present? ? Time.current : nil,
        consent_ip:,
        consent_user_agent:
      )
    end

    def normalize_dob(dob)
      return dob.symbolize_keys.slice(:day, :month, :year) if dob.is_a?(Hash)

      date = dob.is_a?(Date) ? dob : Date.parse(dob.to_s)
      { day: date.day, month: date.month, year: date.year }
    rescue Date::Error
      nil
    end

    def normalize_address(address)
      return nil if address.blank?

      address = address.symbolize_keys
      normalized = {
        line1: address[:line1],
        line2: address[:line2],
        city: address[:city],
        state: address[:state],
        postal_code: address[:postal_code],
        country: address[:country].presence || "US"
      }.compact

      # `country` alone is a default, not a submission. Returning it would record an
      # address as forwarded when none was.
      normalized.keys == [:country] ? nil : normalized
    end

    def describe_requirement(requirement)
      case requirement
      when "individual.first_name", "individual.last_name"
        "The account owner's full legal name"
      when "individual.dob.day", "individual.dob.month", "individual.dob.year"
        "The account owner's date of birth"
      when "individual.address.line1", "individual.address.city",
           "individual.address.state", "individual.address.postal_code"
        "The account owner's home address"
      when "individual.ssn_last_4"
        "The last 4 digits of the account owner's Social Security number"
      when "individual.id_number"
        "The account owner's full Social Security number"
      when "individual.verification.document"
        "A photo of the account owner's government-issued ID"
      when "individual.phone", "individual.email"
        "The account owner's contact details"
      when "business_profile.url", "business_profile.mcc"
        "What the business sells"
      when "external_account"
        "A bank account for payouts"
      when "tos_acceptance.date", "tos_acceptance.ip"
        "Acceptance of Stripe's terms"
      else
        # Passed through rather than swallowed. Stripe adds requirement identifiers, and
        # one nobody can see is a venture that never activates with no explanation.
        requirement.to_s.tr(".", " ").humanize
      end
    end

    # Updating a connected account: platform key, account id as the first argument, NO
    # Stripe-Account header. See the class comment.
    def platform_request_options
      { api_key: StripeService.secret_key }
    end

    # Uploading a file that must BELONG to the connected account: Stripe-Account header
    # required.
    def connected_account_request_options
      { api_key: StripeService.secret_key, stripe_account: account.stripe_id }
    end

  end
end
