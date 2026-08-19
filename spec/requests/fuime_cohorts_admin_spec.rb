# frozen_string_literal: true

require "rails_helper"

# Fuime: /admin/cohorts — creating a code, and the roster board that gets watched
# during the event.
#
# Two things are worth asserting here beyond "it renders". One is that creating a
# cohort cannot sign somebody else's name to fifty approvals. The other is that
# the roster's Next step column tells the truth about where a founder actually
# is — it is the only thing on the page anybody acts on, and a wrong answer sends
# an organiser to the wrong teenager with the wrong sentence.
RSpec.describe "admin cohorts", :merchant_of_record, type: :request do
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

  let(:admin) { create(:user, :make_admin, birthday: 40.years.ago.to_date, verified: true, full_name: "Ada Organiser") }
  let(:other_admin) { create(:user, :make_admin, birthday: 40.years.ago.to_date, verified: true) }
  let(:normal_user) { create(:user, birthday: 40.years.ago.to_date, verified: true) }

  let(:valid_params) do
    { fuime_cohort: { name: "Founders Weekend", code: "FOUNDERS26",
                      rationale: "I'm running this event and I know everyone attending.",
                      expires_at: 3.days.from_now, max_members: 50,
                      risk_level: "slight", auto_approve: "1"
}
}
  end

  describe "who may see it" do
    it "lets an admin in" do
      login_as!(admin)
      get cohorts_admin_index_path

      expect(response).to have_http_status(:ok)
    end

    it "keeps everybody else out" do
      login_as!(normal_user)
      get cohorts_admin_index_path

      expect(response).not_to have_http_status(:ok)
    end
  end

  describe "creating a cohort" do
    before { login_as!(admin) }

    it "creates it and attributes it to whoever made it" do
      post cohort_create_admin_index_path, params: valid_params

      cohort = Fuime::Cohort.sole
      expect(cohort.name).to eq("Founders Weekend")
      expect(cohort.created_by).to eq(admin)
    end

    # `created_by` is not permitted, and this is why: it is the name every vetting
    # decision the cohort makes gets recorded against.
    it "cannot sign another admin's name to the decisions" do
      post cohort_create_admin_index_path,
           params: valid_params.deep_merge(fuime_cohort: { created_by_id: other_admin.id })

      expect(Fuime::Cohort.sole.created_by).to eq(admin)
    end

    it "normalises a code somebody typed in lowercase with a dash" do
      post cohort_create_admin_index_path,
           params: valid_params.deep_merge(fuime_cohort: { code: "founders-26" })

      expect(Fuime::Cohort.sole.code).to eq("FOUNDERS26")
    end

    # An expiry and a cap are the two things that turn a leaked code into a
    # bounded incident. Neither has a default that could be read as "unlimited".
    it "refuses a cohort with no expiry" do
      post cohort_create_admin_index_path,
           params: valid_params.deep_merge(fuime_cohort: { expires_at: "" })

      expect(Fuime::Cohort.count).to eq(0)
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "refuses a cohort with no stated reason" do
      post cohort_create_admin_index_path,
           params: valid_params.deep_merge(fuime_cohort: { rationale: "" })

      expect(Fuime::Cohort.count).to eq(0)
    end
  end

  describe "the roster board" do
    let(:cohort) do
      Fuime::Cohort.create!(name: "Founders Weekend", code: "FOUNDERS26", created_by: admin,
                            rationale: "I know everyone attending.",
                            expires_at: 3.days.from_now, max_members: 50)
    end

    # `business_category` set, as a real applicant's would be by the business-type
    # step. It is carried onto the venture at activation, and a venture with a
    # blank one is blocked from selling before any other check runs — see
    # Event::Application#activate_event!. Leaving it nil here would make every
    # example below assert the same category blocker rather than what it says.
    def admitted_founder(birthday: 16.years.ago.to_date)
      user = create(:user, :minor, birthday:)
      application = create(:event_application, user:, fuime_cohort: cohort,
                                               name: "Lawn Care", teen_led: true,
                                               business_category: "services")
      Fuime::CohortAdmission.new(application: application).call
      user
    end

    before { login_as!(admin) }

    it "renders with founders on it" do
      founder = admitted_founder

      get cohort_admin_index_path(cohort)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(founder.name)
      expect(response.body).to include("FOUNDERS26")
    end

    # The column the whole page exists for. A founder who is vetted but has
    # published nothing should be told to publish, not told they are "eligible".
    it "names publishing as the next step for a founder who can sell but hasn't listed" do
      admitted_founder

      get cohort_admin_index_path(cohort)

      expect(response.body).to include("Publish something to sell")
    end

    # And a founder blocked by the age floor should see THAT, not a generic
    # message — it is the one an organiser cannot fix by walking over.
    it "names the real blocker for a founder under the operator age floor" do
      admitted_founder(birthday: 14.years.ago.to_date)

      get cohort_admin_index_path(cohort)

      expect(response.body).to include("must be at least")
    end

    # Parents are tracked apart from the funnel on purpose: under MoR a missing
    # guardian does not block selling, it blocks being paid.
    it "counts founders with no guardian without calling them blocked" do
      admitted_founder

      get cohort_admin_index_path(cohort)

      expect(response.body).to include("can sell today")
    end
  end

  describe "turning a code off" do
    let(:cohort) do
      Fuime::Cohort.create!(name: "Founders Weekend", code: "FOUNDERS26", created_by: admin,
                            rationale: "I know everyone attending.",
                            expires_at: 3.days.from_now, max_members: 50)
    end

    it "stops it admitting anybody new" do
      login_as!(admin)

      post cohort_archive_admin_index_path(cohort)

      expect(cohort.reload).to be_archived
      expect(Fuime::Cohort.for_code("FOUNDERS26")).to be_nil
    end

    # Archived, not destroyed: the record of who was admitted under it is the only
    # way to review the decision afterwards.
    it "keeps the founders it already admitted" do
      user = create(:user, :minor, birthday: 16.years.ago.to_date)
      application = create(:event_application, user:, fuime_cohort: cohort,
                                               name: "Lawn Care", teen_led: true)
      Fuime::CohortAdmission.new(application: application).call
      login_as!(admin)

      post cohort_archive_admin_index_path(cohort)

      expect(application.reload.event).to be_present
      expect(cohort.reload.applications).to include(application)
    end
  end

end
