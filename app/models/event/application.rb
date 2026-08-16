# frozen_string_literal: true

# == Schema Information
#
# Table name: event_applications
#
#  id                           :bigint           not null, primary key
#  aasm_state                   :string           not null
#  accessibility_notes          :text
#  address_city                 :string
#  address_country              :string
#  address_line1                :string
#  address_line2                :string
#  address_postal_code          :string
#  address_state                :string
#  airtable_status              :string
#  airtable_synced_at           :datetime
#  annual_budget_cents          :integer
#  approved_at                  :datetime
#  archived_at                  :datetime
#  business_category            :string
#  committed_amount_cents       :integer
#  cosigner_email               :string
#  currently_fiscally_sponsored :boolean
#  description                  :text
#  funding_source               :string
#  last_page_viewed             :string
#  last_viewed_at               :datetime
#  name                         :string
#  planning_duration            :string
#  political_description        :text
#  previously_applied           :boolean
#  project_category             :string
#  referral_code                :string
#  referrer                     :string
#  rejected_at                  :datetime
#  service_type                 :string
#  starting_point               :string
#  submitted_at                 :datetime
#  team_size                    :integer
#  teen_led                     :boolean
#  under_review_at              :datetime
#  videos_watched               :boolean          default(FALSE)
#  website_url                  :string
#  created_at                   :datetime         not null
#  updated_at                   :datetime         not null
#  airtable_record_id           :string
#  event_id                     :bigint
#  user_id                      :bigint           not null
#
# Indexes
#
#  index_event_applications_on_event_id      (event_id)
#  index_event_applications_on_service_type  (service_type) WHERE (service_type IS NOT NULL)
#  index_event_applications_on_user_id       (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (event_id => events.id)
#  fk_rails_...  (user_id => users.id)
#
# Check Constraints
#
#  event_applications_starting_point_known  (starting_point IS NULL OR (starting_point::text = ANY (ARRAY['have_business'::character varying::text, 'have_idea'::character varying::text, 'from_template'::character varying::text])))
#
class Event
  class Application < ApplicationRecord
    # YouTube ids for the onboarding videos an applicant must watch.
    #
    # Upstream HCB hardcoded two Hack Club videos here (Ucz-QT2GPOk,
    # LMh9FCm8iIE) explaining HCB's fiscal sponsorship rules. Those describe a
    # nonprofit programme Fuime does not run, so the step is skipped entirely
    # while this list is empty rather than showing another organization's
    # onboarding as if it were Fuime's.
    #
    # To enable: set FUIME_ONBOARDING_VIDEO_IDS to a comma-separated list of
    # YouTube ids. The step then reappears and is mandatory again.
    ONBOARDING_VIDEO_IDS = ENV.fetch("FUIME_ONBOARDING_VIDEO_IDS", "").split(",").map(&:strip).reject(&:blank?).freeze

    has_paper_trail

    include PgSearch::Model
    pg_search_scope :search_name_or_email, against: :name, associated_against: {
      user: :email
    }

    include AASM
    include Contractable

    include Hashid::Rails

    include PublicIdentifiable
    set_public_id_prefix :apl

    belongs_to :user
    belongs_to :event, optional: true
    belongs_to :contract_event, foreign_key: :event_id, class_name: "Event", inverse_of: :application, optional: true

    has_many :affiliations, as: :affiliable
    has_one :contract, ->{ where.not(aasm_state: :voided) }, inverse_of: :contractable, as: :contractable

    validate :cosigner_cannot_change_after_sign

    # Fuime: the category follows from the service and is never posted directly.
    #
    # `business_category` is what Fuime::OperatorEligibility reads to decide
    # whether a venture may sell, so a form field carrying it would be a form
    # field carrying an approval. It is derived here rather than in the
    # controller so every path that sets a service type gets the same answer —
    # including the console, a fixture, and whatever imports applications next.
    before_validation :derive_business_category

    after_save :check_cosigner_update

    monetize :annual_budget_cents, allow_nil: true
    monetize :committed_amount_cents, allow_nil: true

    include Rails.application.routes.url_helpers

    after_create_commit do
      Event::ApplicationReminderJob.set(wait: 1.day).perform_later(self, 1)
      Event::ApplicationReminderJob.set(wait: 2.days).perform_later(self, 2)
      Event::ApplicationReminderJob.set(wait: 7.days).perform_later(self, 3)
      Event::ApplicationReminderJob.set(wait: 14.days).perform_later(self, 4)
    end

    scope :not_archived, -> { where(archived_at: nil) }
    scope :archived, -> { where.not(archived_at: nil) }

    scope :active, -> { where(archived_at: nil, event_id: nil) }

    # Fuime: the business-type step. See Fuime::ServiceCatalog for the catalog and
    # AddBusinessTypeToEventApplications for why the question is asked at all.
    #
    # Validated on the record rather than only in the controller because
    # `business_category` is read by Fuime::OperatorEligibility to decide whether a
    # venture may sell — a value that arrived by some other path and is not a
    # catalog key would be a category nobody chose, gating real money.
    validates :starting_point,
              inclusion: { in: Fuime::ServiceCatalog::STARTING_POINT_KEYS },
              allow_blank: true

    # `if: :service_type_changed?` is load-bearing, not an optimisation.
    #
    # The catalog is product copy and will be edited — services renamed, retired,
    # split. Validating on every save would mean the day a key leaves the catalog,
    # every application that ever chose it becomes unsaveable: a founder could not
    # fix a typo in their business name because of a decision somebody else made
    # about the menu months later. Only a NEW choice has to be one Fuime currently
    # offers.
    validates :service_type,
              inclusion: {
                in: ->(_) { Fuime::ServiceCatalog.services.map(&:key) },
                message: "isn't a service Fuime offers yet"
              },
              allow_blank: true,
              if: :service_type_changed?

    validates :business_category,
              inclusion: { in: ::Event::BUSINESS_CATEGORIES },
              allow_blank: true

    enum :last_page_viewed, {
      show: "show",
      # Fuime: inserted ahead of project_info — a founder says what kind of
      # business this is before describing it, because a teenager who does not
      # yet know what to sell cannot answer "describe your business" and that is
      # where the funnel loses them.
      business_type: "business_type",
      project_info: "project_info",
      personal_info: "personal_info",
      review: "review",
      agreement: "agreement",
      submission: "submission"
    }

    aasm timestamps: true do
      state :draft, initial: true
      state :submitted
      # An application can be submitted but not yet under review if it is pending on signee or cosigner signatures
      # Adults (>18) will immediately advance to under_review, as they do not sign until they have been approved
      state :under_review
      state :approved
      state :rejected

      event :mark_submitted do
        transitions from: :draft, to: :submitted, if: :ready_to_submit?

        after do
          update!(archived_at: nil)

          # Fuime: the parent's invite goes out the moment the teen applies.
          # The form already collected their email (cosigner_email), the
          # guardian ask was deferred to activation (#44), and activation will
          # refuse until a guardian accepts — so sending the invite here means
          # the parent's clock starts at submission instead of at a page the
          # teen has to remember to visit. Best-effort by design: a bad email
          # must not block the submission, and the manual /guardian/new page
          # remains for recovery.
          if teen_led? && cosigner_email.present? &&
             user.minor_or_unknown_age? && !user.has_active_guardian? &&
             !user.institutionally_vouched_for?
            begin
              Fuime::GuardianInviteService.new(minor: user, guardian_email: cosigner_email).run!
            rescue Fuime::GuardianInviteService::InvalidInvite => e
              Rails.logger.warn("[Fuime] auto guardian invite skipped for application #{hashid}: #{e.message}")
            end
          end

          if teen_led? && send_contract.present?
            Event::ApplicationMailer.with(application: self).confirmation.deliver_later
          else
            # Either not teen-led, or no Fuime agreement is configured yet, so
            # there is nothing to sign. Without this the application would sit
            # in `submitted` forever waiting on a contract that never arrives.
            mark_under_review!
          end
        end
      end

      event :mark_under_review do
        transitions from: [:draft, :submitted], to: :under_review
        after do
          Event::ApplicationMailer.with(application: self).under_review.deliver_later
        end
      end

      event :mark_approved do
        transitions from: :under_review, to: :approved
        after do
          if teen_led? && contract.present?
            contract.party(:hcb).schedule_reminders
          else
            send_contract unless contract.present?
            Event::ApplicationMailer.with(application: self).approved.deliver_later
          end
        end
      end

      event :mark_rejected do
        transitions from: [:submitted, :under_review, :approved], to: :rejected, if: -> { event.nil? }
        after do |rejection_message|
          contract.mark_voided! if contract.present?

          if rejection_message.present?
            Event::ApplicationMailer.with(application: self, rejection_message: rejection_message).rejected.deliver_later
          end
        end
      end

      event :mark_draft do
        transitions from: [:submitted, :under_review], to: :draft
      end
    end

    scope :in_progress, -> { where.not(aasm_state: ["approved", "rejected"]) }

    DISALLOWED_COUNTRIES = %w[IN NG RU CU IR KP SY BY VE SD SS MM AF YE SO PK CF CG ZW LY CM LB IQ].freeze

    # Free tier: does the applicant have room for another venture?
    #
    # Pro (the family subscription) unlocks unlimited — theirs, or any
    # overseeing guardian's. Ventures inside a school programme do not count
    # against the free slot: a kid can run their class venture AND their first
    # personal one for free.
    def free_venture_slot_available?
      user.venture_slot_available?
    end

    def rejection_messages
      generic = <<~MSG.strip
        Hi #{user.first_name},

        Thank you for expressing interest in using Fuime for your project, [#{name}](#{Rails.application.routes.url_helpers.application_url(self)}). After careful consideration, we're unable to move forward with your application at this time.

        If you have any questions, feel free to reach out to us at [support@fuime.com](mailto:support@fuime.com) or reply to this email.

        Best,
        The Fuime Team
      MSG

      # FUIME-DIVERGENCE: upstream's "adult" rejection was Hack Club's own
      # letter — "considering us to be your fiscal sponsor", "our parent
      # nonprofit, Hack Club" — none of which describes Fuime, and all of which
      # would have gone out under Fuime's name to a real applicant. Rewritten
      # for what Fuime actually is: a platform for young founders with a
      # parent, guardian, or school as the responsible party.
      adult = <<~MSG.strip
        Hi #{user.first_name},

        Thank you for applying to run [#{name}](#{Rails.application.routes.url_helpers.application_url(self)}) on Fuime!

        Fuime is built specifically for young founders — students running real businesses with a parent, guardian, or school standing behind them. Ventures led by adults are outside what our platform is designed and priced for, so we're unable to take this one on.

        If a young founder is actually at the center of this business, reply and tell us about them — that changes the picture entirely.

        You can reach us any time at [support@fuime.com](mailto:support@fuime.com) or by replying to this email.

        Best,
        The Fuime Team
      MSG

      mission = <<~MSG.strip
        Hi #{user.first_name},

        Thank you for expressing interest in using Fuime for your project, [#{name}](#{Rails.application.routes.url_helpers.application_url(self)}). After careful consideration, we're unable to move forward with your application at this time. Your project's mission doesn't align with Fuime's guidelines, and as a result, we cannot approve your application.

        If you have any questions, feel free to reach out to us at [support@fuime.com](mailto:support@fuime.com) or reply to this email.

        Best,
        The Fuime Team
      MSG

      country = <<~MSG.strip
        Hi #{user.first_name},

        Thank you for expressing interest in using Fuime for your project, [#{name}](#{Rails.application.routes.url_helpers.application_url(self)}). We really want to support projects from all around the world. However, due to regulatory restrictions and incompatible financial systems, we are unable to partner with organizations that operate in certain countries.

        We're sorry for not being able to support you on your journey and wish you all the best. If you have any questions, feel free to reach out to us at [support@fuime.com](mailto:support@fuime.com) or reply to this email.

        Best,
        The Fuime team
      MSG

      {
        generic:,
        adult:,
        mission:,
        country:
      }
    end

    # Fuime: the chosen service, or nil. The one place a view or mailer should ask
    # — nothing else should be matching on `service_type` strings.
    def service
      return nil if service_type.blank?

      Fuime::ServiceCatalog.find(service_type)
    end

    def started_from_template?
      starting_point == "from_template"
    end

    def next_step
      return "Choose what kind of business" if business_category.blank?
      return "Tell us about your project" if name.blank? || description.blank?
      return "Add your information" if address_line1.blank? || address_city.blank? || address_country.blank? || address_postal_code.blank?
      return "Review and submit" if draft?
      return "Sign the Fuime agreement" if contract.present? && ((submitted? && teen_led?) || (approved? && !teen_led?))
      return "We're reviewing your application" if submitted? || under_review?
      return "Start spending!" if event.present?
      return "" if rejected?
      # Approved but not yet activated. Without this the method returns nil and
      # the application card falls back to its "We're reviewing your
      # application" default, contradicting the Approved badge next to it.
      return "Waiting on Fuime to finish setting up your account" if approved?
    end

    def completion_percentage
      return 10 if next_step == "Choose what kind of business"
      return 25 if next_step == "Tell us about your project"
      return 50 if next_step == "Add your information"
      return 75 if next_step == "Review and submit"
      return 100 if submitted? || under_review? || approved?

      0
    end

    def political?
      political_description.present? && political_description.strip.length.positive?
    end

    def contract_notify_when_sent
      false
    end

    def contract_redirect_path
      Rails.application.routes.url_helpers.application_path(self)
    end

    def contract_notify_hcb?
      !teen_led? || contract.reissue?
    end

    def send_contract(reissue_messages: {}, reissue_of: nil, **options)
      # No Fuime agreement is configured (see Event::Plan#contract_docuseal_template_id).
      # Returning nil rather than raising: an unconfigured contract is the
      # expected state until Fuime has its own DocuSeal template, and callers
      # skip the signing step on a nil contract.
      return nil unless Event::Plan::Standard.new.contract_available?

      if name.nil? || description.nil?
        raise StandardError.new("Cannot create a contract for application #{hashid}: missing name and/or description")
      end

      if cosigner_email.present? && !user.is_minor?
        update!(cosigner_email: nil)
      end

      fs_contract = nil
      ActiveRecord::Base.transaction do
        fs_contract = Contract::FiscalSponsorship.create!(
          contractable: self,
          include_videos: false,
          external_template_id: Event::Plan::Standard.new.contract_docuseal_template_id,
          prefills: { "public_id" => public_id, "name" => name, "description" => description },
          reissue_of:
        )
        fs_contract.parties.create!(user:, role: :signee)
        fs_contract.parties.create!(external_email: cosigner_email, role: :cosigner) if cosigner_email.present?
      end

      fs_contract.send!(reissue_messages:)
      fs_contract.party(:cosigner)&.notify unless reissue_of.present?

      fs_contract
    end

    def response_business_days
      teen_led? ? 2 : 10
    end

    def status_color
      return :muted if draft? || submitted?
      return :blue if under_review?
      return :green if approved?
      return :red if rejected?

      :muted
    end

    def on_contract_party_signed(party)
      if party.contract.parties.not_hcb.all?(&:signed?) && party.contract.party(:hcb).pending? && submitted?
        mark_under_review!
      end
    end

    def check_cosigner_update
      if contract.present? && cosigner_email_previously_changed?
        contract.mark_voided!
        send_contract
      end
    end

    def record_pageview(last_page_viewed)
      update!(last_viewed_at: Time.current, last_page_viewed:)
    end

    # `tags` arrives straight from `params[:tags]`, which is nil when the admin
    # selects none — the default only applies to an omitted argument, not an
    # explicit nil, so this raised `undefined method 'filter' for nil`.
    def activate_event!(risk_level:, tags: nil, point_of_contact: nil)
      tags = Array(tags)
      # With no Fuime agreement configured there is no contract to sign, so
      # activation proceeds on admin approval alone. Once a real template is
      # set, contracts exist again and the signed check below applies as before.
      if contract.present?
        contract.party(:hcb).sync_with_docuseal
        contract.reload
        raise "Contract must be signed before activation" unless contract.signed?
      end

      # Fuime: THE guardian gate for the deferred-onboarding flow. Signup and
      # application no longer demand a parent up front — this is where the
      # requirement lands instead, because activation is the moment a venture
      # (and a manager seat on it) comes into existence. Without this, an admin
      # could activate a guardianless minor's application and produce a venture
      # its owner cannot act on; with it, the L2 control is exactly as strong as
      # before, just later in the funnel. Institutionally sponsored applicants
      # (school students) pass — the school is their responsible adult. So do
      # staff applicants (User#staff?): a Fuime admin standing up their own
      # venture has no birthday on file and so reads as a parentless minor,
      # which left staff unable to activate even a demo. Note this tests the
      # APPLICANT, not whoever is clicking activate — an admin activating a
      # teen's application is still held to the guardian requirement, which is
      # the case this gate was written for.
      if user.minor_or_unknown_age? && !user.has_active_guardian? &&
         !user.institutionally_vouched_for? && !user.staff?
        raise ArgumentError,
              "Cannot activate #{hashid}: #{user.email} is a minor with no active guardian. " \
              "Their parent or guardian must accept the guardianship invite first (L2)."
      end

      # The free tier includes ONE venture; the family plan (Pro) is unlimited.
      # Enforced here at activation — the same seam as the guardian gate above —
      # because this is where a venture comes into existence, and an admin
      # reading the error knows exactly what unblocks it. School ventures never
      # consume the slot and school students are never limited: the school's
      # contract is per-student, not per-venture.
      unless user.institutionally_vouched_for? || free_venture_slot_available?
        raise ArgumentError,
              "Cannot activate #{hashid}: the free plan includes one venture, and " \
              "#{user.email} already has one. The family plan ($#{Event::Plan::Pro.new.monthly_fee_cents / 100}/mo) " \
              "covers unlimited businesses."
      end

      self.with_lock do
        raise ArgumentError.new("Event was already created") if event.present?

        # With no contract there is no `hcb` party to fall back to, so an
        # activation without an explicit point of contact would raise on nil.
        poc_user = point_of_contact.presence || contract&.party(:hcb)&.user
        raise ArgumentError, "Cannot activate #{hashid}: no point of contact and no contract to take one from" if poc_user.nil?

        Event.create!(
          name:,
          country: address_country,
          point_of_contact_id: poc_user.id,
          application: self,
          # Fuime: carried from the application rather than left blank.
          #
          # Nothing used to set this, so every venture the funnel produced started
          # with no category — and under merchant-of-record
          # Fuime::OperatorEligibility::ELIGIBLE_CATEGORIES is `%w[services]`,
          # which a blank does not satisfy. Ventures were created pre-blocked from
          # selling and the vetting queue was where anyone found out.
          #
          # Still nullable on the way in: applications that predate the
          # business-type step have nothing to carry, and inventing "services" for
          # them would be inventing the answer that unblocks selling.
          business_category: business_category.presence,
          event_tags: tags.filter { |tag| EventTag::Tags::ALL.include?(tag) }.map { |tag| EventTag.find_or_create_by!(name: tag) },
          risk_level:
        )
        # Only a signed contract produces a countersigned PDF to file. Without a
        # configured agreement there is no document — this call raised on nil and
        # aborted the whole activation, so the business was never created.
        contract.create_document! if contract.present?

        service = OrganizerPositionInviteService::Create.new(event:, sender: poc_user, user_email: user.email, is_signee: true, role: :manager, initial: true)
        invite = service.model
        service.run!

        invite.accept(application_contract: contract)

        affiliations.each do |affiliation|
          affiliation_copy = affiliation.dup
          affiliation_copy.affiliable = event
          affiliation_copy.save!
        end
      end

      Event::ApplicationMailer.with(application: self).activated.deliver_later

      self
    end

    def archive!
      contract&.mark_voided! if contract&.may_mark_voided?
      mark_draft! if may_mark_draft?

      update!(archived_at: Time.current)
    end

    def unarchive!
      send_contract if contract.nil? && approved?

      update!(archived_at: nil)
    end

    def archived?
      archived_at.present?
    end

    def respondent_url
      url_for(controller: "event/applications", action: last_page_viewed || "show", id: hashid)
    end

    def default_tags
      tags = []

      tags << EventTag::Tags::ORGANIZED_BY_TEENAGERS if teen_led?
      tags << EventTag::Tags::ROBOTICS_TEAM if affiliations.any? { |affiliation| affiliation.is_first? || affiliation.is_vex? }
      tags << EventTag::Tags::HACK_CLUB if affiliations.any? { |affiliation| affiliation.is_hack_club? }

      tags
    end

    # Human-readable list of what is still blocking submission.
    #
    # `may_mark_submitted?` only returns a boolean, so the review page used to
    # disable the submit button with no way for the applicant to discover what
    # was wrong. This drives an explicit checklist instead.
    def submission_blockers
      blockers = []

      FIELD_LABELS.each do |field, label|
        next unless required_submission_fields.include?(field)

        blockers << label if self[field].nil? || self[field] == ""
      end

      USER_FIELD_LABELS.each do |field, label|
        blockers << label unless user[field].present?
      end

      if address_country.present? && address_country.in?(DISALLOWED_COUNTRIES)
        blockers << "Fuime is not available in the country you selected"
      end

      if cosigner_email.present? && cosigner_email == user.email
        blockers << "Your parent's email cannot be the same as your own"
      end

      blockers
    end

    private

    # Fuime. Only ever moves the category forward from a known service key; a
    # service key that is not in the catalog leaves it alone rather than clearing
    # it, so retiring a key later cannot silently un-categorise an application
    # that was already reviewed and approved under it.
    def derive_business_category
      return if service_type.blank?

      derived = Fuime::ServiceCatalog.category_for(service_type)
      self.business_category = derived if derived.present?
    end

    FIELD_LABELS = {
      "name"                   => "Business name",
      "description"            => "What your business does",
      "address_line1"          => "Street address",
      "address_city"           => "City",
      "address_state"          => "State",
      "address_postal_code"    => "Zip code",
      "address_country"        => "Country",
      "referrer"               => "How you heard about Fuime",
      "previously_applied"     => "Whether you've used Fuime before",
      "cosigner_email"         => "Parent or guardian email",
      "planning_duration"      => "How long you've been planning",
      "team_size"              => "Team size",
      "annual_budget_cents"    => "Annual budget",
      "committed_amount_cents" => "Committed amount",
      "funding_source"         => "Source of your funding"
    }.freeze

    USER_FIELD_LABELS = {
      "full_name"    => "Your full name",
      "phone_number" => "Your phone number",
      "birthday"     => "Your birthday"
    }.freeze

    def required_submission_fields
      fields = ["name", "description", "address_line1", "address_city", "address_state", "address_postal_code", "address_country", "referrer", "previously_applied"]

      # A parent's email is required only while the guardian question is OPEN.
      # A second application from the same teen has nothing to ask — their
      # guardianship is per-person and already active — and a school student
      # must never be asked for a parent at all (#37: the school vouches).
      # Requiring it unconditionally forced both to invent an answer for a
      # field the system would then ignore.
      if user.is_minor? && !user.has_active_guardian? && !user.institutionally_vouched_for?
        fields.push("cosigner_email")
      end

      unless teen_led?
        fields += ["planning_duration", "team_size", "annual_budget_cents", "committed_amount_cents"]
        fields.push("funding_source") if committed_amount&.positive?
      end

      fields
    end

    def cosigner_cannot_change_after_sign
      if cosigner_email_changed? && contract&.party(:cosigner)&.signed?
        errors.add(:cosigner_email, "cannot change after the cosigner has signed")
      end
    end

    def ready_to_submit?
      application_ready_to_submit? && user_ready_to_submit?
    end

    def application_ready_to_submit?
      missing_fields = required_submission_fields.any? do |field|
        self[field].nil? || self[field] == ""
      end

      !missing_fields && !address_country.in?(DISALLOWED_COUNTRIES) && !(cosigner_email.present? && cosigner_email == user.email)
    end

    def user_ready_to_submit?
      required_fields = ["full_name", "phone_number", "birthday"]

      missing_fields = required_fields.any? do |field|
        !user[field].present?
      end

      !missing_fields
    end

  end

end
