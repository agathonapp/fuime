# frozen_string_literal: true

require "rails_helper"

# Fuime: Playground Mode money must never reach a platform figure.
#
# The pitch venture (Fuime::Playground) carries a seeded ledger and whatever a
# demo driver buys on stage. "$X moved through Fuime" on the admin panel
# (StaticPagesController#admin_tools) and the funders page
# (MarketingController#funder_stats) both read `included_in_stats`; before
# this the sample lawn money was in that total.
RSpec.describe "Playground Mode and platform stats" do
  let(:real) { create(:event) }
  let(:playground) { create(:event, :demo_mode) }

  it "excludes settled transactions mapped to a demo_mode venture" do
    counted = create(:canonical_transaction, amount_cents: 10_00)
    create(:canonical_event_mapping, canonical_transaction: counted, event: real)
    sample = create(:canonical_transaction, amount_cents: 999_00)
    create(:canonical_event_mapping, canonical_transaction: sample, event: playground)

    expect(CanonicalTransaction.included_in_stats).to include(counted)
    expect(CanonicalTransaction.included_in_stats).not_to include(sample)
    expect(CanonicalTransaction.included_in_stats.sum("abs(amount_cents)")).to eq(10_00)
  end

  it "excludes pending transactions mapped to a demo_mode venture" do
    counted = create(:canonical_pending_transaction, amount_cents: 10_00)
    create(:canonical_pending_event_mapping, canonical_pending_transaction: counted, event: real)
    sample = create(:canonical_pending_transaction, amount_cents: 999_00)
    create(:canonical_pending_event_mapping, canonical_pending_transaction: sample, event: playground)

    expect(CanonicalPendingTransaction.included_in_stats).to include(counted)
    expect(CanonicalPendingTransaction.included_in_stats).not_to include(sample)
  end

  # The admin panel figure, end to end.
  describe "the admin panel's moved-through figure", type: :request do
    it "does not count the playground ledger" do
      counted = create(:canonical_transaction, amount_cents: 42_00)
      create(:canonical_event_mapping, canonical_transaction: counted, event: real)
      sample = create(:canonical_transaction, amount_cents: 851_12)
      create(:canonical_event_mapping, canonical_transaction: sample, event: playground)

      admin = create(:user, :make_admin)
      post logins_path, params: { email: admin.email, login: { purpose: "" } }
      login = Login.order(:id).last
      post email_login_path(login)
      code = LoginCode.active.where(user: admin).order(:id).last
      post complete_login_path(login), params: { method: "email", login_code: code.code }

      get admin_tools_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("moved through Fuime")
      expect(response.body).to include("42.00")
      expect(response.body).not_to include("851.12")
      expect(response.body).not_to include("893.12")
    end
  end
end
