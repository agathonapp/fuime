# frozen_string_literal: true

require "rails_helper"

# Fuime: proves the guardianship requirement is enforced at the request level.
#
# The original control was a redirect after profile creation — a suggestion a
# teen could simply navigate away from. These specs assert that a minor without
# an active guardianship is actually blocked, whatever URL they type.
# See docs/fuime/PRODUCTION_READINESS.md §1.1.
RSpec.describe EventsController, type: :controller do
  include SessionSupport

  let(:event) { create(:event) }

  def sign_in_as(user)
    create_session(user, verified: true)
  end

  context "as a minor with no guardian" do
    let(:teen) { create(:user, :minor) }

    before { sign_in_as(teen) }

    it "blocks the business page and redirects to the guardian invite" do
      get :show, params: { id: event.slug }

      expect(response).to redirect_to(new_guardianship_path)
    end
  end

  context "as a user whose age is unknown" do
    # The bypass: no birthday meant is_minor? was nil (falsy), so nothing fired.
    let(:ageless) { create(:user, :unknown_age) }

    before { sign_in_as(ageless) }

    it "is treated as a minor and blocked" do
      get :show, params: { id: event.slug }

      expect(response).to redirect_to(new_guardianship_path)
    end
  end

  context "as a minor with an active guardianship" do
    let(:teen) { create(:user, :minor_with_guardian) }

    before { sign_in_as(teen) }

    it "is not blocked by the guardianship filter" do
      get :show, params: { id: event.slug }

      expect(response).not_to redirect_to(new_guardianship_path)
    end
  end

  context "as an adult" do
    let(:adult) { create(:user, birthday: 30.years.ago.to_date) }

    before { sign_in_as(adult) }

    it "is not blocked" do
      get :show, params: { id: event.slug }

      expect(response).not_to redirect_to(new_guardianship_path)
    end
  end

  # Staff are not teen business owners. "Unknown age counts as minor" is correct
  # for the legal control, but admin accounts have no birthday on file, so
  # without an explicit exemption the filter bounced every admin to
  # /guardian/new on every page — including the admin console. EventPolicy
  # already exempted admins; the request filter did not.
  context "as an admin with no birthday on file" do
    let(:staff) { create(:user, :unknown_age, access_level: :admin) }

    before { sign_in_as(staff) }

    it "is not bounced to the guardian invite" do
      get :show, params: { id: event.slug }

      expect(response).not_to redirect_to(new_guardianship_path)
    end
  end

  context "as an auditor with no birthday on file" do
    let(:auditor) { create(:user, :unknown_age, access_level: :auditor) }

    before { sign_in_as(auditor) }

    it "is not bounced to the guardian invite" do
      get :show, params: { id: event.slug }

      expect(response).not_to redirect_to(new_guardianship_path)
    end
  end

  # FUIME-DIVERGENCE: applying must stay reachable for a teen who has no
  # guardian yet — the application is where the parent's email is collected and
  # the agreement is sent. Blocking it deadlocked the platform's core user: no
  # application without a guardian, no guardian without an application.
  describe "the application flow" do
    it "allowlists the applications controller" do
      expect(Fuime::GuardianshipEnforcement::ALLOWED_CONTROLLER_PATHS)
        .to include("event/applications")
    end

    it "still denies business pages, so the control is not weakened" do
      expect(Fuime::GuardianshipEnforcement::ALLOWED_CONTROLLER_PATHS)
        .not_to include("events")
    end
  end

  describe "EventPolicy" do
    let(:teen)  { create(:user, :minor) }
    let(:adult) { create(:user, birthday: 30.years.ago.to_date) }

    # Defence in depth: even if a request reached the policy directly, a minor
    # without a guardian cannot act on a business.
    it "denies write access to a minor with no guardian" do
      create(:organizer_position, user: teen, event:, role: :manager)

      policy = EventPolicy.new(teen, event)

      expect(policy.update?).to be false
      expect(policy.create_transfer?).to be false
    end

    it "allows write access once a guardian is active" do
      guarded = create(:user, :minor_with_guardian)
      create(:organizer_position, user: guarded, event:, role: :manager)

      expect(EventPolicy.new(guarded, event).update?).to be true
    end

    it "still allows a blocked minor to READ their own business" do
      create(:organizer_position, user: teen, event:, role: :manager)

      expect(EventPolicy.new(teen, event).show?).to be true
    end

    it "does not restrict adults" do
      create(:organizer_position, user: adult, event:, role: :manager)

      expect(EventPolicy.new(adult, event).update?).to be true
    end
  end
end
