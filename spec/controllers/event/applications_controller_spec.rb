# frozen_string_literal: true

require "rails_helper"

# Fuime: pins the approval flow against a crash that reached a real user.
#
# `admin_approve` unconditionally did `@application.contract.party :hcb` for any
# teen-led application. Fuime has no DocuSeal template configured
# (`Event::Plan#contract_docuseal_template_id` is unset), so `send_contract`
# returns nil and teen-led applications have no contract at all — the call
# raised NoMethodError *after* the state transition and mailer had already run,
# producing a 500 page carrying a green "Application approved." flash.
#
# See docs/fuime/DOCUSEAL_SETUP.md for turning the signing step back on.
RSpec.describe Event::ApplicationsController, type: :controller do
  include SessionSupport

  let(:admin) { create(:user, :make_admin) }

  before { create_session(admin, verified: true) }

  describe "POST #admin_approve" do
    context "for a teen-led application with no contract (no DocuSeal template)" do
      let(:application) do
        create(:event_application, teen_led: true).tap do |app|
          app.update!(aasm_state: :under_review)
        end
      end

      it "does not raise, and approves the application" do
        expect(Event::Plan::Standard.new.contract_available?).to be false
        expect(application.contract).to be_nil

        expect {
          post :admin_approve, params: { id: application.to_param }
        }.not_to raise_error

        expect(application.reload).to be_approved
      end

      it "redirects to the submission page rather than a nil contract party" do
        post :admin_approve, params: { id: application.to_param }

        expect(response).to redirect_to(submission_application_path(application))
        expect(flash[:success]).to eq("Application approved.")
      end
    end
  end

  # The second half of the same outage: approval succeeded, but the business was
  # never created. `activate_event!` dereferenced the contract in three places,
  # and the only Activate button in the UI lived on the contract-party page —
  # which does not exist when no agreement is configured.
  describe "POST #admin_activate with no contract" do
    let(:application) do
      create(:event_application, teen_led: true, description: "Prints and stickers").tap do |app|
        app.update!(
          aasm_state: :approved,
          address_line1: "1 Main St",
          address_city: "SF",
          address_country: "US",
          address_postal_code: "94103"
        )
      end
    end

    it "creates the business" do
      expect(application.contract).to be_nil

      expect {
        post :admin_activate, params: { id: application.to_param, risk_level: "zero" }
      }.to change { Event.count }.by(1)

      expect(application.reload.event).to be_present
      expect(application.event.name).to eq(application.name)
    end

    it "redirects to the new business rather than erroring" do
      post :admin_activate, params: { id: application.to_param, risk_level: "zero" }

      expect(response).to redirect_to(event_path(application.reload.event))
    end
  end

  describe "Event::Application#next_step" do
    # The application card renders `next_step`, falling back to "We're reviewing
    # your application" when it returns nil. Approved-but-not-yet-activated hit
    # that fallback, so the card contradicted the "Approved" badge beside it.
    it "returns approval-appropriate copy once approved but not activated" do
      application = create(:event_application, teen_led: true)
      application.update!(
        aasm_state: :approved,
        description: "Prints and stickers",
        address_line1: "1 Main St",
        address_city: "SF",
        address_country: "US",
        address_postal_code: "94103"
      )

      expect(application.event).to be_nil
      expect(application.next_step).to be_present
      expect(application.next_step).not_to eq("We're reviewing your application")
    end
  end

end
