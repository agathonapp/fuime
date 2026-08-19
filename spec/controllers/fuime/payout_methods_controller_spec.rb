# frozen_string_literal: true

require "rails_helper"

# Fuime: the payout-destination page over HTTP.
#
# EventPolicy asserts who *may* connect a bank; this asserts the controller
# actually consults it. The example that matters most is the teen being refused
# on #create — a minor who could repoint the destination could route their own
# earnings past the guardian approval that makes the ownership structure real
# (CLAUDE.md L2), and "the button isn't rendered for them" is not a control when
# the route is a URL anyone can type.
#
# The second is #destroy being scoped through the venture. `connect_payout_method?`
# is checked against @event, so a bare `Fuime::PayoutMethod.find` would let the
# guardian of one venture disconnect another venture's bank by guessing an id.
RSpec.describe Fuime::PayoutMethodsController do
  include SessionSupport

  render_views

  let(:venture) { create(:event) }
  let(:minor) { create(:user, :minor) }
  let(:guardian) { create(:user, birthday: 40.years.ago.to_date) }

  before do
    create(:organizer_position, event: venture, user: minor)
    create(:guardianship, :active, guardian:, minor:)

    allow(Fuime::PlaidLinkService).to receive(:configured?).and_return(true)
    allow(Fuime::PlaidLinkService).to receive(:sandbox?).and_return(true)
  end

  describe "GET #show" do
    it "is readable by the teen, who needs to know whether they can be paid" do
      create_session(minor, verified: true)

      get :show, params: { event_slug: venture.slug }

      expect(response).to have_http_status(:ok)
    end

    it "is readable by the guardian" do
      create_session(guardian, verified: true)

      get :show, params: { event_slug: venture.slug }

      expect(response).to have_http_status(:ok)
    end

    # The teen gets the page and not the button, and is told who to ask. A
    # disabled control with no explanation reads as a broken page to the person
    # it is aimed at.
    it "offers the teen no way to connect a bank, and names who can" do
      create_session(minor, verified: true)

      get :show, params: { event_slug: venture.slug }

      expect(response.body).not_to include("data-controller=\"plaid-link\"")
      expect(response.body).to include(guardian.name.presence || guardian.email)
    end

    it "offers the guardian the connect flow" do
      create_session(guardian, verified: true)

      get :show, params: { event_slug: venture.slug }

      expect(response.body).to include("data-controller=\"plaid-link\"")
    end

    it "shows a connected destination without ever showing digits beyond the last four" do
      create(:fuime_payout_method, :verified, event: venture, added_by: guardian,
                                              institution_name: "Chase", last4: "1234")
      create_session(minor, verified: true)

      get :show, params: { event_slug: venture.slug }

      expect(response.body).to include("Chase ••1234")
    end

    # Same posture as the Stripe test-mode banners: the app runs against a test
    # environment and a family must not be able to believe otherwise on a page
    # asking them to connect a bank.
    it "says plainly that a sandbox connection is not a real bank" do
      create_session(guardian, verified: true)

      get :show, params: { event_slug: venture.slug }

      expect(response.body).to include("test connection")
    end

    it "does not blame the bank when Fuime simply has no Plaid keys" do
      allow(Fuime::PlaidLinkService).to receive(:configured?).and_return(false)
      create_session(guardian, verified: true)

      get :show, params: { event_slug: venture.slug }

      # Matched without the apostrophe: ERB escapes it to `&#39;` on the way out,
      # and asserting on the typed form tests the encoder rather than the copy.
      expect(response.body).to include("available yet")
      expect(response.body).to include("Nothing is wrong with your account")
      expect(response.body).not_to include("data-controller=\"plaid-link\"")
    end
  end

  describe "POST #create" do
    let(:service) { instance_double(Fuime::PlaidLinkService) }

    before { allow(Fuime::PlaidLinkService).to receive(:new).and_return(service) }

    it "connects the destination the guardian chose" do
      record = create(:fuime_payout_method, :verified, event: venture, added_by: guardian)
      expect(service).to receive(:connect!)
        .with(public_token: "public-sandbox-1", account_id: "acc_1")
        .and_return(record)

      create_session(guardian, verified: true)

      post :create, params: { event_slug: venture.slug, public_token: "public-sandbox-1", account_id: "acc_1" }

      expect(response).to redirect_to(fuime_payout_method_path(event_slug: venture.slug))
      expect(flash[:notice]).to include(record.display_name)
    end

    # The control this page exists behind. Not "the button is hidden" — refused.
    it "refuses the teen, who cannot be allowed to point their own earnings somewhere" do
      create_session(minor, verified: true)

      post :create, params: { event_slug: venture.slug, public_token: "public-sandbox-1", account_id: "acc_1" }

      expect(response).not_to have_http_status(:ok)
      expect(response).not_to redirect_to(fuime_payout_method_path(event_slug: venture.slug))
    end

    # Service errors are written for a family to read, so they are surfaced
    # verbatim rather than replaced with something generic.
    it "shows the family what went wrong in their own terms" do
      allow(service).to receive(:connect!)
        .and_raise(Fuime::PlaidLinkService::Error, "Payouts can only go to a checking or savings account.")

      create_session(guardian, verified: true)

      post :create, params: { event_slug: venture.slug, public_token: "public-sandbox-1" }

      expect(flash[:alert]).to include("checking or savings")
    end

    it "says it is Fuime's problem when Plaid was never configured" do
      allow(service).to receive(:connect!).and_raise(Fuime::PlaidLinkService::NotConfigured)

      create_session(guardian, verified: true)

      post :create, params: { event_slug: venture.slug, public_token: "public-sandbox-1" }

      expect(flash[:alert]).to include("isn't available right now")
    end
  end

  describe "POST #link_token" do
    let(:service) { instance_double(Fuime::PlaidLinkService) }

    before { allow(Fuime::PlaidLinkService).to receive(:new).and_return(service) }

    it "mints a token for the guardian" do
      allow(service).to receive(:link_token).and_return("link-sandbox-1")

      create_session(guardian, verified: true)

      post :link_token, params: { event_slug: venture.slug }, format: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["link_token"]).to eq("link-sandbox-1")
    end

    it "refuses the teen" do
      create_session(minor, verified: true)

      post :link_token, params: { event_slug: venture.slug }, format: :json

      expect(response).not_to have_http_status(:ok)
    end

    it "reports a service problem without a stack trace" do
      allow(service).to receive(:link_token).and_raise(Fuime::PlaidLinkService::NotConfigured)

      create_session(guardian, verified: true)

      post :link_token, params: { event_slug: venture.slug }, format: :json

      expect(response).to have_http_status(:service_unavailable)
      expect(response.parsed_body["error"]).to be_present
    end
  end

  describe "DELETE #destroy" do
    it "retires the destination" do
      record = create(:fuime_payout_method, :verified, event: venture, added_by: guardian)

      create_session(guardian, verified: true)

      delete :destroy, params: { event_slug: venture.slug, id: record.id }

      expect(record.reload).to be_removed
      expect(venture.fuime_payout_methods.usable).to be_empty
    end

    it "refuses the teen" do
      record = create(:fuime_payout_method, :verified, event: venture, added_by: guardian)

      create_session(minor, verified: true)

      delete :destroy, params: { event_slug: venture.slug, id: record.id }

      expect(record.reload).to be_verified
    end

    # Scoped through the venture, not found globally. `connect_payout_method?` is
    # checked against @event, so a bare find would let this guardian remove a
    # destination belonging to a venture they have nothing to do with.
    it "cannot reach another venture's destination by id" do
      other_venture = create(:event)
      other_record = create(:fuime_payout_method, :verified, event: other_venture,
                                                             added_by: create(:user, birthday: 40.years.ago.to_date))

      create_session(guardian, verified: true)

      expect {
        delete :destroy, params: { event_slug: venture.slug, id: other_record.id }
      }.to raise_error(ActiveRecord::RecordNotFound)

      expect(other_record.reload).to be_verified
    end
  end

  # Fuime: sandbox Plaid while Stripe is LIVE — the Founders Weekend configuration,
  # because payouts were deliberately deferred past the first real sales.
  #
  # A sandbox Item accepts fake bank logins and still yields a payout method in
  # state `verified`, and nothing on the row records which Plaid environment made
  # it. Once PLAID_ENV is promoted, a fictional destination is indistinguishable
  # from a real one and the payout run reads both the same way. So the collection
  # is refused rather than the button merely hidden.
  describe "collecting a destination while Plaid is sandbox and Stripe is live" do
    before do
      allow(StripeService).to receive(:live?).and_return(true)
      create_session(guardian, verified: true)
    end

    it "is not collectable" do
      expect(Fuime::PlaidLinkService.collectable?).to be(false)
    end

    it "refuses to mint a Link token, in JSON, so the browser cannot start the flow" do
      post :link_token, params: { event_slug: venture.slug }, format: :json

      expect(response).to have_http_status(:service_unavailable)
      expect(response.parsed_body["error"]).to match(/payouts open later/i)
    end

    # The one that matters: a POST is reachable by anyone who can type a URL, and
    # the guardian here is fully authorised — it is the environment that is wrong,
    # not the person.
    it "refuses #create even for the guardian, and stores nothing" do
      expect {
        post :create, params: { event_slug: venture.slug, public_token: "public-sandbox-x", account_id: "acc_1" }
      }.not_to(change { Fuime::PayoutMethod.count })

      expect(flash[:alert]).to match(/payouts open later/i)
    end

    # Removal is deliberately NOT gated: a sandbox destination connected before
    # this gate existed must still be removable, and that is the safe direction.
    it "still allows removing a destination that already exists" do
      existing = create(:fuime_payout_method, :verified, event: venture, added_by: guardian)

      delete :destroy, params: { event_slug: venture.slug, id: existing.id }

      expect(existing.reload).to be_removed
    end

    # Promoting Plaid lifts the refusal with no code change — the property that
    # makes this a configuration gate rather than a feature to remember to delete.
    it "becomes collectable once Plaid is in production" do
      allow(Fuime::PlaidLinkService).to receive(:sandbox?).and_return(false)

      expect(Fuime::PlaidLinkService.collectable?).to be(true)
    end
  end
end
