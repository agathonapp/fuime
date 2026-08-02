# frozen_string_literal: true

require "rails_helper"

# Regression coverage for the dashboard 500 caused by impersonating an
# unverified account.
#
# `User::Session#user` deliberately returns nil for an unverified session, so
# the `user_session.create` activity recorded for such an impersonation has no
# user behind it. This partial rendered `activity.trackable.user.name`
# unguarded, raising `NoMethodError: undefined method 'name' for nil`.
#
# The blast radius is what makes it worth pinning: the partial renders inside
# the dashboard's activity feed, so one unrenderable row took down every load
# of `/` for the admin rather than degrading a single list item.
#
# Tested at the view level rather than through `StaticPagesController` because
# the dashboard's layout requires a compiled `bundle.js`, which is not built in
# the test environment — a controller spec would fail on the asset pipeline
# before it ever reached this partial.
RSpec.describe "public_activity/user_session/_create", type: :view do
  # `spec/rails_helper.rb` sets `PublicActivity.enabled = false` suite-wide, so
  # `User::Session`'s `create_login_activity` callback records nothing by
  # default. These examples are specifically about rendering that activity, so
  # tracking has to be switched back on for the records they build.
  around { |example| PublicActivity.with_tracking { example.run } }

  # `create_login_activity` sets both owner and recipient to
  # `impersonated_by || user`, so an impersonation row belongs to the admin.
  def render_activity_for(session, current_user:)
    render(
      partial: "public_activity/user_session/create",
      locals: { activity: session.activities.sole, current_user: }
    )
  end

  let(:admin) { create(:user, :make_admin) }

  context "when the impersonated account is unverified" do
    let(:shadow) { create(:user, verified: false, creation_method: :first_robotics_form) }

    let(:session) do
      create(
        :user_session,
        user: shadow,
        verified: false,
        impersonated_by: admin,
        expiration_at: 1.hour.from_now,
      )
    end

    it "renders without dereferencing the nil user" do
      expect { render_activity_for(session, current_user: admin) }.not_to raise_error,
                                                                          "The partial raised on an impersonation of an unverified user. " \
                                                                          "`User::Session#user` returns nil for unverified sessions, so this " \
                                                                          "must read through `user(allow_unverified: true)` — otherwise the " \
                                                                          "whole dashboard 500s, since this renders in the activity feed."
    end

    # `allow_unverified: true` bypasses the nil-return, so an unverified target
    # still resolves to its real name. The unguarded `.name` crashed only
    # because it went through the *default* accessor; the fix is what lets the
    # name through at all. The `|| "an account"` fallback is for a session with
    # no user row whatsoever — covered separately below.
    it "names the unverified account by reading through the unverified accessor" do
      render_activity_for(session, current_user: admin)

      expect(rendered).to include("impersonated")
      expect(rendered).to include(shadow.name)
    end
  end

  context "when the impersonated account is verified" do
    let(:target) { create(:user, verified: true) }

    let(:session) do
      create(
        :user_session,
        user: target,
        verified: true,
        impersonated_by: admin,
        expiration_at: 1.hour.from_now,
      )
    end

    it "names the impersonated user" do
      render_activity_for(session, current_user: admin)

      expect(rendered).to include("impersonated")
      expect(rendered).to include(target.name)
    end
  end

  # The `|| "an account"` fallback belongs to a session with no user row at all
  # — the shape `SessionsHelper#create_session` builds before a login resolves.
  context "when the impersonated session has no user at all" do
    let(:session) do
      create(
        :user_session,
        user: nil,
        verified: false,
        impersonated_by: admin,
        expiration_at: 1.hour.from_now,
      )
    end

    it "falls back to a placeholder rather than raising" do
      expect { render_activity_for(session, current_user: admin) }.not_to raise_error

      expect(rendered).to include("impersonated")
      expect(rendered).to include("an account")
    end
  end

  # The impersonation branch is auditor-only; a regular viewer must not be shown
  # the row at all.
  context "when the viewer is not an auditor" do
    let(:viewer) { create(:user) }

    let(:shadow) { create(:user, verified: false, creation_method: :first_robotics_form) }

    let(:session) do
      create(
        :user_session,
        user: shadow,
        verified: false,
        impersonated_by: admin,
        expiration_at: 1.hour.from_now,
      )
    end

    it "renders nothing" do
      render_activity_for(session, current_user: viewer)

      expect(rendered.strip).to be_empty
    end
  end
end
