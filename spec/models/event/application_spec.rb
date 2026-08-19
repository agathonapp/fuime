# frozen_string_literal: true

require "rails_helper"

RSpec.describe Event::Application, type: :model do
  # FUIME-DIVERGENCE: upstream mirrored every application into a Hack Club Airtable
  # base via Event::ApplicationSyncToAirtableJob on an after_commit hook. Fuime keeps
  # applications entirely in Postgres and reviews them in the HCB admin console, so
  # saving an application must not enqueue any external sync at all.
  describe "saving an application" do
    let!(:application) { create(:event_application) }

    it "does not enqueue any background job" do
      expect {
        application.update!(name: "Updated Name")
      }.not_to have_enqueued_job
    end

    it "does not define the removed Airtable sync constant" do
      expect(defined?(Event::ApplicationSyncToAirtableJob)).to be_nil
    end
  end

  describe "aasm state as the source of truth" do
    let!(:application) { create(:event_application, aasm_state: "submitted") }

    it "exposes a human-readable state for the admin console" do
      expect(application.aasm.human_state).to eq("Submitted")
    end
  end

  # FUIME-DIVERGENCE: the review page used to disable the submit button with no
  # explanation. `submission_blockers` names what is still missing, and shares
  # its required-field list with `application_ready_to_submit?` so the checklist
  # and the actual gate cannot drift apart.
  describe "#submission_blockers" do
    let(:teen) { create(:user, birthday: 15.years.ago, full_name: "Maya Rivera", phone_number: "+18556254225") }

    def complete_teen_application
      create(
        :event_application,
        user: teen,
        teen_led: true,
        name: "Maya's Art Prints",
        # Required to submit since 2026-08-18: it is what decides whether the
        # venture may ever sell, and a "complete" application has answered it.
        business_category: "services",
        description: "I sell custom art prints and stickers.",
        address_line1: "8605 Santa Monica Blvd",
        address_city: "West Hollywood",
        address_state: "CA",
        address_postal_code: "90069",
        address_country: "US",
        referrer: "A friend",
        previously_applied: false,
        cosigner_email: "parent@example.com"
      )
    end

    it "is empty for a fully completed teen-led application" do
      expect(complete_teen_application.submission_blockers).to be_empty
    end

    it "allows a completed teen-led application to be submitted" do
      expect(complete_teen_application.may_mark_submitted?).to be true
    end

    it "does not treat answering \"no\" to previously_applied as missing" do
      application = complete_teen_application
      application.update!(previously_applied: false)

      expect(application.submission_blockers).to be_empty
    end

    it "reports an unanswered previously_applied question" do
      application = complete_teen_application
      application.update!(previously_applied: nil)

      expect(application.submission_blockers).to include("Whether you've used Fuime before")
    end

    it "names each missing field" do
      application = create(:event_application, user: teen, teen_led: true, name: nil)

      expect(application.submission_blockers).to include(
        "Business name", "What your business does", "Street address", "City", "State"
      )
    end

    it "does not demand adult-only fields from a teen-led application" do
      expect(complete_teen_application.submission_blockers).not_to include(
        "Team size", "Annual budget", "Committed amount", "How long you've been planning"
      )
    end

    it "demands adult-only fields from an application that is not teen-led" do
      adult = create(:user, birthday: 30.years.ago, full_name: "Alex Chen", phone_number: "+18556254225")
      application = create(
        :event_application,
        user: adult, teen_led: false,
        name: "Studio", description: "We sell things.",
        address_line1: "1 Main St", address_city: "LA", address_state: "CA",
        address_postal_code: "90069", address_country: "US",
        referrer: "A friend", previously_applied: false
      )

      expect(application.submission_blockers).to include("Team size", "Annual budget")
    end

    it "flags a country Fuime cannot serve" do
      application = complete_teen_application
      application.update!(address_country: Event::Application::DISALLOWED_COUNTRIES.first)

      expect(application.submission_blockers).to include("Fuime is not available in the country you selected")
    end

    it "flags a cosigner email that matches the applicant's own" do
      application = complete_teen_application
      application.update!(cosigner_email: teen.email)

      expect(application.submission_blockers).to include("Your parent's email cannot be the same as your own")
    end

    it "stays consistent with the submit gate" do
      application = complete_teen_application

      expect(application.submission_blockers.empty?).to eq(application.may_mark_submitted?)

      application.update!(referrer: nil)

      expect(application.submission_blockers.empty?).to eq(application.may_mark_submitted?)
    end
  end
end
