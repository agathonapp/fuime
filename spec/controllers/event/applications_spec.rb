# frozen_string_literal: true

require "rails_helper"

RSpec.describe Event::ApplicationsController, type: :controller do
  include SessionSupport

  let(:user) { create(:user, birthday: 15.years.ago, full_name: "Maya Rivera", phone_number: "+18556254225") }

  before { create_session(user, verified: true) }

  # FUIME-DIVERGENCE: the intro screen's "Are you under 18?" radio is rendered by
  # `form_with model:`, so it posts as event_application[teen_led]. `create` only
  # read the bare params[:teen_led], so every application was created teen_led=false.
  # That pushed teen applicants onto the adult branch of the submit gate, which
  # requires four fields the teen form never renders — leaving the submit button
  # permanently disabled with no explanation.
  describe "#create" do
    it "records teen_led from the nested form field" do
      post :create, params: { event_application: { teen_led: "true" } }

      expect(Event::Application.last.teen_led).to be true
    end

    it "records a non-teen application from the nested form field" do
      post :create, params: { event_application: { teen_led: "false" } }

      expect(Event::Application.last.teen_led).to be false
    end

    it "still accepts the bare param used by the post-sign-in redirect" do
      post :create, params: { teen_led: "true" }

      expect(Event::Application.last.teen_led).to be true
    end

    it "redirects to the project info step" do
      post :create, params: { event_application: { teen_led: "true" } }

      expect(response).to redirect_to(project_info_application_path(Event::Application.last))
    end
  end

  describe "#submit" do
    let(:application) do
      create(
        :event_application,
        user:,
        teen_led: true,
        name: "Maya's Art Prints",
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

    it "submits a complete teen-led application" do
      post :submit, params: { id: application.hashid }

      expect(application.reload).not_to be_draft
    end

    it "does not strand a submitted application in the draft state" do
      post :submit, params: { id: application.hashid }

      expect(application.reload.aasm_state).to be_in(%w[submitted under_review])
    end

    it "sends an incomplete application back to review with an explanation" do
      application.update!(referrer: nil)

      post :submit, params: { id: application.hashid }

      expect(response).to redirect_to(review_application_path(application))
      expect(flash[:error]).to be_present
    end
  end
end
