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

    # What the guardian's signature gates depends on the money model, so the
    # sentence branches. Under merchant-of-record a vetted teen sells before a
    # guardian signs and the guardian is required before any payout
    # (Event#payout_setup_blockers); "before you can run a business" would be
    # false there. Under Connect the venture cannot go live without one.
    context "when merchant-of-record is on" do
      before { allow(Fuime::Features).to receive(:merchant_of_record?).and_return(true) }

      it "says the guardian agreement comes before getting paid, not before running a business" do
        get :edit, params: { id: user.id }

        expect(response.body).to include("By continuing you agree to")
        expect(response.body).to include(guardian_agreement_path)
        expect(response.body).to include("before you can get paid")
        expect(response.body).not_to include("before you can run a business")
      end
    end

    context "when merchant-of-record is off" do
      before { allow(Fuime::Features).to receive(:merchant_of_record?).and_return(false) }

      it "says the guardian agreement comes before running a business" do
        get :edit, params: { id: user.id }

        expect(response.body).to include("By continuing you agree to")
        expect(response.body).to include(guardian_agreement_path)
        expect(response.body).to include("before you can run a business")
        expect(response.body).not_to include("before you can get paid")
      end
    end

    # ONBOARDING_PLAN A2: the form asks for a name and the 13+ confirmation and
    # nothing else. Phone and profile picture live on the settings branch, which
    # a user with a name gets instead of this one.
    #
    # `:unknown_age` because the factory's default user carries a birthday, which
    # the view rightly treats as an already-answered age question and so renders
    # "You've confirmed..." in place of the checkbox. A real signup has neither.
    it "asks only for a name and the 13+ confirmation" do
      user = create(:user, :unknown_age, full_name: nil)
      create_session(user, verified: true)

      get :edit, params: { id: user.id }

      expect(response.body).to include("What should we call you?")
      expect(response.body).to include("user[full_name]")
      expect(response.body).to include("user[preferred_name]")
      expect(response.body).to include("user[age_attestation_confirmed]")
      expect(response.body).to include("Under 18, a parent or guardian joins")
      expect(response.body).to include("Let's go")

      expect(response.body).not_to include("user[phone_number]")
      expect(response.body).not_to include('id="phone_raw"')
      expect(response.body).not_to include("intlTelInput")
      expect(response.body).not_to include("phone_input")
      expect(response.body).not_to include("user[profile_picture]")
    end

    # Rule 2: the fields left the signup form, not the product.
    it "still offers phone and profile picture on the settings branch" do
      user.update!(full_name: "Maya Founder")

      get :edit, params: { id: user.id }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("user[phone_number]")
      expect(response.body).to include('id="phone_raw"')
      expect(response.body).to include("user[profile_picture]")
    end

    # A user who signed up without a phone number (every A2 signup) must still
    # be able to save every other setting. The field stays, but nothing
    # client-side may demand it — a `required` on #phone_raw browser-blocked the
    # whole form. The model already allows a blank phone number.
    it "does not require a phone number to save settings" do
      user.update!(full_name: "Maya Founder")

      get :edit, params: { id: user.id }

      phone_raw = response.body[/<input[^>]*id="phone_raw"[^>]*>/]
      expect(phone_raw).to be_present
      expect(phone_raw).not_to include("required")

      phone_hidden = response.body[/<input[^>]*id="phone_number"[^>]*>/]
      expect(phone_hidden).to be_present
      expect(phone_hidden).not_to include("required")
    end
  end
end
