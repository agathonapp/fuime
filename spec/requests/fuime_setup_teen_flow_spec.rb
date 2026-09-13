# frozen_string_literal: true

require "rails_helper"

# Fuime: a teenager signs up and ends up inside their own venture.
#
# Over real HTTP from the signup page, because that is the claim — five screens
# and one email, with nothing to do but type. Every gate the wizard is supposed
# to keep is asserted here, not just the happy path: the age answer, the
# country gate, the parent's email, and the fact that the venture is created
# UNVETTED and cannot publish.
RSpec.describe "the teen setup wizard", type: :request do
  # Tagged, because the suite clears the flag per example and production runs
  # merchant-of-record (render.yaml). It is not a convenience: under MoR the
  # guardian gates payouts, so a teen reaches their venture with a pending
  # invite — which is the whole claim this spec exists to prove. The Connect
  # behaviour is asserted separately below.
  describe "the whole path", :merchant_of_record do
    it "walks signup → you → business → name → family → done and leaves a real venture" do
      teen = login_as!("maya-wizard@example.com")
      expect(response).to redirect_to(setup_path(return_to: nil))

      follow_redirect!
      expect(response).to redirect_to(teen_setup_step_path(step: "you"))

      # ── you ───────────────────────────────────────────────────────────
      get teen_setup_step_path(step: "you")
      expect(response).to have_http_status(:ok)
      expect(page_text).to include("I'm 13 or older")

      # The age answer is required, and the model is what refuses.
      post teen_setup_save_path(step: "you"), params: { user: { full_name: "Maya Wizard" } }
      expect(response).to have_http_status(:unprocessable_entity)
      expect(teen.reload.age_attestation).to be_nil

      post teen_setup_save_path(step: "you"),
           params: { user: { full_name: "Maya Wizard", age_attestation_confirmed: "1" } }
      expect(response).to redirect_to(teen_setup_step_path(step: "business"))
      teen.reload
      expect(teen.full_name).to eq("Maya Wizard")
      expect(teen).to be_attested_minor_13_plus
      expect(teen.age_attestation_ip).to be_present
      expect(teen.age_attested_at).to be_present

      # ── business ──────────────────────────────────────────────────────
      get teen_setup_step_path(step: "business")
      expect(response).to have_http_status(:ok)

      post teen_setup_save_path(step: "business"),
           params: { setup: { starting_point: "not_a_point", service_type: "tutoring" } }
      expect(response).to have_http_status(:unprocessable_entity)
      expect(teen.reload.applications.count).to eq(0)

      post teen_setup_save_path(step: "business"),
           params: { setup: { starting_point: "have_idea", service_type: "tutoring" } }
      expect(response).to redirect_to(teen_setup_step_path(step: "name"))
      application = teen.reload.applications.sole
      expect(application).to be_teen_led
      expect(application.service_type).to eq("tutoring")
      # Derived by the model, never assigned by the controller — it decides
      # whether the venture may sell at all.
      expect(application.business_category).to eq("services")

      # A second POST reuses the draft rather than starting another one.
      post teen_setup_save_path(step: "business"),
           params: { setup: { starting_point: "have_business", service_type: "tutoring" } }
      expect(teen.reload.applications.count).to eq(1)

      # ── name ──────────────────────────────────────────────────────────
      get teen_setup_step_path(step: "name")
      expect(response).to have_http_status(:ok)

      post teen_setup_save_path(step: "name"), params: { setup: { name: "", description: "x" } }
      expect(response).to have_http_status(:unprocessable_entity)

      post teen_setup_save_path(step: "name"),
           params: { setup: { name: "Maya Tutoring", description: "I tutor algebra after school." } }
      expect(response).to redirect_to(teen_setup_step_path(step: "family"))

      # ── family ────────────────────────────────────────────────────────
      get teen_setup_step_path(step: "family")
      expect(response).to have_http_status(:ok)
      expect(page_text).to include("Parent or guardian's email")

      post teen_setup_save_path(step: "family"),
           params: { setup: { address_country: "US", cosigner_email: teen.email } }
      expect(response).to have_http_status(:unprocessable_entity)

      expect {
        post teen_setup_save_path(step: "family"),
             params: { setup: { address_country: "US", cosigner_email: "parent-wizard@example.com" } }
      }.to change { Guardianship.pending.count }.by(1)
      expect(response).to redirect_to(teen_setup_step_path(step: "done"))

      # ── what actually exists now ──────────────────────────────────────
      application.reload
      event = application.event
      expect(event).to be_present
      expect(event.organizer_positions.find_by(user: teen)&.role).to eq("manager")

      # The venture is created UNVETTED and cannot publish. This is the gate
      # the copy promises, and it is not the parent.
      expect(event).to be_operator_vetting_unvetted
      expect(event.offer_publish_blockers).to be_any

      # ...and the parent gates nothing about selling.
      guardianship = Guardianship.order(:id).last
      expect(guardianship.minor).to eq(teen)
      expect(guardianship).to be_pending
      expect(guardianship).to be_initiated_by_minor

      # ── done ──────────────────────────────────────────────────────────
      get teen_setup_step_path(step: "done")
      expect(response).to have_http_status(:ok)
      expect(page_text).to include("You're in.")
      expect(page_text).to include("Maya Tutoring")
      expect(page_text).to include("parent-wizard@example.com")
      # The real gate before selling, named as a human decision — the sentence
      # that has to be on this screen instead of "you can start selling".
      expect(page_text).to match(/by a person/i)

      # The done screen is a one-shot: its session state is cleared, so a
      # refresh goes back through the dispatcher rather than re-rendering.
      get teen_setup_step_path(step: "done")
      expect(response).to redirect_to(setup_path)
      follow_redirect!
      expect(response).to redirect_to(root_path)
    end
  end

  describe "the age answer" do
    it "cannot be made into adulthood by any crafted parameter" do
      teen = login_as!("crafty@example.com")

      post teen_setup_save_path(step: "you"), params: {
        user: {
          full_name: "Crafty Person",
          age_attestation_confirmed: "1",
          age_attestation: "adult_18_plus",
          birthday: 30.years.ago.to_date.to_s
        }
      }

      teen.reload
      expect(teen).to be_attested_minor_13_plus
      expect(teen).not_to be_known_adult
      expect(teen.birthday).to be_nil
    end

    it "is write-once — a second pass cannot change it" do
      teen = login_as!("written-once@example.com")
      post teen_setup_save_path(step: "you"),
           params: { user: { full_name: "Once Only", age_attestation_confirmed: "1" } }
      attested_at = teen.reload.age_attested_at

      get teen_setup_step_path(step: "you")
      # A user who has answered both questions is sent on rather than asked again.
      expect(response).to redirect_to(teen_setup_step_path(step: "business"))
      expect(teen.reload.age_attested_at).to eq(attested_at)
    end
  end

  # Under Connect the guardian gates ACTIVATION, so the venture genuinely
  # cannot be created until a parent has accepted. The wizard must say so
  # rather than dropping the founder on a dead `done` screen.
  describe "when merchant-of-record is off" do
    it "submits the application and explains what is holding the venture up" do
      teen = login_as!("connect-teen@example.com")
      post teen_setup_save_path(step: "you"),
           params: { user: { full_name: "Connect Teen", age_attestation_confirmed: "1" } }
      post teen_setup_save_path(step: "business"),
           params: { setup: { starting_point: "have_idea", service_type: "tutoring" } }
      post teen_setup_save_path(step: "name"),
           params: { setup: { name: "Connect Co", description: "I tutor algebra." } }
      post teen_setup_save_path(step: "family"),
           params: { setup: { address_country: "US", cosigner_email: "connect-parent@example.com" } }

      application = teen.reload.applications.sole
      expect(application).not_to be_draft
      expect(application.event).to be_nil
      expect(response).to redirect_to(application_path(application))
      expect(flash[:error]).to match(/guardian/i)
    end
  end

  describe "the country gate", :merchant_of_record do
    it "refuses a disallowed country and does not submit" do
      teen = login_as!("sanctioned@example.com")
      post teen_setup_save_path(step: "you"),
           params: { user: { full_name: "Sanctioned Founder", age_attestation_confirmed: "1" } }
      post teen_setup_save_path(step: "business"),
           params: { setup: { starting_point: "have_idea", service_type: "tutoring" } }
      post teen_setup_save_path(step: "name"),
           params: { setup: { name: "Nope Co", description: "Tutoring." } }

      post teen_setup_save_path(step: "family"), params: {
        setup: { address_country: Event::Application::DISALLOWED_COUNTRIES.first,
                 cosigner_email: "parent-sanctioned@example.com"
}
      }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(teen.reload.applications.sole.event).to be_nil
    end
  end
end
