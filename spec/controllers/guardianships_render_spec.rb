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
      # The "it is not an identity check" footnote stays: Fuime verifies nobody.
      expect(response.body).to include("not an identity check")
    end

    # Under merchant-of-record the guardian requirement sits at the payout seam
    # (Event#payout_setup_blockers): a teen can keep setting up first. The page
    # used to promise "your venture will be fully activated" — a gate that is
    # not there under MoR (L8). It must not swing to "you can start selling now"
    # either: selling waits on Fuime's vetting (Fuime::OperatorEligibility),
    # not on the parent, and this page is usually reached before that decision.
    it "tells the teen they can keep setting up and the parent signs before pay, under merchant-of-record", :merchant_of_record do
      get :new

      expect(response.body).to include("You can keep setting up.")
      expect(response.body).to include("signs before you get paid")
      expect(response.body).to include("Until they accept, you can't be paid.")
      expect(response.body).not_to include("start selling")
      expect(response.body).not_to include("you can sell")
      expect(response.body).not_to include("fully activated")
      expect(response.body).not_to include("Almost there")
    end

    it "keeps an activation framing under Connect" do
      get :new

      expect(response.body).to include("can't go live until they sign")
      expect(response.body).not_to include("keep setting up")
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
      expect(response.body).to include('name="agree"')
      expect(response.body).to include('type="checkbox"')
      expect(response.body).to include('id="guardian-accept-form"')
      # "I agree", not "Agree & activate their account": under merchant-of-record
      # accepting unblocks payouts, not activation.
      expect(response.body).to include('value="I agree"')
      expect(response.body).not_to include("activate their account")
      expect(response.body).to include("needs a parent to sign off")
      expect(response.body).to include("This is not an identity check.")
      # The "important notifications" and "tax time summary" bullets described
      # mailers that do not exist (ONBOARDING_PLAN §2 #8).
      expect(response.body).not_to include("important notifications")
      expect(response.body).not_to match(/tax time/i)
    end

    it "names the venture in the heading when the teen has one" do
      create(:event_application, user: teen, teen_led: true, name: "Sunset Cookies")
      create_session(guardian, verified: true)

      get :show, params: { id: guardianship.invite_token }

      expect(response.body).to include("needs a parent to sign off on Sunset Cookies")
    end

    # Not "you approve every payout": under MoR payouts run as a weekly
    # Fuime::PayoutBatch a Fuime admin approves, and a scheduled line has no teen
    # request for the guardian to decide. What the guardian gates is whether money
    # can go out at all (Event#payout_setup_blockers) and where it goes
    # (EventPolicy#setup_payments? is guardian-only on a family venture).
    it "says nothing is paid out until they have accepted and set up the destination, under merchant-of-record", :merchant_of_record do
      create_session(guardian, verified: true)

      get :show, params: { id: guardianship.invite_token }

      expect(response.body).to include("Nothing is paid out until you've accepted and set up where the money goes.")
      expect(response.body).to include("Money only ever goes to a destination a parent or guardian set up.")
      expect(response.body).not_to include("approve every payout")
      expect(response.body).not_to include("until you say so")
      expect(response.body).not_to include("Nothing goes live until you accept")
    end

    it "says nothing goes live until they accept under Connect" do
      create_session(guardian, verified: true)

      get :show, params: { id: guardianship.invite_token }

      expect(response.body).to include("Nothing goes live until you accept.")
      expect(response.body).not_to include("approve every payout")
    end

    # The standing "not a bank" disclosure lives in the footer, which this
    # controller used to hide on the one page a new adult reads before signing.
    # The request-level assertion is in spec/requests/fuime/status_disclosure_spec.rb;
    # this pins the controller side of it.
    it "renders the footer disclosure on the accept page" do
      create_session(guardian, verified: true)

      get :show, params: { id: guardianship.invite_token }

      expect(response.body).to include("not a bank")
      expect(response.body).to include("does not offer FDIC-insured products")
    end

    # Production path: the invite creates a stub user; after login they have at
    # most a 13+ settings tick. #activation_blockers still lists the 18+ sentence
    # (accept! stays fail-closed), but that sentence used to hide the checkbox
    # that is the only way to clear it.
    it "shows the agreement checkbox to a parent who has not yet attested 18+" do
      stub_parent = create(:user, :unknown_age)
      pending_invite = create(:guardianship, minor: teen, guardian: stub_parent)
      create_session(stub_parent, verified: true)

      get :show, params: { id: pending_invite.invite_token }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('id="agree"')
      expect(response.body).to include('name="agree"')
      expect(response.body).to include('type="checkbox"')
      expect(response.body).to include('id="guardian-accept-submit"')
      expect(response.body).to include("I am 18 or older")
      expect(response.body).not_to include("Update my details")
    end

    it "shows the agreement checkbox after the parent ticked 13+ on settings" do
      settings_parent = create(:user, :attested_teen)
      pending_invite = create(:guardianship, minor: teen, guardian: settings_parent)
      create_session(settings_parent, verified: true)

      get :show, params: { id: pending_invite.invite_token }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('id="agree"')
      expect(response.body).to include('type="checkbox"')
      expect(response.body).to include('value="I agree"')
    end

    it "sends a signed-out visitor to log in rather than erroring" do
      get :show, params: { id: guardianship.invite_token }

      expect(response).to redirect_to(
        auth_users_path(return_to: guardianship_path(guardianship.invite_token))
      )
    end

    # Signed in as somebody else — a shared laptop, or the teen opening the link
    # they were about to text. Before: a flash and a bounce to the dashboard with
    # no way out (ONBOARDING_PLAN §2 #10). Now: a page with the one action that
    # helps, and still only the redacted address.
    it "shows a wrong signed-in user a sign-out, without leaking the guardian's email" do
      intruder = create(:user, birthday: 40.years.ago.to_date)
      create_session(intruder, verified: true)

      get :show, params: { id: guardianship.invite_token }

      expect(response).to have_http_status(:forbidden)
      expect(response.body).to include("This invitation was sent to")
      expect(response.body).to include(guardian.redacted_email)
      expect(response.body).not_to include(guardian.email)
      expect(response.body).to include("Sign out and open the link again")
      expect(response.body).to include(logout_users_path)
      # Nothing about the family reaches the wrong account.
      expect(response.body).not_to include(ERB::Util.html_escape(teen.name).to_s)
      expect(response.body).not_to include('id="guardian-accept-form"')
    end
  end

  # ONBOARDING_PLAN §2 #9: an expired link used to be "Invalid or expired
  # invitation link." and a bounce to a dashboard the parent cannot sign in to.
  describe "GET #show with an expired token" do
    let(:expired) { create(:guardianship, :expired_invite, minor: teen, guardian:) }

    it "offers a fresh link to a signed-out visitor, naming only the redacted address" do
      get :show, params: { id: expired.invite_token }

      expect(response).to have_http_status(:gone)
      expect(response.body).to include("This link has expired. We can send a fresh one to")
      expect(response.body).to include(guardian.redacted_email)
      expect(response.body).not_to include(guardian.email)
      expect(response.body).to include(renew_guardianship_path(expired.invite_token))
      expect(response.body).not_to include('id="guardian-accept-form"')
      # The window is rendered from Guardianship::INVITE_VALID_FOR via
      # ActiveSupport::Duration#inspect, which is "7 days" and not "604800".
      expect(response.body).to include("stop working after 7 days")
      # The disclosure renders here too — no session, and the layout's
      # signed-out branch carries the footer.
      expect(response.body).to include("not a bank")
    end

    it "offers a fresh link to the signed-in guardian as well" do
      create_session(guardian, verified: true)

      get :show, params: { id: expired.invite_token }

      expect(response).to have_http_status(:gone)
      expect(response.body).to include("This link has expired")
    end

    it "answers a stale accept POST with the same page, without activating" do
      create_session(guardian, verified: true)

      post :accept, params: { id: expired.invite_token, agree: "1" }

      expect(response).to have_http_status(:gone)
      expect(expired.reload).to be_pending
    end

    # Accepted and revoked rows clear their token, so the old link never matches
    # a row and keeps the one generic message — the lookup is not an oracle for
    # anything but "this pending link aged out".
    it "keeps the generic message for an accepted token" do
      guardianship = create(:guardianship, minor: teen, guardian:)
      token = guardianship.invite_token
      guardianship.accept!

      get :show, params: { id: token }

      expect(response).to redirect_to(root_path)
      expect(flash[:error]).to eq("Invalid or expired invitation link.")
    end

    it "keeps the generic message for a revoked token" do
      guardianship = create(:guardianship, minor: teen, guardian:)
      token = guardianship.invite_token
      guardianship.revoke!(revoked_by: guardian)

      get :show, params: { id: token }

      expect(response).to redirect_to(root_path)
      expect(flash[:error]).to eq("Invalid or expired invitation link.")
    end

    it "keeps the generic message for an unknown token" do
      get :show, params: { id: "nope" }

      expect(response).to redirect_to(root_path)
      expect(flash[:error]).to eq("Invalid or expired invitation link.")
    end
  end

  describe "POST #renew (the parent re-mints an expired link)" do
    let(:expired) { create(:guardianship, :expired_invite, minor: teen, guardian:) }

    it "mints a new token, resets the reminders and mails once, with no session" do
      expired.update!(invite_day3_reminded_at: 3.days.ago, invite_day6_reminded_at: 1.day.ago)
      old_token = expired.invite_token

      expect {
        post :renew, params: { id: old_token }
      }.to have_enqueued_mail(GuardianshipMailer, :invite).once

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("A fresh link is on its way to")
      expect(response.body).to include(guardian.redacted_email)
      expect(response.body).not_to include(guardian.email)
      expect(response.body).to include("The new link is good for 7 days.")

      expired.reload
      expect(expired).to be_pending
      expect(expired.invite_token).not_to eq(old_token)
      expect(expired).not_to be_invite_expired
      expect(expired.invite_day3_reminded_at).to be_nil
      expect(expired.invite_day6_reminded_at).to be_nil
      expect(Guardianship.find_by_token(expired.invite_token)).to eq(expired)
      # The link that reached the expired page is dead — rotating the token is
      # the rate limit.
      expect(Guardianship.find_by(invite_token: old_token)).to be_nil
    end

    it "refuses to send again within the cooldown" do
      fresh = create(:guardianship, minor: teen, guardian:)
      token = fresh.invite_token

      expect {
        post :renew, params: { id: token }
      }.not_to have_enqueued_mail(GuardianshipMailer, :invite)

      expect(response).to redirect_to(root_path)
      expect(flash[:info]).to include("We sent a new link a few minutes ago")
      expect(fresh.reload.invite_token).to eq(token)
    end

    it "sends again once the cooldown has passed, even for a live link" do
      live = create(:guardianship, minor: teen, guardian:)
      live.update!(invite_sent_at: (GuardianshipsController::RENEW_COOLDOWN + 1.minute).ago)
      token = live.invite_token

      expect {
        post :renew, params: { id: token }
      }.to have_enqueued_mail(GuardianshipMailer, :invite).once

      expect(response).to have_http_status(:ok)
      expect(live.reload.invite_token).not_to eq(token)
    end

    it "keeps the generic message for accepted, revoked and unknown tokens" do
      accepted = create(:guardianship, minor: teen, guardian:)
      accepted_token = accepted.invite_token
      accepted.accept!

      other_teen = create(:user, :minor)
      revoked = create(:guardianship, minor: other_teen, guardian:)
      revoked_token = revoked.invite_token
      revoked.revoke!(revoked_by: guardian)

      [accepted_token, revoked_token, "nope"].each do |token|
        expect {
          post :renew, params: { id: token }
        }.not_to have_enqueued_mail(GuardianshipMailer, :invite)

        expect(response).to redirect_to(root_path)
        expect(flash[:error]).to eq("Invalid or expired invitation link.")
      end
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

    it "activates when an invited stub parent ticks the 18+ box" do
      stub_parent = create(:user, :unknown_age)
      pending_invite = create(:guardianship, minor: teen, guardian: stub_parent)
      create_session(stub_parent, verified: true)

      post :accept, params: { id: pending_invite.invite_token, agree: "1" }

      expect(pending_invite.reload).to be_active
      expect(stub_parent.reload.known_adult?).to be true
    end
  end

  # What withdrawing consent stops differs by money model (L8). Under
  # merchant-of-record User#permitted_to_operate_business? is unconditionally
  # true, so the venture keeps existing and the withdrawal re-arms the guardian
  # blocker in Event#payout_setup_blockers. The old flash — "can no longer
  # operate a business" — described the Connect world only.
  describe "POST #revoke (the parent withdraws consent)" do
    let(:teen) { create(:user, :minor, full_name: "Maya Family") }
    let(:guardianship) { create(:guardianship, :active, minor: teen, guardian:) }

    before { create_session(guardian, verified: true) }

    it "says no money will be paid out until an adult is back, under merchant-of-record", :merchant_of_record do
      post :revoke, params: { id: guardianship.id }

      expect(guardianship.reload).to be_revoked
      expect(flash[:success]).to eq(
        "Guardianship revoked. No money will be paid out of Maya Family's business until a parent or guardian is on the account again."
      )
      expect(flash[:success]).not_to include("no longer operate")
    end

    it "says the minor can no longer operate a business, under Connect" do
      post :revoke, params: { id: guardianship.id }

      expect(guardianship.reload).to be_revoked
      expect(flash[:success]).to eq("Guardianship revoked. Maya Family can no longer operate a business on Fuime.")
    end
  end

  # The confirm dialog on the agreement record carries the same split.
  describe "GET #record (the withdraw-consent confirmation copy)" do
    let(:teen) { create(:user, :minor, full_name: "Maya Family") }
    let(:guardianship) { create(:guardianship, :active, minor: teen, guardian:) }

    before { create_session(guardian, verified: true) }

    it "warns about payouts, not operating, under merchant-of-record", :merchant_of_record do
      get :record, params: { id: guardianship.id }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("No money will be paid out of their business until a parent or guardian is on the account again.")
      expect(response.body).not_to include("lose the ability to operate")
    end

    it "warns about operating under Connect" do
      get :record, params: { id: guardianship.id }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("will immediately lose the ability to operate a business on Fuime.")
      expect(response.body).not_to include("No money will be paid out")
    end
  end

end
