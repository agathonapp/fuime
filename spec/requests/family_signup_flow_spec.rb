# frozen_string_literal: true

require "rails_helper"

# Fuime: the whole family journey over real HTTP — the part the golden-path
# spec (spec/models/d2c_golden_path_spec.rb) deliberately skips by starting
# from create(:user). Nothing here reaches into a session or fabricates a
# record the UI wouldn't: the teen signs up with an email code, is parked at
# the guardian step by the real redirect, invites their parent through the real
# form, the parent signs up the same way, proves their age, and accepts through
# the same token link the email carries.
#
# This is the platform-readiness canary for "can a parent and teen actually
# sign up and activate?": if any step 302s somewhere unexpected, renders the
# wrong page, or silently no-ops, this fails with the actual response.
RSpec.describe "a family signs up and activates", type: :request do
  # The full production login dance: request a code, read it from the database
  # exactly as letter_opener users read it from the email, and complete.
  def login_as!(email)
    # `email` rides at the top level; the controller separately requires a
    # nested `login:` hash (return_to/purpose/referral), which the real form
    # always posts even when empty.
    post logins_path, params: { email:, login: { purpose: "" } }
    login = Login.order(:id).last
    expect(login).to be_present,
                     "POST /logins created no Login: status=#{response.status} flash=#{flash.to_hash.inspect}"
    expect(login.user.email).to eq(email)

    post email_login_path(login)
    code = LoginCode.active.where(user: login.user).order(:id).last
    expect(code).to be_present, "no login code was issued for #{email}"

    post complete_login_path(login), params: { method: "email", login_code: code.code }
    expect(User::Session.where(user: login.user)).to exist, "login did not produce a session"
    login.user
  end

  def logout!
    delete logout_users_path
  end

  it "walks teen signup -> guardian invite -> parent accept -> operating rights" do
    # ── The teen ──────────────────────────────────────────────────────────
    teen = login_as!("maya-family@example.com")

    # Deferred onboarding: confirming they're old enough no longer walls them
    # behind the guardian invite — they land in the product with a heads-up, and
    # the hard requirement waits at activation.
    #
    # `age_attestation_confirmed` and not `birthday`: signup asks for a checkbox
    # rather than a date (AddAgeAttestationToUsers). Posting a birthday here would
    # now be silently dropped — `:birthday` is not a permitted parameter — and the
    # onboarding validation would refuse with a 422, which is how this example
    # caught the change.
    patch user_path(teen), params: {
      user: { full_name: "Maya Family", age_attestation_confirmed: "1" }
    }
    expect(response).to redirect_to(root_path)
    expect(flash[:info]).to include("invite a parent or guardian when your business is ready")

    # The invite form, as the UI submits it.
    post guardianships_path, params: { guardianship: { guardian_email: "pat-family@example.com" } }
    guardianship = Guardianship.order(:id).last
    expect(guardianship.minor).to eq(teen.reload)
    expect(guardianship).to be_pending
    expect(guardianship.invite_token).to be_present

    # The teen can look, but not operate — and activation is where the
    # deferred guardian requirement actually bites: an admin cannot create the
    # venture while the applicant has no guardian.
    expect(teen.needs_guardian?).to be(true)
    premature = create(:event_application, user: teen.reload, teen_led: true, name: "Too Early LLC-less")
    premature.update!(aasm_state: :approved)
    early_admin = create(:user, :make_admin, birthday: 35.years.ago.to_date)
    expect {
      premature.activate_event!(risk_level: 0, point_of_contact: early_admin)
    }.to raise_error(ArgumentError, /minor with no active guardian/)

    logout!

    # ── The parent ────────────────────────────────────────────────────────
    # The invite created a stub user for this email; the parent signs in with
    # the same code flow the teen used.
    parent = login_as!("pat-family@example.com")

    # The parent completes their own profile with the same generic account gate
    # every user gets — "I'm 13 or older", because that is the platform minimum and
    # the settings form deliberately cannot offer anything stronger (a box a user
    # controls must never be able to make them an adult).
    #
    # They used to have to enter a DATE OF BIRTH here, because Guardianship's 18+
    # check was fail-closed on unknown age and a date was the only way to satisfy
    # it. That is gone: the acceptance checkbox below already reads "I confirm I am
    # the parent or legal guardian of X, that I am 18 or older", so ticking THAT is
    # the assertion, and #accept promotes the attestation. This is the one
    # legitimate minor_13_plus -> adult_18_plus transition, and this is the flow it
    # exists for.
    patch user_path(parent), params: {
      user: { full_name: "Pat Family", age_attestation_confirmed: "1" }
    }
    expect(parent.reload.known_adult?).to be(false)

    # The link from the invite email: token-addressed show, then accept.
    get guardianship_path(guardianship.invite_token)
    expect(response).to have_http_status(:ok)

    # The agreement checkbox is required server-side — skipping it is refused
    # with a flash, which an earlier run of this spec proved by omitting it. It now
    # also carries the 18+ claim, so this one request is what makes the parent a
    # known adult.
    post accept_guardianship_path(guardianship.invite_token), params: { agree: "1" }
    expect(parent.reload.known_adult?).to be(true)
    expect(guardianship.reload).to be_active,
                                   "accept did not activate: #{flash.to_hash.inspect}"

    # ── The unlock ────────────────────────────────────────────────────────
    expect(teen.reload.needs_guardian?).to be(false)

    # From here the model-level golden path takes over (application ->
    # activation -> venture); assert the seam between the two specs is real.
    application = create(:event_application, user: teen, teen_led: true, name: "Maya Family Studio")
    application.update!(aasm_state: :approved)
    admin = create(:user, :make_admin, birthday: 35.years.ago.to_date)
    application.activate_event!(risk_level: 0, point_of_contact: admin)

    venture = application.reload.event
    expect(venture.organizer_positions.find_by(user: teen)&.role).to eq("manager")
    expect(EventPolicy.new(teen, venture).send(:permitted_to_operate_business?)).to be(true)
    expect(EventPolicy.new(parent, venture).setup_payments?).to be(true)
  end
end
