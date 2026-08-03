# frozen_string_literal: true

require "rails_helper"

# Fuime: the onboarding form is the moment a person becomes a Fuime user, so it
# is where the terms have to appear — documents that are published but never put
# in front of anyone are not notice.
#
# This spec exists mostly because no other spec renders `users/edit`. A typo'd
# path helper there would 500 the signup page with a green suite behind it,
# which is the exact failure mode this codebase keeps rediscovering.
RSpec.describe UsersController, type: :controller do
  include SessionSupport
  render_views

  describe "GET #edit" do
    # `User#onboarding?` is `full_name_in_database.blank?`, and only the
    # onboarding branch of users/edit renders the notice. A fully-populated user
    # gets the settings branch, where this copy does not belong.
    let(:user) { create(:user, full_name: nil) }

    before { create_session(user, verified: true) }

    it "renders the onboarding form" do
      get :edit, params: { id: user.id }

      expect(response).to have_http_status(:ok)
    end

    it "states what continuing agrees to" do
      get :edit, params: { id: user.id }

      expect(response.body).to include("By continuing you agree to")
    end

    it "links the terms, the privacy policy, and the guardian agreement" do
      get :edit, params: { id: user.id }

      expect(response.body).to include(terms_path)
      expect(response.body).to include(privacy_path)
      expect(response.body).to include(guardian_agreement_path)
    end
  end
end
