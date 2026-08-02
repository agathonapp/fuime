# frozen_string_literal: true

require "rails_helper"

# Regression coverage for the dashboard 500 introduced by impersonating an
# unverified account.
#
# `User::Session#user` deliberately returns nil for an unverified session, so
# the `user_session.create` activity recorded for such an impersonation has no
# user behind it. `public_activity/user_session/_create` rendered
# `activity.trackable.user.name` unguarded, which raised
# `NoMethodError: undefined method 'name' for nil`.
#
# The blast radius is what makes this worth pinning: the partial renders inside
# the dashboard's activity feed, so a single unrenderable row took down every
# load of `/` for the admin rather than degrading one list item.
#
# Controller-spec style for parity with the other authenticated coverage, and
# because `SessionSupport#create_session` writes `cookies.encrypted[...]` with
# an options hash — a form only controller specs' cookie jar accepts.
RSpec.describe StaticPagesController, type: :controller do
  include SessionSupport

  render_views

  # The activity's owner/recipient is `impersonated_by || user` (see
  # `User::Session#create_login_activity`), so an impersonation row surfaces on
  # the *admin's* dashboard — which is exactly why it broke their `/`.
  def impersonation_session(target, by:, verified:)
    create(
      :user_session,
      user: target,
      verified:,
      impersonated_by: by,
      expiration_at: 1.hour.from_now,
    )
  end

  describe "GET #index" do
    let(:admin) { create(:user, :make_admin) }

    it "renders for an admin who impersonated an unverified user" do
      shadow = create(:user, verified: false, creation_method: :first_robotics_form)
      impersonation_session(shadow, by: admin, verified: false)
      create_session(admin, verified: true)

      get :index

      expect(response).to have_http_status(:ok),
                          "Expected the dashboard to render for an admin with an impersonation " \
                          "activity for an unverified user. A 500 here means the activity feed " \
                          "partial is dereferencing `User::Session#user` — nil for unverified " \
                          "sessions — and taking down the whole page."
    end

    it "renders the impersonation row rather than silently dropping it" do
      shadow = create(:user, verified: false, creation_method: :first_robotics_form)
      impersonation_session(shadow, by: admin, verified: false)
      create_session(admin, verified: true)

      get :index

      # Without this the status assertion above could pass on an empty feed,
      # leaving the regression uncovered.
      expect(response.body).to include("impersonated"),
                               "Expected the impersonation activity to appear in the feed. If " \
                               "this fails while the status check passes, the row is being " \
                               "dropped and the regression is no longer actually covered."
    end

    it "still names the target when the impersonated user is verified" do
      target = create(:user, verified: true)
      impersonation_session(target, by: admin, verified: true)
      create_session(admin, verified: true)

      get :index

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(target.name)
    end
  end
end
