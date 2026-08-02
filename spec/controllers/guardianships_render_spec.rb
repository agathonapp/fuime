# frozen_string_literal: true

require "rails_helper"

# Fuime: the guardian invite and accept screens actually RENDER.
#
# The guardianship rules are well covered by model and policy specs, but no
# spec rendered these two views. They are the product thesis on screen — a
# parent follows an emailed link and signs — and a template error in either is
# invisible to a status-code-only spec.
RSpec.describe GuardianshipsController, type: :controller do
  render_views
  include SessionSupport

  let(:teen) { create(:user, :minor) }
  let(:guardian) { create(:user, birthday: 40.years.ago.to_date) }

  describe "GET #new (teen invites their parent)" do
    before { create_session(teen, verified: true) }

    it "renders the invite form" do
      get :new

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("form")
    end
  end

  describe "GET #show (parent opens the emailed link)" do
    let(:guardianship) { create(:guardianship, minor: teen, guardian:) }

    it "renders the accept page for the invited guardian" do
      create_session(guardian, verified: true)

      get :show, params: { id: guardianship.invite_token }

      expect(response).to have_http_status(:ok)
      # The agreement they are consenting to must be on the page they sign.
      expect(response.body).to match(/agree/i)
    end

    it "sends a signed-out visitor to log in rather than erroring" do
      get :show, params: { id: guardianship.invite_token }

      expect(response).to redirect_to(
        auth_users_path(return_to: guardianship_path(guardianship.invite_token))
      )
    end

    it "does not leak the guardian's email to a wrong signed-in user" do
      intruder = create(:user, birthday: 40.years.ago.to_date)
      create_session(intruder, verified: true)

      get :show, params: { id: guardianship.invite_token }

      expect(response).to redirect_to(root_path)
      expect(flash[:error]).to include(guardian.redacted_email)
      expect(flash[:error]).not_to include(guardian.email)
    end
  end

  describe "POST #accept" do
    let(:guardianship) { create(:guardianship, minor: teen, guardian:) }

    before { create_session(guardian, verified: true) }

    # Consent is the entire legal product of this action.
    it "refuses to activate without the agreement checkbox" do
      post :accept, params: { id: guardianship.invite_token }

      expect(guardianship.reload).not_to be_active
      expect(flash[:error]).to be_present
    end

    it "activates the guardianship when the guardian agrees" do
      post :accept, params: { id: guardianship.invite_token, agree: "1" }

      expect(guardianship.reload).to be_active
      expect(guardianship.agreement_signed_at).to be_present
    end
  end

end
