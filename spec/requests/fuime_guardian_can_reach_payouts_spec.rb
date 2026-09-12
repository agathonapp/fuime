# frozen_string_literal: true

require "rails_helper"

# Fuime: the guardian's one required job must be reachable.
#
# ── The hole this file exists for ──────────────────────────────────────────
#
# `EventPolicy#connect_payout_method?` resolves to `guardian_reader?` on a family
# venture: the guardian is the ONLY person who may connect a bank account, which
# is correct under L2 — they are the legal payee.
#
# But both money nav entries were gated on `policy(...) && organizer_signed_in?`,
# and `organizer_signed_in?` requires an OrganizerPosition. Accepting a
# guardianship deliberately creates none (see EventPolicy#guardian_reader?). So
# the single required action in a guardian's entire relationship with Fuime had
# no route to it anywhere in the product:
#
#   * the venture nav hid both items from them,
#   * /guardian listed Ledger and Transactions and nothing else,
#   * the teen's payouts page says "your parent can connect the bank account"
#     with no URL to forward,
#   * and the acceptance email links only to the dashboard.
#
# The consequence is not a missing link, it is that every venture sits on the
# payout batch skip list — "No payout destination set up yet" — indefinitely,
# and nobody is ever paid.
#
# It was invisible because `PlaidLinkService.collectable?` is false while Plaid
# is in sandbox alongside live Stripe, which hides the item from everyone. The
# day Plaid flips to production — a no-code-change step, per render.yaml — this
# would have been the thing that stopped the money.
RSpec.describe "a guardian reaching the payout pages", type: :request do
  def login_as!(user)
    post logins_path, params: { email: user.email, login: { purpose: "" } }
    login = Login.order(:id).last
    post email_login_path(login)
    code = LoginCode.active.where(user:).order(:id).last
    post complete_login_path(login), params: { method: "email", login_code: code.code }
    expect(User::Session.where(user:)).to exist, "login failed for #{user.email}"
  end

  let(:guardian) { create(:user, birthday: 40.years.ago.to_date, verified: true) }
  let(:teen) { create(:user, :minor, birthday: 16.years.ago.to_date, verified: true) }

  let(:event) do
    create(:event, business_category: "services", name: "Sunset Lawn Care").tap do |e|
      e.update!(operator_vetting_status: :approved, operator_vetted_at: Time.current)
      create(:organizer_position, event: e, user: teen)
    end
  end

  before do
    event # created before the page is rendered, not lazily inside an expectation
    create(:guardianship, :active, guardian:, minor: teen)
    login_as!(guardian)
  end

  # The premise. A guardian holds no organizer position — that is the design, not
  # an accident — and the policy grants them anyway.
  it "has no organizer position but is permitted by the policy" do
    expect(OrganizerPosition.where(user: guardian, event:)).not_to exist
    expect(EventPolicy.new(guardian, event).payout_method?).to be(true)
    expect(EventPolicy.new(guardian, event).payouts?).to be(true)
  end

  it "is offered both money links on their own overview" do
    get guardianships_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(fuime_payouts_path(event_slug: event.slug))
  end

  it "can open the payout destination page" do
    get fuime_payout_method_path(event_slug: event.slug)

    expect(response).to have_http_status(:ok)
  end

  it "can open the payouts page" do
    get fuime_payouts_path(event_slug: event.slug)

    expect(response).to have_http_status(:ok)
  end

  # The other half: opening the nav to the policy must not open it to the public.
  # `reader?` is false without a position or a guardianship, so a stranger on a
  # transparent venture still sees neither page.
  context "a stranger on a transparent venture" do
    let(:outsider) { create(:user, birthday: 30.years.ago.to_date, verified: true) }

    before do
      event.update!(is_public: true, publishes_ledger: true)
      login_as!(outsider)
    end

    it "is refused both pages" do
      expect(EventPolicy.new(outsider, event).payouts?).to be(false)
      expect(EventPolicy.new(outsider, event).payout_method?).to be(false)
    end
  end
end
