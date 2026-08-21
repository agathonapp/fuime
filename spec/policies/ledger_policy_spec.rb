# frozen_string_literal: true

require "rails_helper"

RSpec.describe LedgerPolicy, type: :policy do
  describe "#show?" do
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

    let(:event) { create(:event) }
    let(:ledger) { event.ledger }
    let(:user) { create(:user) }

    subject { described_class.new(user, ledger).show? }

    context "as a reader" do
      before { create(:organizer_position, user:, event:, role: :reader) }

      it "is denied without either ledger flag" do
        is_expected.to eq(false)
      end

      it "is allowed when the event has new_ledger_2026_06_30 enabled" do
        Flipper.enable(:new_ledger_2026_06_30, event)

        is_expected.to eq(true)
      end

      it "is allowed when the user has opted into new_ledger_2026_07_17" do
        Flipper.enable_actor(:new_ledger_2026_07_17, user)

        is_expected.to eq(true)
      end
    end

    context "as a non-member with the opt-in flag enabled" do
      before { Flipper.enable_actor(:new_ledger_2026_07_17, user) }

      it "is denied" do
        is_expected.to eq(false)
      end
    end

    context "as an auditor" do
      let(:user) { create(:user, :make_auditor) }

      it "is allowed without either flag" do
        is_expected.to eq(true)
      end
    end
  end
end
