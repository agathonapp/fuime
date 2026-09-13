# frozen_string_literal: true

require "rails_helper"

# Fuime: `GET /join/:token` — the link that lets a parent-first teen into the
# account their parent made for them.
#
# The link signs its holder in AS THE MINOR, so the interesting examples here
# are all about who must NOT be let through.
RSpec.describe "the family join link", type: :request do
  let(:parent) { create(:user, birthday: 40.years.ago.to_date, full_name: "Pat Join", verified: true) }
  let(:teen) do
    create(:user, :unknown_age, full_name: nil, preferred_name: "Maya",
                                email: "maya-join@example.com", creation_method: :family_invite)
  end
  let!(:guardianship) do
    create(:guardianship, guardian: parent, minor: teen).tap do |row|
      row.update!(status: :active, initiated_by: :guardian,
                  agreement_signed_at: Time.current,
                  agreement_version: Guardianship::CURRENT_AGREEMENT_VERSION)
    end
  end
  let(:token) { Fuime::FamilyInviteService.generate_token(user: teen) }

  it "signs the teen in and drops them at the start of their own setup" do
    expect {
      get family_invite_path(token)
    }.to change { User::Session.where(user: teen).count }.by(1)

    expect(response).to redirect_to(setup_path)
    expect(teen.reload).to be_verified

    follow_redirect!
    expect(response).to redirect_to(teen_setup_step_path(step: "you", return_to: nil))

    follow_redirect!
    expect(response).to have_http_status(:ok)
    # They see who signed for them, and they still answer the age question
    # themselves — nobody may attest on another person's behalf.
    expect(page_text).to include("Pat Join")
    expect(page_text).to include("I'm 13 or older")
  end

  it "refuses an expired token and names the way back" do
    expired = travel_to(8.days.ago) { Fuime::FamilyInviteService.generate_token(user: teen) }

    expect {
      get family_invite_path(expired)
    }.not_to(change { User::Session.count })

    expect(response).to redirect_to(auth_users_path(signup: true))
    expect(flash[:error]).to match(/expired/i)
    expect(flash[:error]).to match(/login code/i)
  end

  it "refuses a tampered token" do
    get family_invite_path("#{token}xyz")

    expect(response).to redirect_to(auth_users_path(signup: true))
    expect(User::Session.count).to eq(0)
  end

  # The shared-laptop case: the parent opens the link they just sent.
  it "refuses a signed-in stranger and reveals only the redacted address" do
    login_as!(parent.email)

    get family_invite_path(token)

    expect(response).to have_http_status(:forbidden)
    expect(page_text).to include("This link is for a different account")
    expect(page_text).to include("Sign out and open the link again")
    expect(page_text).not_to include("maya-join@example.com")
    expect(page_text).not_to include(teen.preferred_name)
  end

  it "is a no-op for the teen when they are already signed in" do
    login_as!(teen.email)

    get family_invite_path(token)

    expect(response).to redirect_to(setup_path)
  end

  describe "resending it" do
    it "is the guardian's to ask for, not the teen's" do
      expect(GuardianshipPolicy.new(parent, guardianship).resend_join?).to be(true)
      expect(GuardianshipPolicy.new(teen, guardianship).resend_join?).to be(false)
    end

    it "stops once the teen has joined" do
      teen.update!(full_name: "Maya Joined")

      expect(GuardianshipPolicy.new(parent, guardianship.reload).resend_join?).to be(false)
    end

    it "mails again, then holds off on a second click" do
      login_as!(parent.email)

      expect {
        post resend_join_guardianship_path(guardianship)
      }.to have_enqueued_mail(Fuime::FamilyMailer, :teen_join).once
      expect(flash[:success]).to match(/sent again/i)

      expect {
        post resend_join_guardianship_path(guardianship)
      }.not_to have_enqueued_mail(Fuime::FamilyMailer, :teen_join)
      expect(flash[:info]).to match(/few minutes ago/i)
    end
  end
end
