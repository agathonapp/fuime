# frozen_string_literal: true

require "rails_helper"

# Fuime: the standing "not a bank" status disclosure.
#
# Fuime presents balances, a ledger, transactions and cards. That is the exact
# presentation that leads a reader to assume a bank and deposit insurance sit
# behind it, and the FDIC's rule for non-banks makes the *omission* the
# violation, not just an affirmative false claim: 12 CFR 328.102(b)(3)(ii)
# reaches a statement that "omit[s] or fail[s] to clearly and conspicuously
# disclose material information that would be necessary to prevent a reasonable
# consumer from being misled". Subpart B has bound non-banks since 1 Jan 2025
# and was not rescinded by the 2025–26 amendments (those touched Subpart A
# signage only). See docs/fuime/LEGAL_RESEARCH.md §7.
#
# So the disclosure is not decoration and not a nice-to-have on the pricing
# page — it has to be present, and it has to survive refactors that move
# layouts around. These examples pin it on the two surfaces where its absence
# would matter most, and they exist because the failure mode is silent: nobody
# notices a missing paragraph in a footer until it is quoted back at them.
#
# The storefront is asserted separately and deliberately. It renders through the
# no-nav layout branch, which does *not* render application/_footer, so the
# footer copy genuinely does not reach it; the disclosure is duplicated into the
# view. A future refactor that unifies the layouts should delete the duplicate
# and leave both these examples passing.
# Matching on the load-bearing clauses rather than the full paragraph. The wording
# will be edited; what must not disappear is the denial of bank status, the denial of
# insurance, and who owns the account.
#
# Defined at file scope rather than inside the example group: Ruby constants assigned
# in a block leak to the top level anyway, and doing it explicitly is what
# Lint/ConstantDefinitionInBlock asks for.
NOT_A_BANK = "not a bank"
NO_FDIC = "does not offer FDIC-insured products"
GUARDIAN_OWNED = /owned by a parent or legal guardian/i

RSpec.describe "Status disclosure", type: :request do

  describe "on public legal pages" do
    # Signed out on purpose: a parent reading the terms before accepting an
    # emailed guardian invite has no account, and is precisely the reader the
    # disclosure is for.
    ["/faq", "/terms"].each do |path|
      it "discloses Fuime's status on #{path} to a signed-out visitor" do
        get path

        expect(response).to have_http_status(:ok)
        expect(response.body).to include(NOT_A_BANK)
        expect(response.body).to include(NO_FDIC)
      end
    end
  end

  describe "on a public storefront" do
    # A payer here is being asked for a card number by a stranger's business,
    # with no account and no prior relationship with Fuime.
    let(:event) { create(:event, is_public: true) }

    it "discloses Fuime's status and who owns the venture's account" do
      get "/b/#{event.slug}"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(NOT_A_BANK)
      expect(response.body).to include(NO_FDIC)
      expect(response.body).to match(GUARDIAN_OWNED)
    end

    # The inverse assertion, and the one most likely to catch a real mistake:
    # the storefront must not imply the payer's money lands anywhere insured.
    it "makes no affirmative claim of deposit insurance" do
      get "/b/#{event.slug}"

      expect(response.body).not_to match(/FDIC[- ]insured (up to|through|via)/i)
      expect(response.body).not_to include("Member FDIC")
    end
  end
end
