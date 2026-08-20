# frozen_string_literal: true

require "rails_helper"

# Fuime: the operator-facing half of the blocker guarantee.
#
# spec/controllers/fuime/storefront_blocker_privacy_spec.rb proves the PUBLIC
# storefront never explains why a venture cannot sell. That guarantee is only
# half a design — a control that hides the reason from everybody is not privacy,
# it is a support ticket. This file proves the people who can actually fix the
# problem are told what it is.
#
# Rendered through the payouts page because that is where an operator goes when
# money is not arriving, and because it exercises the real partial rather than a
# stub of it.
RSpec.describe Fuime::PayoutsController, "selling blockers" do
  include SessionSupport

  render_views

  let(:venture) { create(:event) }
  let(:minor) { create(:user, :minor, full_name: "Maya Operator") }
  let(:guardian) { create(:user, birthday: 40.years.ago.to_date) }
  let!(:account) { create(:stripe_connected_account, :ready, event: venture, owner: guardian) }

  # The callout's title reaches the page through `<%= %>`, so "can't" is rendered
  # as "can&#39;t" and a raw-apostrophe assertion fails against markup that is
  # perfectly correct. Same trap storefronts_controller_spec documents for Faker
  # names. Unescaping here rather than writing apostrophe-free copy: the copy is
  # what an operator reads, and it should not be shaped by the test.
  def rendered_text
    CGI.unescapeHTML(response.body)
  end

  before do
    create(:organizer_position, event: venture, user: minor)
    create(:guardianship, :active, guardian:, minor:)

    allow(Stripe::Balance).to receive(:retrieve).and_return(
      Stripe::Balance.construct_from(available: [{ currency: "usd", amount: 50_000 }])
    )
    create(:canonical_transaction, amount_cents: 50_000, memo: "Sale", event: venture)
  end

  # The partial renders nothing when there is nothing wrong, which is what makes
  # it safe to drop at the top of any venture page. If this regresses, every
  # healthy operator sees a warning about a problem they do not have.
  it "says nothing when the venture is fine" do
    create_session(minor, verified: true)

    get :index, params: { event_slug: venture.slug }

    expect(response).to have_http_status(:ok)
    expect(rendered_text).not_to include("This business can't take payments yet")
  end

  context "when the venture has not been reviewed yet" do
    before { venture.update!(operator_vetting_status: :unvetted) }

    it "tells the operator, and tells them it is Fuime's move" do
      create_session(minor, verified: true)

      get :index, params: { event_slug: venture.slug }

      expect(rendered_text).to include("This business can't take payments yet")
      expect(rendered_text).to match(/not been approved by Fuime yet/)
      # The distinction that saves a support email: waiting on us, not on them.
      expect(rendered_text).to match(/We'll email you when/)
    end

    it "tells the guardian too, since they are who usually fixes it" do
      create_session(guardian, verified: true)

      get :index, params: { event_slug: venture.slug }

      expect(rendered_text).to include("This business can't take payments yet")
    end
  end

  context "when the venture is suspended" do
    before { venture.update!(operator_vetting_status: :suspended) }

    # Suspension is the one the operator most needs stated plainly — the public
    # page deliberately will not say it, so if this page does not either, nobody
    # ever learns why their storefront went quiet.
    it "says so, and does not pretend Fuime will email them" do
      create_session(minor, verified: true)

      get :index, params: { event_slug: venture.slug }

      expect(rendered_text).to match(/suspended/i)
      expect(rendered_text).not_to match(/We'll email you when/)
    end
  end

  context "when the launch scope blocks it", :merchant_of_record do
    before { venture.update!(business_category: "food") }

    it "names the category refusal and the operator's age to the operator" do
      create_session(minor, verified: true)

      get :index, params: { event_slug: venture.slug }

      expect(rendered_text).to match(/service and digital businesses/)
      # The exact string the storefront must never print. Here it is the point.
      expect(rendered_text).to include("Maya Operator")
    end
  end
end
