# frozen_string_literal: true

require "rails_helper"

# Fuime: the two queues added before the public launch, and the parent's data
# rights, exercised as HTTP.
#
# These pages are read by exactly one person under time pressure, which is when
# a view error is most expensive. The examples are about who may reach them and
# whether they render at all — the behaviour lives in the service specs.
RSpec.describe "launch ops pages", type: :request do
  # The real login dance — the SessionSupport factory shortcut trips over 2FA
  # state in request specs. Same as fuime_payout_batches_admin_spec.
  def login_as!(user)
    post logins_path, params: { email: user.email, login: { purpose: "" } }
    login = Login.order(:id).last
    post email_login_path(login)
    code = LoginCode.active.where(user:).order(:id).last
    post complete_login_path(login), params: { method: "email", login_code: code.code }
    expect(User::Session.where(user:)).to exist, "login failed for #{user.email}"
  end

  let(:admin) { create(:user, :make_admin, birthday: 40.years.ago.to_date, verified: true) }
  let(:stranger) { create(:user, birthday: 40.years.ago.to_date, verified: true) }
  let(:guardian) { create(:user, full_name: "Dana Reyes", birthday: 40.years.ago.to_date, verified: true) }
  let(:minor) { create(:user, :minor, full_name: "Sam Reyes", verified: true) }

  describe "the dispute queue" do
    before do
      event = create(:event)
      Fuime::Dispute.create!(event:, stripe_dispute_id: "dp_page_1", stripe_payment_intent_id: "pi_page_1",
                             amount_cents: 4_000, reason: "product_not_received",
                             status: "needs_response", opened_at: 1.day.ago,
                             evidence_due_at: 6.days.from_now)
    end

    it "renders for an admin, with the row on it" do
      login_as!(admin)
      get fuime_disputes_admin_index_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Product not received")
      expect(response.body).to include("Respond in Stripe")
    end

    it "keeps everybody else out" do
      login_as!(stranger)
      get fuime_disputes_admin_index_path

      expect(response).not_to have_http_status(:ok)
    end

    # The empty state is the normal state, and it has to distinguish itself from
    # "the webhook is not wired", which looks identical from this page.
    it "renders empty without pretending nothing could be wrong" do
      Fuime::Dispute.delete_all
      login_as!(admin)
      get fuime_disputes_admin_index_path

      expect(response.body).to include("charge.dispute.created")
    end
  end

  describe "the data request queue" do
    it "renders for an admin" do
      Fuime::DataRequest.create!(requested_by: guardian, subject: minor, kind: :deletion,
                                 requested_at: Time.current)
      login_as!(admin)
      get fuime_data_requests_admin_index_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("rake fuime:data_request:fulfil")
    end
  end

  describe "a parent's data rights" do
    let!(:guardianship) { create(:guardianship, :active, guardian:, minor:) }

    it "hands the guardian a file, and records that it did" do
      login_as!(guardian)

      expect { get export_data_guardianship_path(guardianship) }
        .to change { Fuime::DataRequest.kind_export.count }.by(1)

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("application/json")
      expect(JSON.parse(response.body).dig("about", "name")).to eq("Sam Reyes")
    end

    # The whole point of hanging this off the guardianship rather than the user.
    it "refuses a stranger" do
      login_as!(stranger)
      get export_data_guardianship_path(guardianship)

      expect(response).not_to have_http_status(:ok)
    end

    # Not the minor's to exercise, in either direction — see GuardianshipPolicy.
    it "refuses the teenager themselves" do
      login_as!(minor)
      get export_data_guardianship_path(guardianship)

      expect(response).not_to have_http_status(:ok)
    end

    it "opens a deletion request and tells ops" do
      login_as!(guardian)

      expect {
        post request_deletion_guardianship_path(guardianship), params: { reason: "We are closing the business." }
      }.to change { Fuime::DataRequest.kind_deletion.count }.by(1)
                                                            .and have_enqueued_mail(Fuime::DataRequestMailer, :ops_alert)

      request_row = Fuime::DataRequest.kind_deletion.last
      expect(request_row.subject).to eq(minor)
      expect(request_row.requested_by).to eq(guardian)
      expect(request_row.reason).to eq("We are closing the business.")
      # Evidence of who asked, recorded for the same reason Guardianship records
      # it at signature.
      expect(request_row.request_ip).to be_present
    end

    # Pressing it twice on a slow phone must not open two cases against one
    # child, and the parent should be told the date they were already given.
    it "does not open a second case while one is open" do
      login_as!(guardian)
      post request_deletion_guardianship_path(guardianship)

      expect { post request_deletion_guardianship_path(guardianship) }
        .not_to(change { Fuime::DataRequest.kind_deletion.count })
    end
  end
end
