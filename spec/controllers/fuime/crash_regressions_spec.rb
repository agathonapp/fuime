# frozen_string_literal: true

require "rails_helper"

# Fuime: regressions found by crawling every GET route as each persona
# (admin, teen, guardian, adult, unguarded minor) looking for 5xx.
#
# Each example below reproduces a page that returned a 500 in that sweep. They
# are grouped here rather than scattered across controller specs because they
# share a cause worth seeing together: a page nobody clicked during manual
# testing, failing on a path that only shows up when you visit it directly.
RSpec.describe "crash-test regressions" do
  include SessionSupport

  # `config.action_controller.include_all_helpers = false`, so a helper module
  # is only available to its own controller unless ApplicationHelper includes
  # it. RolesHelper arrived with the brand sweep (manager/member/reader →
  # Owner/Team member/Parent) and was never wired in, so every view calling
  # `role_label` 500'd: the team page, the invite page, and /roles.
  describe "RolesHelper availability" do
    it "is included in ApplicationHelper" do
      expect(ApplicationHelper.included_modules).to include(RolesHelper)
    end

    it "makes role_label callable from an arbitrary view context" do
      view = ActionView::Base.empty.tap { |v| v.extend(ApplicationHelper) }

      expect(view.role_label("manager")).to eq("Owner")
      expect(view.role_label("reader")).to eq("Parent")
    end
  end

  describe EventsController, type: :controller do
    let(:admin) { create(:user, :make_admin, birthday: 30.years.ago.to_date) }
    let(:event) { create(:event) }

    before { create_session(admin, verified: true) }

    it "renders the team page" do
      create(:organizer_position, user: admin, event:, role: :manager)

      get :team, params: { event_id: event.slug }

      expect(response).to have_http_status(:ok)
    end
  end

  # `find_by!` raises before `authorize` runs, so Pundit's verify_authorized
  # after_action fired; and #verify has no template (there is no
  # app/views/users/email_updates/), so its rescue fell through to an implicit
  # render. Either way an expired link — an ordinary thing to click — 500'd.
  describe Users::EmailUpdatesController, type: :controller do
    let(:user) { create(:user, birthday: 30.years.ago.to_date) }

    before { create_session(user, verified: true) }

    it "redirects with an error when the verification token is unknown" do
      get :verify, params: { verification_token: "not-a-real-token" }

      expect(response).to redirect_to(root_path)
      expect(flash[:error]).to be_present
    end

    it "redirects with an error when the authorization token is unknown" do
      get :authorize_change, params: { authorization_token: "not-a-real-token" }

      expect(response).to redirect_to(root_path)
      expect(flash[:error]).to be_present
    end
  end

  # /sponsors is linked from Admin Tools. Two separate breaks met there:
  # SponsorPolicy called `record.event` on the Sponsor *class* for #index (a
  # class has no #event), and there was no #new action at all, so Rails rendered
  # new.html.erb with @sponsor nil.
  describe SponsorsController, type: :controller do
    let(:admin) { create(:user, :make_admin, birthday: 30.years.ago.to_date) }
    let(:teen)  { create(:user, :minor_with_guardian) }

    context "as an admin" do
      before { create_session(admin, verified: true) }

      it "renders the sponsors index" do
        get :index

        expect(response).to have_http_status(:ok)
      end

      it "renders the new sponsor form" do
        get :new

        expect(response).to have_http_status(:ok)
      end
    end

    context "as a user with no claim to any sponsor" do
      before { create_session(teen, verified: true) }

      it "denies the index instead of raising NoMethodError on the class" do
        get :index

        expect(response).to have_http_status(:redirect)
        expect(flash[:error]).to be_present
      end
    end
  end

  # Wise is outbound international transfer — the same category as wires, and
  # the only member of it missing from the disabled list, so Fuime could still
  # originate one.
  describe "disabled outbound money movement" do
    it "blocks wise_transfers alongside the other outbound rails" do
      expect(Fuime::DisabledModules::DISABLED_CONTROLLER_PREFIXES)
        .to include("wise_transfers")
    end
  end

  # #edit_address redirected before authorizing, so for a non-owner the redirect
  # fired, `authorize` then raised, and user_not_authorized redirected a second
  # time — AbstractController::DoubleRenderError, a 500 where the answer should
  # simply be "not authorized".
  describe UsersController, type: :controller do
    let(:teen)    { create(:user, :minor_with_guardian) }
    let(:someone) { create(:user, birthday: 30.years.ago.to_date) }

    before { create_session(teen, verified: true) }

    it "denies another user's address page instead of raising DoubleRenderError" do
      get :edit_address, params: { id: someone.slug }

      expect(response).to have_http_status(:redirect)
      expect(flash[:error]).to be_present
    end
  end
end
