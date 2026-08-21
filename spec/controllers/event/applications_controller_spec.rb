# frozen_string_literal: true

require "rails_helper"

# Fuime: pins the approval flow against a crash that reached a real user.
#
# `admin_approve` unconditionally did `@application.contract.party :hcb` for any
# teen-led application. Fuime has no DocuSeal template configured
# (`Event::Plan#contract_docuseal_template_id` is unset), so `send_contract`
# returns nil and teen-led applications have no contract at all — the call
# raised NoMethodError *after* the state transition and mailer had already run,
# producing a 500 page carrying a green "Application approved." flash.
#
# See docs/fuime/DOCUSEAL_SETUP.md for turning the signing step back on.
RSpec.describe Event::ApplicationsController, type: :controller do
  include SessionSupport

  let(:admin) { create(:user, :make_admin) }

  before { create_session(admin, verified: true) }

  describe "POST #admin_approve" do
    context "for a teen-led application with no contract (no DocuSeal template)" do
      let(:application) do
        create(:event_application, teen_led: true).tap do |app|
          app.update!(aasm_state: :under_review)
        end
      end

      it "does not raise, and approves the application" do
        expect(Event::Plan::Standard.new.contract_available?).to be false
        expect(application.contract).to be_nil

        expect {
          post :admin_approve, params: { id: application.to_param }
        }.not_to raise_error

        expect(application.reload).to be_approved
      end

      it "redirects to the submission page rather than a nil contract party" do
        post :admin_approve, params: { id: application.to_param }

        expect(response).to redirect_to(submission_application_path(application))
        expect(flash[:success]).to eq("Application approved.")
      end
    end
  end

  # The second half of the same outage: approval succeeded, but the business was
  # never created. `activate_event!` dereferenced the contract in three places,
  # and the only Activate button in the UI lived on the contract-party page —
  # which does not exist when no agreement is configured.
  describe "POST #admin_activate with no contract" do
    let(:application) do
      create(:event_application, teen_led: true, description: "Prints and stickers").tap do |app|
        app.update!(
          aasm_state: :approved,
          address_line1: "1 Main St",
          address_city: "SF",
          address_country: "US",
          address_postal_code: "94103"
        )
      end
    end

    it "creates the business" do
      expect(application.contract).to be_nil

      expect {
        post :admin_activate, params: { id: application.to_param, risk_level: "zero" }
      }.to change { Event.count }.by(1)

      expect(application.reload.event).to be_present
      expect(application.event.name).to eq(application.name)
    end

    it "redirects to the new business rather than erroring" do
      post :admin_activate, params: { id: application.to_param, risk_level: "zero" }

      expect(response).to redirect_to(event_path(application.reload.event))
    end
  end

  # Fuime: the outage of 2026-08-21 — activation 500ing instead of explaining.
  #
  # `activate_event!` deliberately refuses four ordinary situations, and
  # `admin_activate` rescued none of them, so the commonest one of all — the
  # applicant already has their one free venture, which is every account anybody
  # has tested the funnel on — reached the operator as the generic error page
  # with a reference code and no reason.
  #
  # Asserts the hole is closed on the real controller action rather than that a
  # guard method exists, per the rule in fuime_security_review_fixes_spec.
  describe "POST #admin_activate when activation is not possible" do
    # An ADULT founder, so the only thing standing between this application and
    # activation is the venture limit. A minor here would also trip the guardian
    # blocker and these examples would be quietly testing two gates at once —
    # the exact trap spec/factories/user_factory.rb warns about.
    let(:founder) { create(:user) }

    let(:application) do
      create(:event_application, user: founder, teen_led: true, description: "Prints").tap do |app|
        app.update!(aasm_state: :approved, address_country: "US")
      end
    end

    # The free plan includes one venture. Giving the founder one makes the
    # second application unactivatable — the exact case that 500'd.
    # `create(:organizer_position, ...)` is how the rest of the suite attaches a
    # user to a venture, and it is what User#events reads through.
    before { create(:organizer_position, event: create(:event), user: founder) }

    it "reports the reason instead of raising" do
      expect(application.activation_blockers).to contain_exactly(
        a_string_matching(/free plan includes one venture/)
      )

      expect {
        post :admin_activate, params: { id: application.to_param, risk_level: "zero" }
      }.not_to raise_error

      expect(response).to redirect_to(submission_application_path(application))
      expect(flash[:error]).to match(/free plan includes one venture/)
    end

    it "does not create a business" do
      expect {
        post :admin_activate, params: { id: application.to_param, risk_level: "zero" }
      }.not_to(change { Event.count })

      expect(application.reload.event).to be_nil
    end

    # The blocker list and the raise must not drift: the view promises a button
    # will work based on the first, and the second is what actually decides.
    it "keeps #activation_blockers and #activate_event! in agreement" do
      expect(application.activation_blockers).to be_present

      expect {
        application.activate_event!(risk_level: 0, point_of_contact: admin)
      }.to raise_error(ArgumentError, /free plan includes one venture/)
    end

    # Fuime: the asymmetry that actually broke activation for a superadmin.
    # `staff?` covers superadmin and exempted them from the guardian gate, but
    # nothing exempted them from the one-venture free-plan limit — a commercial
    # rule about families that a Fuime admin is not subject to.
    it "exempts a staff account from the free-plan venture limit" do
      staff = create(:user, :make_admin)
      create(:organizer_position, event: create(:event), user: staff)
      expect(staff.venture_slot_available?).to be false

      staff_app = create(:event_application, user: staff, teen_led: true, description: "Demo").tap do |app|
        app.update!(aasm_state: :approved, address_country: "US")
      end

      expect(staff_app.activation_blockers).to be_empty
    end

    # ...but an admin who has asked to be treated as an ordinary user still is.
    it "still applies the limit to an admin pretending not to be one" do
      staff = create(:user, :make_admin)
      create(:organizer_position, event: create(:event), user: staff)
      staff.update!(pretend_is_not_admin: true)

      pretending = create(:event_application, user: staff.reload, teen_led: true, description: "Demo").tap do |app|
        app.update!(aasm_state: :approved, address_country: "US")
      end

      expect(pretending.activation_blockers).to include(a_string_matching(/free plan includes one venture/))
    end

    # The mirror case, on a founder who has NOT used their free slot, so the
    # guard is shown to block the right thing rather than everything.
    #
    # Deliberately the default factory applicant rather than an explicit
    # 16-year-old: a minor with no accepted guardian trips the OTHER blocker, so
    # asserting `be_empty` on one would be asserting the absence of a gate this
    # example is not about. (That is what the first version of this spec did, and
    # CI caught it.)
    it "still activates a founder whose first venture this is" do
      unblocked = create(:event_application, teen_led: true, description: "Prints").tap do |app|
        app.update!(aasm_state: :approved, address_country: "US")
      end
      expect(unblocked.activation_blockers).to be_empty

      expect {
        post :admin_activate, params: { id: unblocked.to_param, risk_level: "zero" }
      }.to change { Event.count }.by(1)
    end
  end

  describe "Event::Application#next_step" do
    # The application card renders `next_step`, falling back to "We're reviewing
    # your application" when it returns nil. Approved-but-not-yet-activated hit
    # that fallback, so the card contradicted the "Approved" badge beside it.
    it "returns approval-appropriate copy once approved but not activated" do
      application = create(:event_application, teen_led: true)
      application.update!(
        aasm_state: :approved,
        description: "Prints and stickers",
        address_line1: "1 Main St",
        address_city: "SF",
        address_country: "US",
        address_postal_code: "94103"
      )

      expect(application.event).to be_nil
      expect(application.next_step).to be_present
      expect(application.next_step).not_to eq("We're reviewing your application")
    end
  end

end
