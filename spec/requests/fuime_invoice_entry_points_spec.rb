# frozen_string_literal: true

require "rails_helper"

# Fuime: invoices are off, so nothing may offer to start one.
#
# The nav item and the request-level blocker were both handled when invoices were
# disabled. Two BUTTONS were not: a "Send an invoice" quick-action on the venture
# home page and a "New Invoice" button on the sponsor page, each gated only on
# `InvoicePolicy#create?` — an upstream permission question that answers yes for
# any organizer and cannot know whether Fuime offers invoices at all.
#
# That combination is worse than either state alone: the sidebar says the feature
# does not exist while a button on the home page offers it, and clicking bounces.
# The founder found it by looking at their own screen, which is how it should not
# have to be found.
RSpec.describe "invoice entry points while the module is off", type: :request do
  let(:operator) { create(:user, birthday: 17.years.ago.to_date) }
  let(:venture) { create(:event, business_category: "services") }

  before do
    create(:organizer_position, event: venture, user: operator, role: :manager)
    post logins_path, params: { email: operator.email, login: { purpose: "" } }
    login = Login.order(:id).last
    post email_login_path(login)
    code = LoginCode.active.where(user: operator).order(:id).last
    post complete_login_path(login), params: { method: "email", login_code: code.code }
  end

  it "offers no way to start an invoice from the venture home page" do
    get event_path(venture)

    expect(response.body).not_to match(/Send an invoice/i)
  end

  # The module being blocked is the precondition for the above, asserted here so a
  # failure says which half broke.
  it "has invoices blocked at the request layer" do
    expect(Fuime::DisabledModules.blocked_prefixes).to include("invoices")
  end
end
