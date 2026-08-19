# frozen_string_literal: true

require "rails_helper"

# Fuime: `business_category` is the field that decides whether a venture may sell
# at all — Fuime::OperatorEligibility#category_blocker reads it and fails closed
# on blank, which is correct and is not what this spec is about.
#
# What this spec is about is the hole upstream of that check. The column was
# written exactly once, derived from the application's service_type at
# activation, and required by nothing: `allow_blank: true` on both the
# application and the Event, absent from required_submission_fields, and present
# in no form, no strong-params list and no admin screen anywhere in the app.
#
# So an application that skipped the business-type step submitted, approved and
# activated in silence, and produced a venture permanently unable to sell whose
# blocker told the founder to "Choose what this venture sells" — with nowhere to
# choose it, for them or for an admin standing next to them. Found before
# Founders Weekend rather than during it.
RSpec.describe "business category", type: :request do
  def login_as!(user)
    post logins_path, params: { email: user.email, login: { purpose: "" } }
    login = Login.order(:id).last
    post email_login_path(login)
    code = LoginCode.active.where(user:).order(:id).last
    post complete_login_path(login), params: { method: "email", login_code: code.code }
    expect(User::Session.where(user:)).to exist, "login failed for #{user.email}"
  end

  describe "the application cannot be submitted without one" do
    let(:application) { create(:event_application) }

    it "is listed as a required submission field" do
      # `send`: the method is private, and what it contains is the fact under test —
      # asserting it through submission_blockers alone would still pass if the field
      # were merely relabelled rather than actually required.
      expect(application.send(:required_submission_fields)).to include("business_category")
    end

    it "blocks submission while blank, naming the field in words a founder can act on" do
      application.update_columns(business_category: nil)

      expect(application.reload.submission_blockers).to include("What kind of business this is")
    end

    it "stops blocking once answered" do
      application.update_columns(business_category: "services")

      expect(application.reload.submission_blockers).not_to include("What kind of business this is")
    end
  end

  # Tagged: #category_blocker is one of the umbrella_scope_blockers, so it binds
  # only under merchant-of-record — which is the model Founders Weekend runs in.
  # Untagged, spec/support/structural_flags.rb clears the flag and the blocker
  # this whole repair exists for never fires.
  describe "an admin can repair a venture that already got through", :merchant_of_record do
    let(:admin) { create(:user, :make_admin, birthday: 40.years.ago.to_date, verified: true) }
    let(:normal_user) { create(:user, birthday: 40.years.ago.to_date, verified: true) }
    let(:event) { create(:event) }

    before { event.update_columns(business_category: nil) }

    it "sets the category, which is what unblocks selling" do
      expect(Fuime::OperatorEligibility.new(event: event).blockers)
        .to include("Choose what this venture sells before accepting payments.")

      login_as!(admin)
      post operator_vetting_category_admin_index_path(id: event.slug),
           params: { business_category: "services" }

      expect(event.reload.business_category).to eq("services")
      expect(Fuime::OperatorEligibility.new(event: event).blockers)
        .not_to include("Choose what this venture sells before accepting payments.")
    end

    # The category is what Fuime vets against, so an unrecognised value must not
    # reach the column — a blank or junk category that *looks* set is worse than
    # one that is honestly missing, because the blocker stops naming it.
    it "refuses a category that is not one of ours" do
      login_as!(admin)
      post operator_vetting_category_admin_index_path(id: event.slug),
           params: { business_category: "laundering" }

      expect(event.reload.business_category).to be_blank
      expect(flash[:alert]).to match(/not a business category/i)
    end

    it "refuses a blank submission rather than storing one" do
      login_as!(admin)
      post operator_vetting_category_admin_index_path(id: event.slug),
           params: { business_category: "" }

      expect(event.reload.business_category).to be_blank
    end

    it "is not something a non-admin can reach" do
      login_as!(normal_user)
      post operator_vetting_category_admin_index_path(id: event.slug),
           params: { business_category: "services" }

      expect(event.reload.business_category).to be_blank
    end
  end
end
