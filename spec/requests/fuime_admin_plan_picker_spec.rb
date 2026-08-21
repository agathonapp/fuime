# frozen_string_literal: true

require "rails_helper"

# Fuime: the admin plan control on a venture's settings page.
#
# Worth a request spec rather than a model one because the bug was in the view.
# The "Change plan" form built its <select> from `selectable_plans`, which by
# design excludes retired HCB plans — so for a venture sitting on one, the browser
# rendered the FIRST option as selected and pressing the button silently migrated
# the venture onto a different fee. `Plan.select_options(current)` exists precisely
# to keep the current type in the list, and only one of the page's two forms was
# using it.
RSpec.describe "admin plan picker", type: :request do
  def login_as!(user)
    post logins_path, params: { email: user.email, login: { purpose: "" } }
    login = Login.order(:id).last
    post email_login_path(login)
    code = LoginCode.active.where(user:).order(:id).last
    post complete_login_path(login), params: { method: "email", login_code: code.code }
    expect(User::Session.where(user:)).to exist, "login failed for #{user.email}"
  end

  let(:admin) { create(:user, :make_admin, birthday: 40.years.ago.to_date, verified: true) }

  it "renders every Fuime plan under its Fuime name" do
    venture = create(:event, plan_type: Event::Plan::Free)
    login_as!(admin)

    get edit_event_path(venture, tab: "admin")

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Fuime free (7.0%)")
    expect(response.body).to include("Fuime for schools (0.0%)")
    expect(response.body).to include("Fuime standard (5.0% + $15.00/mo)")
    # No lowercase HCB leftovers left in the control.
    expect(response.body).not_to include(">terminated<")
    expect(response.body).not_to include(">card-only<")
    expect(response.body).not_to include(">spend-only<")
  end

  it "keeps a venture on a RETIRED plan in its own picker" do
    venture = create(:event, plan_type: Event::Plan::Argosy2024)
    login_as!(admin)

    get edit_event_path(venture, tab: "admin")

    expect(response.body).to include(Event::Plan::Argosy2024.name)
  end

  it "offers exactly one writable plan control on the page" do
    venture = create(:event, plan_type: Event::Plan::Free)
    login_as!(admin)

    get edit_event_path(venture, tab: "admin")

    # Two <select name="event[plan]"> controls meant changing a postal code could
    # also post a plan.
    expect(response.body.scan(/name="event\[plan\]"/).size).to eq(1)
  end
end
