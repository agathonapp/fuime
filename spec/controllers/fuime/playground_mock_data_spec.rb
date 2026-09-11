# frozen_string_literal: true

require "rails_helper"

# Playground Mode's mock ledger, restored from upstream (removed there in
# 73d010de6, "Remove playground mode & mock data"). Without it, toggling an
# organization into Playground Mode changed nothing an organizer could see.
#
# Every example here is a bug the restore actually hit on the way in.
RSpec.describe EventsController, type: :controller do
  include SessionSupport
  render_views

  let(:manager) { create(:user) }
  let(:playground) { create(:event, :demo_mode, :with_positive_balance) }
  let(:real_org) { create(:event, :with_positive_balance) }

  def mock_descriptions
    MockTransactionEngineService::GenerateMockTransaction::POSITIVE_DESCRIPTIONS.map { |d| d[:desc] } +
      [MockTransactionEngineService::GenerateMockTransaction::SERVICE_FEE_LABEL]
  end

  def rendered_mock_memos
    mock_descriptions.select { |desc| response.body.include?(desc) }
  end

  before do
    create(:organizer_position, event: playground, user: manager, role: :manager)
    create(:organizer_position, event: real_org, user: manager, role: :manager)
    create_session(manager, verified: true)
  end

  describe "the ?show_mock_data toggle" do
    it "is off until asked for" do
      get :transactions_list, params: { event_id: playground.friendly_id }

      expect(response).to have_http_status(:ok)
      expect(rendered_mock_memos).to be_empty
    end

    it "renders a mock ledger once switched on, and keeps it across requests" do
      get :transactions_list, params: { event_id: playground.friendly_id, show_mock_data: "true" }
      expect(response).to have_http_status(:ok)
      expect(rendered_mock_memos).not_to be_empty

      # The flag lives in the session, so the next request needs no param.
      get :transactions_list, params: { event_id: playground.friendly_id }
      expect(rendered_mock_memos).not_to be_empty
    end

    it "switches back off" do
      get :transactions_list, params: { event_id: playground.friendly_id, show_mock_data: "true" }
      get :transactions_list, params: { event_id: playground.friendly_id, show_mock_data: "false" }

      expect(rendered_mock_memos).to be_empty
    end

    # The session key is per event, so turning mock data on for one organization
    # must not fabricate a ledger for another.
    it "does not leak into a different organization" do
      get :transactions_list, params: { event_id: playground.friendly_id, show_mock_data: "true" }
      get :transactions_list, params: { event_id: real_org.friendly_id }

      expect(rendered_mock_memos).to be_empty
    end

    # Playground Mode is the gate, not the parameter.
    it "is refused on an organization that is not in Playground Mode" do
      get :transactions_list, params: { event_id: real_org.friendly_id, show_mock_data: "true" }

      expect(response).to have_http_status(:ok)
      expect(rendered_mock_memos).to be_empty
    end
  end

  # The banner is on every page of a Playground org, but the mock ledger only
  # renders on transactions. Linking to the current page meant clicking it from
  # the org home — where everyone starts — set the flag and did nothing visible,
  # which is exactly how it was reported.
  describe "the banner's toggle" do
    it "links to the transactions page rather than whatever page you are on" do
      get :show, params: { id: playground.friendly_id }

      expect(response.body).to include(
        "#{event_transactions_path(event_id: playground.slug)}?show_mock_data=true"
      )
    end

    # The strip is the presenter's script: the four stops of the pitch with
    # the current page lit, and an exit only when there is an impersonation
    # to exit from.
    it "renders the demo path with the current stop marked and no exit for a real session" do
      get :show, params: { id: playground.friendly_id }

      expect(response.body).to include("playground-strip")
      expect(response.body).to include('data-tour-step="playground_mode"')
      expect(response.body).to match(/is-current[^>]*aria-current="page"[^>]*>.*?Home/m)
      expect(response.body).to include(fuime_storefront_path(slug: playground.slug))
      expect(response.body).not_to include("Exit demo")
    end

    it "offers Exit demo while impersonating" do
      current_session!.update!(impersonated_by: create(:user, :make_admin))

      get :show, params: { id: playground.friendly_id }

      expect(response.body).to include("Exit demo")
      expect(response.body).to include(unimpersonate_user_path(manager.id, return_to: playground_admin_index_path))
    end

    it "offers the off switch once mock data is on" do
      get :transactions_list, params: { event_id: playground.friendly_id, show_mock_data: "true" }
      get :show, params: { id: playground.friendly_id }

      expect(response.body).to include("show_mock_data=false")
    end

    it "is absent for an organization that is not in Playground Mode" do
      get :show, params: { id: real_org.friendly_id }

      expect(response.body).not_to include("show_mock_data")
    end
  end

  # `@mock_total` is only set by the action that builds the mock ledger. Every
  # other page left it nil, and the balance partial rendered that as $0.00.
  describe "the balance while mock data is on" do
    it "keeps showing the real balance on pages that build no mock ledger" do
      get :transactions_list, params: { event_id: playground.friendly_id, show_mock_data: "true" }
      get :show, params: { id: playground.friendly_id }

      # $1,000.00 from the :with_positive_balance trait — the real balance, not $0.00.
      expect(playground.balance_available_v2_cents).to be_positive
      expect(response.body).to include(ApplicationController.helpers.render_money_amount(playground.balance_available_v2_cents))
    end
  end

  describe "the rendered rows" do
    before { get :transactions_list, params: { event_id: playground.friendly_id, show_mock_data: "true" } }

    # hcb_codes/memo/_memo caches the rendered memo under
    # "#{event}/#{hcb_code.hcb_code}/cached_memo" when custom_memo is nil. A mock
    # row has no hcb_code, so every row collided on one key and the entire ledger
    # rendered the same memo — cached for ten minutes, across requests.
    it "gives each row its own memo rather than repeating one" do
      expect(rendered_mock_memos.size).to be > 1
    end

    # The rows are OpenStructs, and the transaction partial calls methods on them
    # that take arguments (memo(event:), receipt_optional?, association(:receipts)).
    # An OpenStruct field is arity 0, so each of those was a 500 in turn.
    it "renders without hitting the partial's argument-taking calls" do
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(MockTransactionEngineService::GenerateMockTransaction::SERVICE_FEE_LABEL)
    end

    it "does not invent card-like spend" do
      expect(response.body).not_to include("Business cards")
      expect(response.body).not_to include("Farmers market booth fee")
      expect(response.body).not_to include("Fiscal sponsorship")
    end
  end

  describe "the pending take-rate row" do
    it "labels FeeEngine's accrual Fuime service fee, not Fiscal sponsorship" do
      venture = create(:event, :demo_mode, plan_type: Event::Plan::Free)
      create(:organizer_position, event: venture, user: manager, role: :manager)
      create(
        :canonical_event_mapping,
        event: venture,
        canonical_transaction: create(:canonical_transaction, amount_cents: 10_000, memo: "Lawn — Saturday block")
      )

      get :transactions_list, params: { event_id: venture.friendly_id }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Fuime service fee")
      expect(response.body).not_to include("Fiscal sponsorship")
    end
  end
end
