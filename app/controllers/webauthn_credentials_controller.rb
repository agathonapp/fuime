# frozen_string_literal: true

class WebauthnCredentialsController < ApplicationController
  # NOTE: this controller has no `auth_options` action — it lives on
  # UsersController as `webauthn_options` (GET /users/webauthn/auth_options).
  # Two `skip_*_action ... only: [:auth_options]` callbacks used to sit here
  # naming it. Rails 7.1 raises `AbstractController::ActionNotFound` for a
  # callback listing an action the controller doesn't define, so EVERY request
  # here raised before reaching an action, and no one could register a security
  # key. All three actions below require a signed-in user and authorize, so
  # there was nothing for the skips to do in the first place.

  def register_options
    user = User.friendly.find(params[:user_id])

    authorize user, :manage_webauthn_credentials?

    if !user.webauthn_id
      user.update!(webauthn_id: WebAuthn.generate_user_id)
    end

    options = WebAuthn::Credential.options_for_create(
      user: { id: user.webauthn_id, name: user.email, display_name: user.name },
      authenticator_selection: { authenticator_attachment: params[:type], user_verification: "discouraged" }
    )

    session[:webauthn_challenge] = options.challenge

    render json: options
  end

  def create
    user = User.friendly.find(params[:user_id])

    authorize user, :manage_webauthn_credentials?

    webauthn_credential = WebAuthn::Credential.from_create(JSON.parse(params[:credential]))

    begin
      webauthn_credential.verify(session[:webauthn_challenge])

      user.webauthn_credentials.create!(
        webauthn_id: webauthn_credential.id,
        public_key: webauthn_credential.public_key,
        sign_count: webauthn_credential.sign_count,
        name: params[:name].presence || "#{browser.name} on #{browser.platform.name}",
        authenticator_type: authenticator_type_param
      )

      redirect_back fallback_location: edit_user_path(user), flash: { success: "Registered security key!" }
    rescue WebAuthn::Error => e
      Rails.error.report e
      redirect_back fallback_location: edit_user_path(user), flash: { error: "Something went wrong registering a security key." }
    end
  end

  def destroy
    credential = WebauthnCredential.find(params[:id])

    authorize credential

    credential.destroy

    redirect_back fallback_location: edit_user_path(params[:user_id]), flash: { success: "Deleted security key." }
  end

  private

  # `params[:type]` arrives in one of two spellings for the same thing. The form
  # radio posts `cross_platform` (the enum value), but the Stimulus controller
  # overwrites it with `cross-platform` — the hyphenated spelling the WebAuthn
  # API itself requires for `authenticator_attachment`. Passing the hyphenated
  # form straight to the enum raised `'cross-platform' is not a valid
  # authenticator_type`, so registering any roaming key (a YubiKey, a phone)
  # failed while platform keys happened to work.
  def authenticator_type_param
    normalized = params[:type].to_s.tr("-", "_")
    return nil unless WebauthnCredential.authenticator_types.key?(normalized)

    normalized
  end

end
