# frozen_string_literal: true

require "rails_helper"

# Fuime: a parent sets the family up before the teen has heard of Fuime.
#
# The entry order the product did not have. What this spec is really guarding
# is the pair of things that make it safe: the stub teen is a stub (no name, no
# age answer written on their behalf), and the adulthood attestation is the
# same single path the accept page uses.
RSpec.describe "the parent setup wizard", type: :request do
  # The signup page a parent arrives on from "Set up your family".
  describe "the signup page" do
    it "speaks to a parent when return_to points at the parent path" do
      get auth_users_path(signup: true, return_to: "/setup/parent")

      expect(response).to have_http_status(:ok)
      expect(page_text).to include("Set up your family on Fuime")
      expect(page_text).to include("Social Security number")
      expect(page_text).not_to include("Start your business on Fuime")
    end

    it "speaks to a founder otherwise" do
      get auth_users_path(signup: true)

      expect(page_text).to include("Start your business on Fuime")
      expect(page_text).not_to include("Set up your family on Fuime")
    end
  end

  describe "the whole path" do
    it "walks signup → teen → sign → done and leaves an active guardianship" do
      parent = login_as!("pat-parent@example.com", return_to: "/setup/parent")
      expect(response).to redirect_to(setup_path(return_to: "/setup/parent"))

      # A name-less parent is NOT bounced into the founder wizard.
      follow_redirect!
      expect(response).to redirect_to(parent_setup_step_path(step: "teen"))

      # ── teen ──────────────────────────────────────────────────────────
      get parent_setup_step_path(step: "teen")
      expect(response).to have_http_status(:ok)
      expect(page_text).to include("is 13 or older")

      # Their own address is refused.
      post parent_setup_save_path(step: "teen"),
           params: { setup: { teen_first_name: "Maya", teen_email: parent.email, teen_13_plus: "1" } }
      expect(response).to have_http_status(:unprocessable_entity)

      # L6: under-13 is refused before anything is signed, and nothing about
      # the refusal is persisted.
      expect {
        post parent_setup_save_path(step: "teen"),
             params: { setup: { teen_first_name: "Maya", teen_email: "maya-parent@example.com" } }
      }.not_to change(User, :count)
      expect(response).to have_http_status(:unprocessable_entity)
      expect(page_text).to include("13 and up")

      post parent_setup_save_path(step: "teen"), params: {
        setup: { teen_first_name: "Maya", teen_email: "maya-parent@example.com", teen_13_plus: "1" }
      }
      expect(response).to redirect_to(parent_setup_step_path(step: "sign"))
      # Session only so far — a mistyped address creates nobody.
      expect(User.find_by(email: "maya-parent@example.com")).to be_nil

      # ── sign ──────────────────────────────────────────────────────────
      get parent_setup_step_path(step: "sign")
      expect(response).to have_http_status(:ok)
      expect(page_text).to include("I confirm I am the parent or legal guardian of")
      expect(page_text).to include("that I am 18 or older")
      expect(page_text).to include("not a bank")
      expect(page_text).to include("does not offer FDIC-insured products")

      # Without the tick, nothing happens at all.
      expect {
        post parent_setup_save_path(step: "sign"), params: { setup: { parent_full_name: "Pat Parent" } }
      }.not_to change(Guardianship, :count)
      expect(response).to have_http_status(:unprocessable_entity)
      expect(parent.reload.known_adult?).to be(false)

      post parent_setup_save_path(step: "sign"),
           params: { agree: "1", setup: { parent_full_name: "Pat Parent" } }
      expect(response).to redirect_to(parent_setup_step_path(step: "done"))

      # ── what exists now ───────────────────────────────────────────────
      parent.reload
      expect(parent.full_name).to eq("Pat Parent")
      expect(parent).to be_known_adult
      expect(parent).to be_attested_adult_18_plus

      teen = User.find_by!(email: "maya-parent@example.com")
      # A stub: named only by the first name the parent typed, with no age
      # answer written on their behalf and no full name — so `onboarding?`
      # stays true and their own first screen still asks them both questions.
      expect(teen.preferred_name).to eq("Maya")
      expect(teen.full_name).to be_blank
      expect(teen.age_attestation).to be_nil
      expect(teen).to be_onboarding
      expect(teen.creation_method).to eq("family_invite")

      guardianship = Guardianship.find_by!(guardian: parent, minor: teen)
      expect(guardianship).to be_active
      expect(guardianship).to be_initiated_by_guardian
      expect(guardianship.agreement_version).to eq(Guardianship::CURRENT_AGREEMENT_VERSION)
      expect(guardianship.agreement_ip).to be_present
      expect(guardianship.agreement_signed_at).to be_present

      # ── done ──────────────────────────────────────────────────────────
      get parent_setup_step_path(step: "done")
      expect(response).to have_http_status(:ok)
      expect(page_text).to include("guardian on Fuime")
      # The teen's sign-in token must never appear in anything the parent sees.
      expect(page_text).not_to include(Fuime::FamilyInviteService.generate_token(user: teen))
      expect(page_text).not_to include("maya-parent@example.com")
    end
  end

  describe "the mail" do
    it "sends the teen a join link and not the accepted-your-invitation mail" do
      login_as!("pat-mail@example.com", return_to: "/setup/parent")
      post parent_setup_save_path(step: "teen"), params: {
        setup: { teen_first_name: "Maya", teen_email: "maya-mail@example.com", teen_13_plus: "1" }
      }

      expect {
        post parent_setup_save_path(step: "sign"),
             params: { agree: "1", setup: { parent_full_name: "Pat Mailer" } }
      }.to have_enqueued_mail(Fuime::FamilyMailer, :teen_join).once

      expect(GuardianshipMailer).not_to have_received(:accepted) if GuardianshipMailer.respond_to?(:has_received?)
    end

    # L7: nothing to a minor between midnight and 6 a.m. local.
    it "holds the join mail until 6 a.m. when a parent signs at 1 a.m." do
      travel_to Time.find_zone!(Fuime::MinorMailWindow::DEFAULT_ZONE).local(2026, 9, 12, 1, 0, 0) do
        login_as!("pat-quiet@example.com", return_to: "/setup/parent")
        post parent_setup_save_path(step: "teen"), params: {
          setup: { teen_first_name: "Maya", teen_email: "maya-quiet@example.com", teen_13_plus: "1" }
        }
        post parent_setup_save_path(step: "sign"),
             params: { agree: "1", setup: { parent_full_name: "Pat Quiet" } }

        expect(Fuime::MinorMailWindow.earliest_send_time.in_time_zone(Fuime::MinorMailWindow::DEFAULT_ZONE).hour)
          .to eq(6)
      end
    end
  end

  # The escalation the parent door must refuse: a teenager who finished their
  # own signup cannot walk over here and attest themselves into adulthood.
  describe "a founder account trying to become a guardian" do
    it "is refused before the agreement, not after" do
      teen = login_as!("sneaky@example.com")
      post teen_setup_save_path(step: "you"),
           params: { user: { full_name: "Sneaky Founder", age_attestation_confirmed: "1" } }
      expect(teen.reload).to be_attested_minor_13_plus

      get parent_setup_step_path(step: "teen")
      expect(response).to redirect_to(root_path)
      expect(flash[:alert]).to match(/young founder/i)

      post parent_setup_save_path(step: "teen"), params: {
        setup: { teen_first_name: "Mark", teen_email: "mark@example.com", teen_13_plus: "1" }
      }
      expect(User.find_by(email: "mark@example.com")).to be_nil
      expect(teen.reload).to be_attested_minor_13_plus
      expect(teen).not_to be_known_adult
    end

    it "refuses a ward of somebody else" do
      teen = create(:user, :minor_with_guardian, full_name: "Warded Teen")
      login_as!(teen.email)

      get parent_setup_step_path(step: "teen")
      expect(response).to redirect_to(new_guardianship_path)
    end
  end

  # Migration 20260912120000 scoped the uniqueness index to live rows so a
  # parent who withdrew consent can be asked again. The wizard must not
  # reintroduce the wall that migration removed.
  describe "a previously revoked pair" do
    it "lets the same parent sign again" do
      parent = create(:user, birthday: 40.years.ago.to_date, full_name: "Pat Again", verified: true)
      teen = create(:user, :attested_teen, full_name: nil, email: "maya-again@example.com", verified: true)
      revoked = create(:guardianship, guardian: parent, minor: teen)
      revoked.revoke!(revoked_by: parent)

      login_as!(parent.email, return_to: "/setup/parent")
      post parent_setup_save_path(step: "teen"), params: {
        setup: { teen_first_name: "Maya", teen_email: teen.email, teen_13_plus: "1" }
      }
      post parent_setup_save_path(step: "sign"), params: { agree: "1" }

      expect(response).to redirect_to(parent_setup_step_path(step: "done"))
      expect(Guardianship.where(guardian: parent, minor: teen).active.count).to eq(1)
    end
  end
end
