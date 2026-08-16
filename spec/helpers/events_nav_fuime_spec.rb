# frozen_string_literal: true

require "rails_helper"

# Fuime: the nav must not offer what the app refuses.
#
# `Fuime::DisabledModules` blocks these at the request level, so every one of them
# was a link to a page answering "That feature isn't available on Fuime." A
# teenager clicking "Deposit a check" and bouncing reads it as broken rather than
# as absent — and Milestone 5's own verification step says a click-through must
# find no dead nav links.
#
# The property worth protecting long-term is not the specific list. It is that
# **the nav and the blocker read the same source**, so a flag flip cannot leave
# them disagreeing in either direction.
RSpec.describe EventsHelper, type: :helper do
  describe "#fuime_module_hidden?" do
    it "hides what the request-level blocker refuses" do
      Fuime::DisabledModules.blocked_prefixes.each do |prefix|
        expect(helper.fuime_module_hidden?(prefix)).to be(true), "#{prefix} is blocked but not hidden"
      end
    end

    it "hides nothing the blocker permits" do
      expect(helper.fuime_module_hidden?("invoices")).to be(false)
      expect(helper.fuime_module_hidden?("reimbursement")).to be(false)
    end

    it "treats an untagged nav item as visible" do
      expect(helper.fuime_module_hidden?(nil)).to be(false)
    end

    # The direction that actually bites: turning a feature back on must restore
    # its nav item without anybody remembering to edit a second list. That is
    # what CLAUDE.md Rule 2's "disable, don't delete" is supposed to feel like.
    it "stops hiding a module when its flag comes back", :sponsor_banking do
      expect(helper.fuime_module_hidden?("check_deposits")).to be(false)
    end

    it "hides sponsor-banking modules while the flag is off" do
      expect(helper.fuime_module_hidden?("check_deposits")).to be(true)
      expect(helper.fuime_module_hidden?("ach_transfers")).to be(true)
    end
  end

  describe "the tagged nav items" do
    # A typo'd `module_prefix` would silently never match, leaving a dead link in
    # place while looking like it had been handled.
    it "only names prefixes some list actually gates" do
      tagged = EventsHelper::NAV_ITEMS.filter_map { |i| i[:module_prefix] }
      tagged += EventsHelper::NAV_ITEMS.flat_map { |i| Array(i[:dropdown_items]).filter_map { |d| d[:module_prefix] } }

      expect(tagged).to be_present
      expect(tagged - Fuime::DisabledModules.all_gated_prefixes).to be_empty
    end
  end
end
