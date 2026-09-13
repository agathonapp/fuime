# frozen_string_literal: true

require "rails_helper"

# Fuime: the payouts page must survive the weekly run it is describing.
#
# ── The bug this file exists for ────────────────────────────────────────────
#
# A weekly batch line is also a `PayoutRequest`, created in state `pending` with
# `requested_by: nil` — nobody asked for it, the schedule made it
# (Fuime::PayoutBatchService#create_line!). Fuime::PayoutsController picked the
# venture's pending request with the bare `awaiting_approval` scope, so from the
# moment `fuime_generate_payout_batch_job` runs (Wednesday 14:00 UTC) until an
# admin approves the run, that batch line WAS "the pending request" — and the
# view renders `@pending_request.requested_by.name`.
#
# So the one page a teenager opens to ask where their money is returned a 500,
# for the whole review window, every week, starting the first week they were
# owed anything. Their guardian, who shares the page, got the same.
#
# `PayoutRequest` already had the scope that prevents this and says so in its own
# comment ("so a batch line can never wander into a guardian's decision queue").
# The controller had simply never adopted it. The lesson worth keeping: a scope
# that documents an invariant does not enforce it — the call sites do.
RSpec.describe "the payouts page while a weekly batch is in draft", type: :request do
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
    create(:event, business_category: "services", is_public: true, name: "Sunset Lawn Care").tap do |e|
      e.update!(operator_vetting_status: :approved, operator_vetted_at: Time.current)
      create(:organizer_position, event: e, user: teen)
    end
  end

  # A sale big enough to clear the hold and the reserve, so the run actually
  # produces a line for this venture rather than skipping it.
  def sale!(gross: 200_00, when_posted: 30.days.ago.to_date)
    create(:fuime_payout_method, :verified, event:)
    create(:canonical_transaction, amount_cents: gross, event:, date: when_posted,
                                   memo: "Payment from a customer [fuime_pi_#{SecureRandom.hex(4)}]")
  end

  context "under merchant-of-record", :merchant_of_record do
    before do
      create(:guardianship, :active, guardian:, minor: teen)
      sale!
      Fuime::PayoutBatchService.new.generate!(period_end: Date.current)
    end

    it "still renders for the operator" do
      login_as!(teen)

      get fuime_payouts_path(event_slug: event.slug)

      expect(response).to have_http_status(:ok)
    end

    it "still renders for the guardian, who reads the same page" do
      login_as!(guardian)

      get fuime_payouts_path(event_slug: event.slug)

      expect(response).to have_http_status(:ok)
    end

    # The positive half: the batch line is genuinely pending, and it is genuinely
    # this venture's. The page is fine because the line is not treated as a
    # request awaiting a person's decision — not because nothing was generated.
    it "has a pending batch line for this venture that nobody requested" do
      line = event.payout_requests.awaiting_approval.first

      expect(line).to be_present
      expect(line.requested_by).to be_nil
      expect(line.payout_batch).to be_present
    end

    it "does not offer the batch line to a guardian as something to approve" do
      login_as!(guardian)

      get fuime_payouts_path(event_slug: event.slug)

      expect(response.body).not_to include("waiting for approval")
    end
  end
end
