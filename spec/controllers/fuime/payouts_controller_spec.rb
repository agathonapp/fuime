# frozen_string_literal: true

require "rails_helper"

# Fuime: the payout flow over HTTP.
#
# EventPolicy asserts who *may* do what; this asserts the controller actually
# consults it, because an authorization rule no route checks is decoration. The two
# examples that matter most are the teen being refused on #approve, and the request
# being looked up through the venture — both are routes by which a minor could
# otherwise move money out of an account they do not own.
RSpec.describe Fuime::PayoutsController do
  include SessionSupport

  render_views

  let(:venture) { create(:event) }
  let(:minor) { create(:user, :minor) }
  let(:guardian) { create(:user, birthday: 40.years.ago.to_date) }
  let!(:account) { create(:stripe_connected_account, :ready, event: venture, owner: guardian) }

  before do
    create(:organizer_position, event: venture, user: minor)
    create(:guardianship, :active, guardian:, minor:)

    allow(Stripe::Balance).to receive(:retrieve).and_return(
      Stripe::Balance.construct_from(available: [{ currency: "usd", amount: 50_000 }])
    )

    # The page reports what Fuime OWES, which is a ledger fact — stubbing Stripe's
    # balance alone leaves the venture at $0 owed however much Stripe holds. That
    # separation is deliberate (the figure survives Stripe being unreachable), so
    # the ledger has to be credited too.
    create(:canonical_transaction, amount_cents: 50_000, memo: "Sale", event: venture)
  end

  def stub_payout(id: "po_req_1")
    allow(Stripe::Payout).to receive(:create)
      .and_return(Stripe::Payout.construct_from(id:, amount: 5_000, currency: "usd"))
  end

  describe "GET #index" do
    it "shows what the teen is owed" do
      create_session(minor, verified: true)

      get :index, params: { event_slug: venture.slug }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("500.00")
    end

    it "shows the page to the guardian" do
      create_session(guardian, verified: true)

      get :index, params: { event_slug: venture.slug }

      expect(response).to have_http_status(:ok)
    end

    # What Fuime owes is a LEDGER fact, so it survives Stripe being unreachable —
    # that is the point of reading Fuime::PayablesLedger rather than Stripe's
    # balance. What becomes unknown is only whether the money can move TODAY, and
    # the page has to say that without implying the money is gone.
    it "still states what is owed when Stripe cannot be reached" do
      allow(Stripe::Balance).to receive(:retrieve).and_raise(Stripe::APIError.new("boom"))
      create_session(minor, verified: true)

      get :index, params: { event_slug: venture.slug }

      expect(response).to have_http_status(:ok)
      expect(response.body).to match(/can't reach Stripe right now/)
      expect(response.body).to match(/doesn't change what you're owed/)
    end

    it "refuses an unrelated user" do
      create_session(create(:user), verified: true)

      get :index, params: { event_slug: venture.slug }

      expect(response).not_to have_http_status(:ok)
    end
  end

  describe "POST #create" do
    it "lets the teen create a request" do
      create_session(minor, verified: true)

      expect {
        post :create, params: { event_slug: venture.slug, amount: "50.00" }
      }.to change(PayoutRequest, :count).by(1)

      expect(PayoutRequest.last.amount_cents).to eq(5_000)
      expect(PayoutRequest.last.requested_by).to eq(minor)
      expect(PayoutRequest.last).to be_pending
    end

    # People type dollar signs and commas. Rejecting that input teaches a teenager
    # the tool is broken rather than that they mistyped.
    it "accepts a typed dollar sign and comma" do
      # A comma needs a four-figure amount to appear at all, so this example needs
      # more headroom than the shared $500 balance.
      allow(Stripe::Balance).to receive(:retrieve).and_return(
        Stripe::Balance.construct_from(available: [{ currency: "usd", amount: 500_000 }])
      )
      create_session(minor, verified: true)

      post :create, params: { event_slug: venture.slug, amount: "$1,240.50" }

      expect(PayoutRequest.last.amount_cents).to eq(124_050)
    end

    it "refuses more than the available balance, with an explanation" do
      create_session(minor, verified: true)

      post :create, params: { event_slug: venture.slug, amount: "9000" }

      expect(PayoutRequest.count).to eq(0)
      expect(flash[:alert]).to match(/less than/i)
    end

    it "refuses an unparseable amount without raising" do
      create_session(minor, verified: true)

      post :create, params: { event_slug: venture.slug, amount: "abc" }

      expect(PayoutRequest.count).to eq(0)
      expect(flash[:alert]).to be_present
    end

    it "does not let a guardian request on the teen's behalf" do
      create_session(guardian, verified: true)

      post :create, params: { event_slug: venture.slug, amount: "50.00" }

      expect(PayoutRequest.count).to eq(0)
    end
  end

  describe "POST #approve" do
    let!(:payout_request) do
      create(:payout_request, event: venture, requested_by: minor, amount_cents: 5_000)
    end

    it "lets the guardian approve, and sends the payout" do
      stub_payout
      create_session(guardian, verified: true)

      post :approve, params: { event_slug: venture.slug, id: payout_request.id }

      expect(payout_request.reload).to be_approved
      expect(payout_request.approved_by).to eq(guardian)
      expect(payout_request.stripe_payout_id).to eq("po_req_1")
    end

    # The single most important example in this file. Everything else is plumbing.
    it "refuses the teen approving their own request" do
      stub_payout
      create_session(minor, verified: true)

      post :approve, params: { event_slug: venture.slug, id: payout_request.id }

      expect(payout_request.reload).to be_pending
      expect(Stripe::Payout).not_to have_received(:create)
    end

    it "refuses an unrelated adult" do
      stub_payout
      create_session(create(:user, birthday: 30.years.ago.to_date), verified: true)

      post :approve, params: { event_slug: venture.slug, id: payout_request.id }

      expect(payout_request.reload).to be_pending
      expect(Stripe::Payout).not_to have_received(:create)
    end

    # `decide_payout?` is authorized against the venture in the URL, so looking the
    # request up globally would let a guardian of venture A approve venture B's
    # request just by knowing its id. The scoped lookup makes that a 404 instead —
    # the request simply does not exist as far as this venture is concerned.
    it "will not approve a request belonging to another venture" do
      stub_payout
      other_request = create(:payout_request, event: create(:event), amount_cents: 5_000)
      create_session(guardian, verified: true)

      expect {
        post :approve, params: { event_slug: venture.slug, id: other_request.id }
      }.to raise_error(ActiveRecord::RecordNotFound)

      expect(other_request.reload).to be_pending
      expect(Stripe::Payout).not_to have_received(:create)
    end

    it "surfaces a Stripe refusal without approving" do
      allow(Stripe::Payout).to receive(:create)
        .and_raise(Stripe::InvalidRequestError.new("no funds", nil, code: "balance_insufficient"))
      create_session(guardian, verified: true)

      post :approve, params: { event_slug: venture.slug, id: payout_request.id }

      expect(payout_request.reload).to be_pending
      expect(flash[:alert]).to match(/couple of days/i)
    end
  end

  describe "POST #reject" do
    let!(:payout_request) do
      create(:payout_request, event: venture, requested_by: minor, amount_cents: 5_000)
    end

    it "lets the guardian decline with a reason" do
      create_session(guardian, verified: true)

      post :reject, params: { event_slug: venture.slug, id: payout_request.id,
                              rejection_reason: "Let's reinvest it."
}

      expect(payout_request.reload).to be_rejected
      expect(payout_request.rejection_reason).to eq("Let's reinvest it.")
    end

    it "refuses the teen declining their own request" do
      create_session(minor, verified: true)

      post :reject, params: { event_slug: venture.slug, id: payout_request.id }

      expect(payout_request.reload).to be_pending
    end
  end
end
