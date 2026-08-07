# frozen_string_literal: true

require "rails_helper"

# Fuime: registering a security key, exercised through the real controller.
#
# Reported symptom: an admin cannot register a security key. These specs walk
# the two requests the browser actually makes — GET register_options, then
# POST create with the signed credential — for an admin, a normal user, and an
# auditor acting on someone else's account.
RSpec.describe WebauthnCredentialsController, type: :controller do
  include SessionSupport
  include WebAuthnSupport

  let(:admin) { create(:user, :make_admin) }

  describe "GET #register_options" do
    it "returns creation options for an admin registering their own key" do
      create_session(admin, verified: true)

      get :register_options, params: { user_id: admin.slug, type: "cross-platform" }

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["challenge"]).to be_present
      expect(body.dig("user", "name")).to eq(admin.email)
      # The controller backfills webauthn_id on first use.
      expect(admin.reload.webauthn_id).to be_present
    end

    it "returns options for an ordinary user registering their own key" do
      user = create(:user)
      create_session(user, verified: true)

      get :register_options, params: { user_id: user.slug, type: "platform" }

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["challenge"]).to be_present
    end
  end

  describe "POST #create" do
    it "registers the key an admin just signed" do
      create_session(admin, verified: true)
      admin.update!(webauthn_id: WebAuthn.generate_user_id)

      options = WebAuthn::Credential.options_for_create(
        user: { id: admin.webauthn_id, name: admin.email, display_name: admin.name }
      )
      session[:webauthn_challenge] = options.challenge
      raw = webauthn_client.create(challenge: options.challenge)

      expect {
        post :create, params: {
          user_id: admin.slug, credential: raw.to_json, name: "Yubikey", type: "cross-platform"
        }
      }.to change { admin.webauthn_credentials.count }.by(1)

      expect(flash[:success]).to eq("Registered security key!")
    end
  end

  # UserPolicy#edit? is `user.auditor? || record == user`, so the authorize call
  # in this controller lets an auditor act on ANOTHER user's account. Registering
  # a security key onto someone else's login is an authentication change, not a
  # read — an auditor should not be able to do it.
  describe "an auditor acting on another user's account" do
    let(:auditor) { create(:user, :make_auditor) }
    let(:victim) { create(:user) }

    before { create_session(auditor, verified: true) }

    it "does not let an auditor mint registration options for someone else" do
      get :register_options, params: { user_id: victim.slug, type: "cross-platform" }

      expect(response).not_to have_http_status(:ok)
    end

    it "does not let an auditor register a key onto someone else's account" do
      victim.update!(webauthn_id: WebAuthn.generate_user_id)
      options = WebAuthn::Credential.options_for_create(
        user: { id: victim.webauthn_id, name: victim.email, display_name: victim.name }
      )
      session[:webauthn_challenge] = options.challenge
      raw = webauthn_client.create(challenge: options.challenge)

      expect {
        post :create, params: {
          user_id: victim.slug, credential: raw.to_json, name: "Attacker key", type: "cross-platform"
        }
      }.not_to(change { victim.webauthn_credentials.count })
    end
  end

end
