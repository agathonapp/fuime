# frozen_string_literal: true

require "rails_helper"

# Fuime: the business-type step, and the bug it exists to fix.
#
# The step is new UI, but the thing worth protecting is older than the UI: nothing
# used to set `Event#business_category` from an application, so every venture the
# funnel produced started blank — and under merchant-of-record
# `Fuime::OperatorEligibility::ELIGIBLE_CATEGORIES` is `%w[services]`, which a
# blank does not satisfy. Ventures were created already unable to sell.
RSpec.describe Event::ApplicationsController, type: :controller do
  include SessionSupport
  render_views

  let(:user) { create(:user, birthday: 16.years.ago.to_date) }
  let(:application) { create(:event_application, user:, teen_led: true) }

  before { create_session(user, verified: true) }

  describe "GET #business_type" do
    it "offers the three-way fork and the sellable services" do
      get :business_type, params: { id: application.id }

      expect(response).to have_http_status(:ok)
      body = CGI.unescapeHTML(response.body)
      expect(body).to include("Where are you starting from?")
      expect(body).to include("Start from a template")
      expect(body).to include("Tutoring")
    end

    # L8's failure mode in miniature: a picker offering categories the app then
    # blocks at vetting is the site describing a product that does not exist.
    it "offers nothing outside the launch scope" do
      get :business_type, params: { id: application.id }

      body = CGI.unescapeHTML(response.body)
      # The scope card. Its heading stopped being "Services first" when
      # OperatorEligibility::ELIGIBLE_CATEGORIES gained `digital` and the catalog
      # gained templates resolving to it — copy that closes a door the app has
      # opened is the same L8 failure as copy that opens one the app has closed.
      expect(body).to include("What you can sell today")
      expect(body).not_to match(/babysit/i)
    end
  end

  describe "PATCH #update from the business-type step" do
    def choose!(service_type:, starting_point: "have_idea")
      patch :update, params: {
        id: application.id,
        event_application: { starting_point:, service_type: },
        return_to: project_info_application_path(application)
      }
    end

    it "records the answers and derives the category" do
      choose!(service_type: "lawn_and_garden")

      application.reload
      expect(application.starting_point).to eq("have_idea")
      expect(application.service_type).to eq("lawn_and_garden")
      expect(application.business_category).to eq("services")
    end

    it "moves the applicant on to describing the business" do
      choose!(service_type: "tutoring")

      expect(response).to redirect_to(project_info_application_path(application))
    end

    # `business_category` is what OperatorEligibility reads to decide whether a
    # venture may sell, so a form field carrying it would be a form field
    # carrying an approval.
    it "will not let the category be posted directly" do
      patch :update, params: {
        id: application.id,
        event_application: { business_category: "digital" }
      }

      expect(application.reload.business_category).to be_nil
    end

    it "refuses a service that is not in the catalog" do
      expect {
        choose!(service_type: "crypto_arbitrage")
      }.to raise_error(ActiveRecord::RecordInvalid, /isn't a service Fuime offers yet/)

      expect(application.reload.service_type).to be_nil
    end
  end

  describe "GET #project_info after picking a template" do
    it "offers the outline as a placeholder, never as the description" do
      application.update!(starting_point: "from_template", service_type: "pet_care")

      get :project_info, params: { id: application.id }

      body = CGI.unescapeHTML(response.body)
      # The prompt is offered as a placeholder…
      expect(body).to include("I walk dogs and look after pets for")
      # …with the checklist beside it…
      expect(body).to include("ask every owner for their vet's number".titleize) |
                      include("Ask every owner for their vet's number")
      # …and the record still holds the operator's own words, which is none yet.
      expect(application.reload.description).to be_blank
    end

    it "shows no outline to somebody who did not ask for one" do
      application.update!(starting_point: "have_business", service_type: "pet_care")

      get :project_info, params: { id: application.id }

      # Asserted on the checklist itself rather than on the word "outline",
      # which appears elsewhere in the layout.
      expect(CGI.unescapeHTML(response.body)).not_to include("Ask every owner for their vet's number")
    end
  end
end
