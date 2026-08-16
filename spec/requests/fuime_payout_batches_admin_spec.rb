# frozen_string_literal: true

require "rails_helper"

# Fuime: /admin/payout_batches — the page where a human decides whether Fuime pays.
#
# The examples worth having here are not "does it render 200". They are the two
# claims the page makes that would be dangerous if untrue: that only an admin can
# release money, and that approving a run does not send any.
RSpec.describe "admin payout batches", type: :request do
  # The real login dance — the SessionSupport factory shortcut trips over 2FA
  # state in request specs. Same as fuime_waitlist_admin_spec.
  def login_as!(user)
    post logins_path, params: { email: user.email, login: { purpose: "" } }
    login = Login.order(:id).last
    post email_login_path(login)
    code = LoginCode.active.where(user:).order(:id).last
    post complete_login_path(login), params: { method: "email", login_code: code.code }
    expect(User::Session.where(user:)).to exist, "login failed for #{user.email}"
  end

  let(:admin) { create(:user, :make_admin, birthday: 40.years.ago.to_date, verified: true) }
  let(:normal_user) { create(:user, birthday: 40.years.ago.to_date, verified: true) }

  describe "who may see it" do
    it "lets an admin in" do
      login_as!(admin)
      get payout_batches_admin_index_path

      expect(response).to have_http_status(:ok)
    end

    it "keeps everybody else out" do
      login_as!(normal_user)
      get payout_batches_admin_index_path

      expect(response).not_to have_http_status(:ok)
    end
  end

  # With the flag off there is no money of Fuime's own to pay out, which is the
  # state every environment is in today. The page has to say so rather than let
  # somebody click Generate and read a raised exception as a bug.
  describe "with merchant of record off" do
    before { login_as!(admin) }

    it "says why no run can be generated" do
      get payout_batches_admin_index_path

      expect(CGI.unescapeHTML(response.body)).to include("Merchant of record is off")
    end

    it "refuses to generate one" do
      post payout_batch_generate_admin_index_path, params: { period_end: Date.current }

      expect(Fuime::PayoutBatch.count).to eq(0)
      expect(flash[:alert]).to be_present
    end
  end

  describe "reviewing a run", :merchant_of_record do
    let(:event) { create(:event) }
    let(:batch) do
      create(:canonical_transaction, amount_cents: 100_00, event:, date: 30.days.ago.to_date,
                                     memo: "Payment from a customer [fuime_pi_1]")
      Fuime::PayoutBatchService.new.generate!(period_end: Date.current)
    end

    before { login_as!(admin) }

    it "shows the policy the run was generated under, not today's" do
      batch.update_columns(hold_days: 30, reserve_basis_points: 250)

      get payout_batch_admin_index_path(id: batch.id)

      expect(CGI.unescapeHTML(response.body)).to include("30-day hold")
      expect(CGI.unescapeHTML(response.body)).to include("2.5%")
    end

    # The claim the approve button's copy makes. If approving DID move money the
    # copy would be a lie, so it is asserted rather than described.
    it "approves without posting any ledger line" do
      batch # generated before the reading is taken, or the sale does not exist yet
      before_payable = Fuime::PayablesLedger.new(event:).net_payable_cents
      expect(before_payable).to eq(100_00)

      post payout_batch_approve_admin_index_path(id: batch.id)

      expect(batch.reload).to be_approved
      expect(Fuime::PayablesLedger.new(event: event.reload).net_payable_cents).to eq(before_payable)
    end

    it "debits the operator only when the run is marked paid" do
      post payout_batch_approve_admin_index_path(id: batch.id)

      expect { post payout_batch_mark_paid_admin_index_path(id: batch.id) }
        .to change { Fuime::PayablesLedger.new(event: event.reload).net_payable_cents }.by(-90_00)
    end
  end
end
