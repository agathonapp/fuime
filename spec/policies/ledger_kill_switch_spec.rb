# frozen_string_literal: true

require "rails_helper"

# Fuime: the rewritten ledger is closed for everyone (2026-08-21).
#
# It rendered "This ledger has no items yet" for a venture whose classic ledger
# correctly showed a $5 payment and its fee. Showing a founder an empty ledger
# for money they have actually taken is the worst failure this product has.
#
# These assert the CLOSURE holds against the two ways in that mattered: the
# auditor branch, which was unconditional and is how staff saw it regardless of
# any flag, and a per-user Flipper actor, which is what
# EventsController#toggle_new_ledger hands out and what makes "turn the flag
# off" insufficient on its own.
RSpec.describe "the new ledger kill switch" do
  let(:event) { create(:event) }
  let(:admin) { create(:user, :make_admin) }
  let(:member) { create(:user) }

  before { create(:organizer_position, event:, user: member) }

  def with_new_ledger(value)
    previous = ENV["FUIME_NEW_LEDGER"]
    ENV["FUIME_NEW_LEDGER"] = value
    yield
  ensure
    ENV["FUIME_NEW_LEDGER"] = previous
  end

  describe "while the switch is off (the default)" do
    it "is off by default" do
      with_new_ledger(nil) { expect(Fuime::Features.new_ledger?).to be false }
    end

    it "refuses an auditor, whose branch was unconditional" do
      with_new_ledger(nil) do
        expect(EventPolicy.new(admin, event).ledger?).to be false
      end
    end

    it "refuses a member who has the per-user Flipper actor enabled" do
      Flipper.enable_actor(:new_ledger_2026_07_17, member)

      with_new_ledger(nil) do
        expect(EventPolicy.new(member, event).ledger?).to be false
      end
    ensure
      Flipper.disable_actor(:new_ledger_2026_07_17, member)
    end

    it "refuses when the per-event flag is enabled" do
      Flipper.enable(:new_ledger_2026_06_30, event)

      with_new_ledger(nil) do
        expect(EventPolicy.new(member, event).ledger?).to be false
      end
    ensure
      Flipper.disable(:new_ledger_2026_06_30, event)
    end
  end

  # The switch is a pause, not a deletion (CLAUDE.md Rule 2): with it on, the
  # Flipper flags decide again exactly as before.
  describe "while the switch is on" do
    it "lets an auditor back in" do
      with_new_ledger("true") do
        expect(EventPolicy.new(admin, event).ledger?).to be true
      end
    end

    it "still requires a flag for an ordinary member" do
      with_new_ledger("true") do
        expect(EventPolicy.new(member, event).ledger?).to be false
      end
    end

    it "honours the per-user actor again" do
      Flipper.enable_actor(:new_ledger_2026_07_17, member)

      with_new_ledger("true") do
        expect(EventPolicy.new(member, event).ledger?).to be true
      end
    ensure
      Flipper.disable_actor(:new_ledger_2026_07_17, member)
    end
  end
end
