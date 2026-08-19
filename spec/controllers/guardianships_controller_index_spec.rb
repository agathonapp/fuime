# frozen_string_literal: true

require "rails_helper"

# Fuime: GET /guardian — the guardian's overview of the ventures they signed for.
#
# The guardian agreement promises this in §3 and says it "cannot be turned off by
# the minor", but until now `guardianships_as_guardian` was rendered in exactly
# one template: the *admin* user page. A guardian's only authenticated surfaces
# were the invite page, the agreement record, revoke and resend — there was no
# way for them to see the business they had taken legal responsibility for.
#
# What the read access itself is built on, and why it does not live in an
# OrganizerPosition, is covered in spec/policies/event_policy_guardian_spec.rb.
RSpec.describe GuardianshipsController do
  include SessionSupport
  render_views

  let(:guardian) { create(:user) }
  let(:minor) { create(:user, :minor) }
  let(:event) { create(:event, name: "Sunset Cookies") }

  # The minor runs the venture; that is what brings it into the guardian's view.
  before { create(:organizer_position, event:, user: minor) }

  describe "#index as a guardian who has signed" do
    before do
      create(:guardianship, :active, guardian:, minor:)
      create_session(guardian, verified: true)
    end

    it "lists the ward and the venture they run" do
      get :index

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(minor.name)
      expect(response.body).to include("Sunset Cookies")
    end

    # The summary is a table of contents; the oversight is the ledger it points
    # at. A page that named the venture but could not link into it would satisfy
    # the letter of §3 and none of its purpose.
    it "links through to the venture" do
      get :index

      expect(response.body).to include(event_path(event))
    end
  end

  describe "#index as a guardian whose invite is still pending" do
    before do
      create(:guardianship, guardian:, minor:)
      create_session(guardian, verified: true)
    end

    # They can see they have been asked. A signature not yet given buys no
    # visibility into the books.
    it "shows the invitation without the ward's venture" do
      get :index

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(minor.name)
      expect(response.body).not_to include("Sunset Cookies")
    end
  end

  describe "#index after consent is withdrawn" do
    let!(:guardianship) { create(:guardianship, :active, guardian:, minor:) }

    before { create_session(guardian, verified: true) }

    it "stops showing the venture" do
      guardianship.revoke!(revoked_by: guardian)

      get :index

      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include("Sunset Cookies")
    end
  end

  describe "#index as the teen" do
    before do
      create(:guardianship, guardian:, minor:)
      create_session(minor, verified: true)
    end

    # A teen previously had to keep the emailed link to learn anything about the
    # state of their own invite. Chasing an unresponsive parent is their problem
    # to solve, so they get the status and a resend.
    it "shows who they invited" do
      get :index

      expect(response).to have_http_status(:ok)
      # The page names the guardian (email only when they have no name),
      # matching every other guardianship surface.
      expect(response.body).to include(guardian.name)
    end
  end

  describe "#index as an unrelated adult" do
    before do
      create(:guardianship, :active, guardian:, minor:)
      create_session(create(:user), verified: true)
    end

    # The page is open to any signed-in user on purpose: gating it on
    # `is_guardian?` would 403 a parent whose invite is still pending, which is
    # exactly when they want to look. So the guarantee is that it shows them
    # nothing — not that it refuses them.
    it "shows no other family's ward or venture" do
      get :index

      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include("Sunset Cookies")
      expect(response.body).not_to include(minor.name)
    end
  end
end
