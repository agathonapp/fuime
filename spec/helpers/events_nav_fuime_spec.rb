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

  # Fuime: "Payments" and "Payout account" answer the same question — how do I get
  # paid? — under the two different models, and the flag decides which is true.
  #
  # Showing both would put two different answers in one sidebar; showing neither
  # would leave an operator with no way to be paid at all and no page saying so.
  # Neither failure is visible from either item's own definition, which is why the
  # complement is asserted here rather than left to a comment on each.
  describe "the two money-in nav items" do
    let(:event) { create(:event) }

    # Both procs gate on the reader's own access as well as the flag. Those
    # checks have their own specs; what is under test here is the flag alone.
    #
    # The collaborators are defined on the singleton rather than stubbed: `helper`
    # is an ActionView::Base that implements neither method outside a request, so
    # `allow(...).to receive` is refused by verify_partial_doubles — correctly,
    # since there is nothing there to verify against.
    #
    # And they are defined HERE rather than in a `before`, because `helper` does
    # not hand back the same object every time it is called. Setting them up in a
    # `before` decorates one instance and the example then evaluates the proc
    # against another, so every item reads as unavailable — which looks exactly
    # like the flag being wrong and is not.
    def available?(name)
      item = EventsHelper::NAV_ITEMS.find { |i| i[:name] == name }
      expect(item).to be_present, "no nav item named #{name.inspect}"

      view = helper
      access = instance_double(EventPolicy, payment_setup_status?: true, payout_method?: true)
      view.define_singleton_method(:organizer_signed_in?) { true }
      view.define_singleton_method(:policy) { |_record| access }

      view.instance_exec(event, &item[:available_proc])
    end

    it "offers the Connect setup screen while merchant-of-record is off" do
      expect(available?("Payments")).to be(true)
      expect(available?("Payout account")).to be(false)
    end

    # Stubbed rather than left to the environment. The nav item also consults
    # Fuime::PlaidLinkService.collectable?, which is false without PLAID_CLIENT_ID
    # and PLAID_SECRET — present in .env.development (and therefore in the local
    # test container, via docker-compose's env_file) and absent on CI. Unstubbed,
    # this example passes on a laptop and fails on a shard, which is the third
    # time that shape of bug has appeared in this suite.
    #
    # What is under test here is the FLAG and the policy, not whether the machine
    # has Plaid keys.
    it "swaps to the payout destination under merchant-of-record", :merchant_of_record do
      allow(::Fuime::PlaidLinkService).to receive(:collectable?).and_return(true)

      expect(available?("Payments")).to be(false)
      expect(available?("Payout account")).to be(true)
    end

    # The Founders Weekend configuration: sandbox Plaid alongside live Stripe, so
    # a destination must not be collected yet. The nav is cosmetic — the refusal
    # that matters is in the controller — but showing an entry that leads to a page
    # which refuses is how a founder concludes the product is broken.
    it "hides the payout destination when a destination cannot be collected", :merchant_of_record do
      allow(::Fuime::PlaidLinkService).to receive(:collectable?).and_return(false)

      expect(available?("Payout account")).to be(false)
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
