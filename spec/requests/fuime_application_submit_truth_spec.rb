# frozen_string_literal: true

require "rails_helper"

# Fuime: the last screen before Submit must agree with the first screen after it.
#
# ── What a founder saw ─────────────────────────────────────────────────────
#
# The review page rendered HCB's out-of-office callout: on a Saturday it read
# "Fuime is closed — it is currently the weekend and Fuime is closed.
# Applications will be reviewed within 2 business days." Submit then ran
# `Fuime::FounderAdmission`, which approves and activates on the spot, and the
# next page said "You're in."
#
# Two costs. The page lied about a review that does not happen — nobody reviews
# an application any more; the human review Fuime does have is operator vetting
# before an offer can be PUBLISHED. And it discouraged the exact founder we most
# want: a teenager at a weekend event, reading "Fuime is closed" on the screen
# with the Submit button on it.
#
# The other half of this file is the branch where admission genuinely does not
# happen — most often a second venture on Free. That redirect carried no flash at
# all, so the founder landed on an inherited "under review" status page, waiting
# on a review that will never run, for a reason nobody had told them.
RSpec.describe "what submitting an application promises", type: :request do
  def login_as!(user)
    post logins_path, params: { email: user.email, login: { purpose: "" } }
    login = Login.order(:id).last
    post email_login_path(login)
    code = LoginCode.active.where(user:).order(:id).last
    post complete_login_path(login), params: { method: "email", login_code: code.code }
    expect(User::Session.where(user:)).to exist, "login failed for #{user.email}"
  end

  let(:teen) { create(:user, :minor, birthday: 16.years.ago.to_date, verified: true) }

  before { login_as!(teen) }

  # A submittable teen-led application, the shape family_signup_flow_spec uses.
  def submittable_application
    create(
      :event_application,
      user: teen.reload,
      teen_led: true,
      name: "Nova Dog Walking",
      description: "I walk dogs after school.",
      business_category: "services",
      address_country: "US",
      cosigner_email: "parent-truth@example.com"
    )
  end

  describe "the review page" do
    let(:application) { submittable_application }

    # Two assertions, because the bug only showed on a weekend and a spec that
    # only holds on a weekend is not a pin.
    #
    # The first reads the template: the callout is gone from the page, whatever
    # day the suite runs. The second is the real page, which is a genuine check
    # on a Saturday or Sunday and a harmless one the rest of the week. Moving the
    # clock instead was the obvious route and the wrong one — every jump big
    # enough to reach a weekend also expires the session the test just built.
    it "does not render the out-of-office callout at all" do
      source = File.read(Rails.root.join("app/views/event/applications/review.html.erb"))
      rendered = source.gsub(/<%#.*?%>/m, "") # the comment explains why it went

      expect(rendered).not_to include("ooo_callout")
    end

    it "does not tell a founder that Fuime is closed" do
      get review_application_path(application)

      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include("Fuime is closed")
      expect(response.body).not_to match(/reviewed within/i)
    end
  end

  describe "when the business cannot be stood up" do
    let(:application) { submittable_application }

    before do
      allow_any_instance_of(Event::Application)
        .to receive(:activation_blockers)
        .and_return(["you already have a business on the Free plan"])
    end

    it "says why, instead of redirecting in silence" do
      post submit_application_path(application)

      expect(flash[:error]).to be_present
      expect(flash[:error]).to include("already have a business")
    end

    it "still submits the application itself" do
      post submit_application_path(application)

      expect(application.reload.event).to be_nil
      expect(application.reload).not_to be_draft
    end
  end
end
