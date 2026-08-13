# frozen_string_literal: true

require "rails_helper"

# Fuime: operator-facing pages must not describe money as a balance on deposit.
#
# This is the spec that gives Fuime::PayablesLedger its value. The presenter can
# frame the number correctly all it likes; if a template goes around it and prints
# `@event.balance` under a heading that says "Account balance", the product is
# back to describing a deposit account.
#
# ── Why this is a source-text check rather than a rendering one ─────────────
#
# Rendering each of these pages needs a signed-in user with the right position, a
# connected account, a funded ledger and a Stripe stub — several of them are
# turbo-frame endpoints that only make sense mid-request. A test that expensive
# gets deleted the first time it is inconvenient.
#
# What actually needs guarding is narrow and static: which method a template
# calls, and which nouns it puts on screen. Both are visible in the file. So this
# reads the templates, which makes it fast, total (nothing is skipped because a
# fixture was awkward), and specific about the failure.
#
# ── What counts as operator-facing ──────────────────────────────────────────
#
# Pages a teen operator or their guardian sees. Explicitly NOT admin pages,
# `bank_accounts/*`, or internal tooling: there the money genuinely is Fuime's own
# and "balance" is the accurate word. Narrowing the rule to where it is true is
# what keeps it enforceable.
#
# See docs/fuime/MOR_MIGRATION_PLAN.md §3.4 and §3.9.
RSpec.describe "operator-facing payables copy" do
  # Templates an operator or guardian reaches, that display money owed.
  OPERATOR_TEMPLATES = %w[
    app/views/fuime/payouts/index.html.erb
    app/views/events/home/_balance.html.erb
    app/views/events/stats.html.erb
    app/views/events/async_balance.html.erb
    app/views/events/ledger.html.erb
    app/views/events/transactions.html.erb
  ].freeze

  # Everything except comments, so the prose explaining WHY "balance" is wrong
  # does not itself trip the rule that forbids it.
  def visible_source(path)
    src = Rails.root.join(path).read
    src.gsub(/<%#.*?%>/m, "")       # ERB comment tags
       .gsub(/^\s*#.*$/, "")        # Ruby comments inside ERB blocks
  end

  OPERATOR_TEMPLATES.each do |path|
    describe path do
      let(:source) { visible_source(path) }

      it "exists" do
        expect(Rails.root.join(path)).to exist
      end

      # The nouns. "Account balance" is named explicitly by the pivot brief and by
      # L5's forbidden vocabulary; the rest are the words that turn a receivable
      # into a deposit product in a reader's head.
      it "does not describe the money as a balance, deposit or account" do
        [
          "Account balance",
          "Your balance",
          "your balance",
          "Available balance",
          "on deposit",
          "FDIC",
          "Withdraw"
        ].each do |phrase|
          expect(source).not_to include(phrase),
                                "#{path} must not say #{phrase.inspect} — it describes a deposit account. " \
                                "Use Fuime::PayablesLedger and say what Fuime owes."
        end
      end

      # The method. A template that reaches past the presenter to
      # `Event#balance_available_v2_cents` reintroduces the divergence the
      # presenter exists to remove — that figure subtracts HCB's accrued
      # fee_balance, and Fuime's fee is already deducted by Stripe at the charge.
      it "reads what is owed through Fuime::PayablesLedger" do
        forbidden = ["balance_available_v2_cents", "\.available_balance", "\.balance_available"]

        forbidden.each do |method|
          expect(source).not_to match(/#{method}/),
                                "#{path} must not call #{method} directly. " \
                                "Use payables_for(event) so every page shows the same figure."
        end
      end
    end
  end

  # The payouts page is the primary earnings surface, so it carries the standing
  # clarification rather than leaving it to the global footer.
  describe "the payouts page specifically" do
    let(:source) { Rails.root.join("app/views/fuime/payouts/index.html.erb").read }

    it "states what Fuime owes and when it is paid" do
      expect(source).to include("owed_sentence")
    end

    it "carries the disclosure that this is not money held on account" do
      expect(source).to include("disclosure")
    end

    it "shows the fee breakdown, because 'why is this less than my sales' is the first question" do
      expect(source).to include("gross_sales_cents")
      expect(source).to include("fuime_fee_cents")
      expect(source).to include("processing_fee_cents")
    end
  end

  # Guards the guard. If someone renames or moves one of these templates, the
  # examples above would silently pass over a file that no longer exists.
  describe "the template list" do
    it "names only templates that are on disk" do
      missing = OPERATOR_TEMPLATES.reject { |p| Rails.root.join(p).exist? }

      expect(missing).to be_empty, "listed but missing: #{missing.join(', ')}"
    end
  end
end
