# frozen_string_literal: true

require "rails_helper"
require "webauthn/fake_client"

RSpec.describe LoginsController do
  include SessionSupport
  include WebAuthnSupport
  render_views

  describe "#new" do
    it "shows the current user when logged in" do
      user = create(:user)
      create_session(user, verified: true)

      get(:new)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(
        "You're currently signed into Fuime, would you like to head to your dashboard?"
      )
    end

    it "renders a login form when logged out" do
      get(:new)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Sign in to Fuime")
      expect(response.body).not_to include("Start your business on Fuime")
    end

    # Fuime: the marketing site's primary CTA lands here with ?signup=true, so
    # the page has to read like signing up, and its one promise about parents
    # has to be true for the money model that is on
    # (docs/fuime/ONBOARDING_PLAN.md §4.1 screen 2).
    context "when arriving to sign up" do
      it "reads like sign-up and, under merchant-of-record, says a teen sells once Fuime approves, before a guardian signs" do
        allow(Fuime::Features).to receive(:merchant_of_record?).and_return(true)

        get(:new, params: { signup: "true" })
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("Start your business on Fuime")
        expect(response.body).not_to include("Sign up for Fuime")
        # Vetting is human and comes before any sale (Fuime::OperatorEligibility),
        # so the page may not say "start selling now".
        expect(response.body).not_to include("start selling now")
        expect(response.body).to include("sell as soon as Fuime approves your business")
        expect(response.body).to include("a parent or guardian signs off before you get paid")
        # The sign-in variant is still one click away.
        expect(response.body).to include(">Sign in<")
      end

      it "does not promise selling before the venture is live when merchant-of-record is off" do
        allow(Fuime::Features).to receive(:merchant_of_record?).and_return(false)

        get(:new, params: { signup: "true" })
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("Start your business on Fuime")
        expect(response.body).not_to include("start selling now")
        expect(response.body).not_to include("sell as soon as Fuime approves your business")
        expect(response.body).to include("a parent or guardian signs off before your venture goes live")
      end
    end
  end

  describe "#create" do
    it "creates a user if one doesn't and uses the login code factor" do
      email = "test@example.com"
      expect(User.find_by(email:)).to be_nil

      expect { post(:create, params: { email: "test@example.com", login: { purpose: "" } }) }
        .to( change { Login.count }.by(1).and(change { User.count }.by(1)) )

      login = Login.last
      expect(login.user.email).to eq(email)
      expect(login).not_to be_reauthentication
      expect(response).to redirect_to(email_login_path(login))
    end

    it "uses the existing user if the email matches" do
      user = create(:user, email: "test@example.com")

      expect { post(:create, params: { email: user.email, login: { purpose: "" } }) }
        .to(change { Login.count }.by(1).and(change { User.count }.by(0)))

      login = Login.last
      expect(login.user).to eq(user)
      expect(response).to redirect_to(email_login_path(login))
    end
  end

  describe "#login_code" do
    it "sends a code to the user's email and renders the form" do
      user = create(:user, email: "text@example.com")
      login = create(:login, user:)

      expect {
        get(:email, params: { id: login.hashid })
      }.to send_email(to: user.email)

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("Email code")
      expect(response.body).to include("We just sent a login code")
    end

    it "sends an SMS code if the user has opted-in and verified their phone number" do
      user = create(:user, phone_number: "+18556254225")
      # This can't be done through the factory because we have validation logic
      # that clears out `phone_number_verified` when the phone number changes.
      user.update!(use_sms_auth: true, phone_number_verified: true)
      login = create(:login, user:)

      # Stub out the SMS service
      verification_service = instance_double(TwilioVerificationService)
      expect(verification_service).to receive(:send_verification_request).with(user.phone_number)
      expect(TwilioVerificationService).to receive(:new).and_return(verification_service)

      get(:sms, params: { id: login.hashid })

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("SMS code")
      expect(response.body).to include("We just sent a login code")
    end

    it "returns an error if the login is a reauthentication" do
      user = create(:user, email: "text@example.com")
      login = create(:login, user:, is_reauthentication: true)

      get(:email, params: { id: login.hashid })

      expect(flash[:error]).to eq("Please start again.")
      expect(response).to redirect_to(auth_users_path)
    end
  end

  describe "#complete" do
    context "webauthn" do
      it "signs the user in and redirects" do
        user = create(:user, phone_number: "+18556254225")
        login = create(:login, user:)
        webauthn_credential = create_webauthn_credential(user:)

        webauthn_challenge = generate_webauthn_challenge(user:)
        session[:webauthn_challenge] = webauthn_challenge

        credential = get_webauthn_credential(challenge: webauthn_challenge)

        expect {
          post(
            :complete,
            params: {
              id: login.hashid,
              method: "webauthn",
              credential: JSON.dump(credential)
            }
          )
        }.to change { webauthn_credential.reload.sign_count }.by(1)

        expect(response).to redirect_to(root_path)

        login.reload
        expect(login).to be_complete
        expect(login.authenticated_with_webauthn).to eq(true)
        expect(login.user_session).to be_present
        expect(current_session!).to eq(login.user_session)
      end
    end

    context "login_code" do
      context "email" do
        it "rejects invalid login codes" do
          user = create(:user)
          login = create(:login, user:)

          post(
            :complete,
            params: {
              id: login.hashid,
              method: "email",
              login_code: "123-456"
            }
          )

          expect(response).to have_http_status(:unprocessable_content)
          expect(response.body).to include("Invalid login code")
        end

        it "signs the user in and redirects" do
          user = create( :user, phone_number: "+18556254225" )
          login = create(:login, user:)
          login_code = create(:login_code, user:)

          post(
            :complete,
            params: {
              id: login.hashid,
              method: "email",
              login_code: login_code.code
            }
          )

          expect(response).to redirect_to(root_path)

          login.reload
          expect(login).to be_complete
          expect(login.authenticated_with_email).to eq(true)
          expect(login.user_session).to be_present
          expect(current_session!).to eq(login.user_session)

          login_code.reload
          expect(login_code).not_to be_active
        end
      end

      context "sms" do
        it "rejects invalid sms codes" do
          user = create(:user, phone_number: "+18556254225")
          login = create(:login, user:)

          # Stub out the SMS service
          verification_service = instance_double(TwilioVerificationService)
          expect(verification_service).to(
            receive(:check_verification_token)
              .with(user.phone_number, "123456")
              .and_return(false)
          )
          expect(TwilioVerificationService).to receive(:new).and_return(verification_service)

          post(
            :complete,
            params: {
              id: login.hashid,
              method: "sms",
              login_code: "123-456",
            }
          )

          expect(response).to have_http_status(:unprocessable_content)
          expect(response.body).to include("Invalid login code")
        end

        it "signs the user in and redirects" do
          user = create(:user, phone_number: "+18556254225")
          login = create(:login, user:)

          # Stub out the SMS service
          verification_service = instance_double(TwilioVerificationService)
          expect(verification_service).to(
            receive(:check_verification_token)
              .with(user.phone_number, "123456")
              .and_return(true)
          )
          expect(TwilioVerificationService).to receive(:new).and_return(verification_service)

          post(
            :complete,
            params: {
              id: login.hashid,
              method: "sms",
              login_code: "123-456",
            }
          )

          expect(response).to redirect_to(root_path)

          login.reload
          expect(login).to be_complete
          expect(login.authenticated_with_sms).to eq(true)
          expect(login.user_session).to be_present
          expect(current_session!).to eq(login.user_session)
        end
      end
    end

    context "totp" do
      it "rejects invalid totp codes" do
        user = create(:user)
        login = create(:login, user:)

        post(
          :complete,
          params: {
            id: login.hashid,
            method: "totp",
            code: "123456"
          }
        )

        expect(response).to redirect_to(totp_login_path(login))
        expect(flash[:error]).to include("Invalid TOTP code")
      end

      it "signs the user in and redirects" do
        freeze_time do
          user = create(:user, phone_number: "+18556254225")
          totp = user.create_totp!
          code = ROTP::TOTP.new(totp.secret, issuer: User::Totp::ISSUER).at(Time.now)
          login = create(:login, user:)

          post(
            :complete,
            params: {
              id: login.hashid,
              method: "totp",
              code:
            }
          )

          expect(response).to redirect_to(root_path)

          login.reload
          expect(login).to be_complete
          expect(login.authenticated_with_totp).to eq(true)
          expect(login.user_session).to be_present
          expect(current_session!).to eq(login.user_session)

          totp.reload
          expect(totp.last_used_at).to eq(Time.now)
        end
      end
    end

    context "backup_code" do
      it "rejects invalid backup codes" do
        user = create(:user)
        login = create(:login, user:)

        post(
          :complete,
          params: {
            id: login.hashid,
            method: "backup_code",
            code: "AAAAAAAA"
          }
        )

        expect(response).to redirect_to(backup_code_login_path(login))
        expect(flash[:error]).to include("Invalid backup code")
      end

      it "signs the user in and redirects to home" do
        freeze_time do
          user = create(:user, phone_number: "+18556254225")
          codes = user.generate_backup_codes!
          user.backup_codes.previewed.map(&:mark_active!)
          login = create(:login, user:)

          post(
            :complete,
            params: {
              id: login.hashid,
              method: "backup_code",
              backup_code: codes.first
            }
          )

          expect(response).to redirect_to(root_path)

          login.reload
          expect(login).to be_complete
          expect(login.authenticated_with_backup_code).to eq(true)
          expect(login.user_session).to be_present
          expect(current_session!).to eq(login.user_session)

          user.backup_codes.reload
          expect(user.backup_codes.used.first.updated_at).to eq(Time.now)
        end
      end

      it "signs the user in and redirects to security page if the user has no backup codes remaining" do
        freeze_time do
          user = create(:user, phone_number: "+18556254225")
          code = SecureRandom.alphanumeric(10)
          user.backup_codes.create!(code:)
          user.backup_codes.previewed.map(&:mark_active!)
          login = create(:login, user:)

          post(
            :complete,
            params: {
              id: login.hashid,
              method: "backup_code",
              backup_code: code
            }
          )

          expect(response).to redirect_to(security_user_path(user))

          login.reload
          expect(login).to be_complete
          expect(login.authenticated_with_backup_code).to eq(true)
          expect(login.user_session).to be_present
          expect(current_session!).to eq(login.user_session)

          user.backup_codes.reload
          expect(user.backup_codes.used.first.updated_at).to eq(Time.now)
        end
      end
    end

    context "2fa" do
      it "requests a second factor if 2fa is enabled" do
        user = create(:user,
                      phone_number: "+18556254225",
                      phone_number_verified: true,
                      use_sms_auth: true,
                      use_two_factor_authentication: true)
        totp = user.create_totp!
        login = create(:login, user:)
        login_code = create(:login_code, user:)

        post(
          :complete,
          params: {
            id: login.hashid,
            method: "email",
            login_code: login_code.code
          }
        )

        expect(response).to redirect_to(choose_login_preference_login_path(login))

        login.reload
        expect(login).not_to be_complete
        expect(login.authenticated_with_email).to be(true)

        code = ROTP::TOTP.new(totp.secret, issuer: User::Totp::ISSUER).at(Time.now)

        post(
          :complete,
          params: {
            id: login.hashid,
            method: "totp",
            code:
          }
        )

        expect(response).to redirect_to(root_path)

        login.reload
        expect(login).to be_complete
        expect(login.authenticated_with_totp).to eq(true)
        expect(login.user_session).to be_present
        expect(current_session!).to eq(login.user_session)
      end
    end

    it "redirects to the profile form if they don't have a name" do
      user = create(:user, full_name: nil, phone_number: nil)
      login = create(:login, user:)
      login_code = create(:login_code, user:)

      post(
        :complete,
        params: {
          id: login.hashid,
          method: "email",
          login_code: login_code.code
        }
      )

      expect(response).to redirect_to(edit_user_path(user.slug))
    end

    # Fuime A2: signup asks for a name and the 13+ confirmation only, so a name
    # is the whole test for "finished onboarding". Upstream also required a phone
    # number here, which would have bounced every phoneless user back to the
    # profile form on every login.
    it "sends a user with a name and no phone number to the product" do
      user = create(:user, full_name: "Maya Founder", phone_number: nil)
      login = create(:login, user:)
      login_code = create(:login_code, user:)

      post(
        :complete,
        params: {
          id: login.hashid,
          method: "email",
          login_code: login_code.code
        }
      )

      expect(response).to redirect_to(root_path)
    end

    it "redirects to the auth page with a flash message if the user's account is locked" do
      user = create(:user)
      user.lock!
      login = create(:login, user:)
      login_code = create(:login_code, user:)

      post(
        :complete,
        params: {
          id: login.hashid,
          method: "email",
          login_code: login_code.code
        }
      )

      expect(flash[:error]).to eq("Your Fuime account has been locked.")
      expect(response).to redirect_to(auth_users_path)
    end
  end

  describe "#reauthenticate" do
    it "checks for sudo mode and redirects" do
      user = create(:user)
      Flipper.enable(:sudo_mode_2015_07_21, user)
      create_session(user, verified: true)

      travel(3.hours)

      post(:reauthenticate, params: { return_to: "/test" })

      expect(response).to have_http_status(:unauthorized)
      expect(response.body).to include("Confirm Access")

      post(
        :reauthenticate,
        params: {
          return_to: "/test",
          _sudo: {
            submit_method: "email",
            login_code: user.login_codes.last.code,
            login_id: user.logins.last.hashid,
          }
        }
      )

      expect(response).to redirect_to("/test")
    end

    it "requires an active session" do
      post(:reauthenticate, params: { return_to: "/test" })

      expect(response).to redirect_to(auth_users_path(require_reload: true, return_to: reauthenticate_logins_url))
    end
  end
end
