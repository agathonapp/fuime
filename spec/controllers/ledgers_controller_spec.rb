# frozen_string_literal: true

require "rails_helper"

RSpec.describe LedgersController, type: :controller do
  include SessionSupport

  let(:admin) { create(:user, :make_admin) }
  let(:event) { create(:event) }
  let(:ledger) { event.ledger }

  before { create_session(admin, verified: true) }

  describe "GET #show" do
    # Fuime: these cover the rewritten ledger, which is closed by default since
    # 2026-08-21 — it rendered an empty page for a venture that had taken money.
    # The feature is PAUSED, not deleted (Rule 2), so its specs still run, with
    # the switch in the state they describe. The closure itself is asserted in
    # spec/policies/ledger_kill_switch_spec.rb.
    around do |example|
      previous = ENV["FUIME_NEW_LEDGER"]
      ENV["FUIME_NEW_LEDGER"] = "true"
      example.run
    ensure
      ENV["FUIME_NEW_LEDGER"] = previous
    end

    it "returns success" do
      get :show, params: { id: ledger.to_param }
      expect(response).to be_successful
    end

    it "returns success with ledger items" do
      items = create_list(:ledger_item, 3)
      items.each do |item|
        create(:ledger_mapping, ledger:, ledger_item: item, on_primary_ledger: true)
      end

      get :show, params: { id: ledger.to_param }
      expect(response).to be_successful
    end
  end

end
