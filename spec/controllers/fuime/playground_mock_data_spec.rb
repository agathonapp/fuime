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
    MockTransactionEngineService::GenerateMockTransaction::NEGATIVE_DESCRIPTIONS.map { |d| d[:desc] } +
      MockTransactionEngineService::GenerateMockTransaction::POSITIVE_DESCRIPTIONS.map { |d| d[:desc] } +
      ["Fuime platform fee (4%)"]
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
      expect(response.body).to include("Fuime platform fee (4%)").or include("🎪 Farmers market booth fee")
    end
  end
end
