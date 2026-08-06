# frozen_string_literal: true

require "rails_helper"

# Fuime: the school's treasury page.
#
# Renders views, because the two things most likely to break here are visual: the
# funding form appearing for someone who should never see it, and the Dashboard
# fallback disappearing from the page — which matters more than usual, since API
# top-ups on a Stripe-liability account are unverified and the Dashboard may be the
# only route that works.
#
# The authorization boundary is the point of this file. A student must not reach this
# page at all: on a shared account the balance shown is every sibling venture's sales
# revenue.
RSpec.describe Fuime::SchoolFundingsController do
  include SessionSupport

  render_views

  let(:tree) { build_school_tree }
  let(:school) { tree[0] }
  let(:venture) { tree[2] }
  let!(:account) { create(:stripe_connected_account, :ready, event: school) }
  let!(:guide) { create_school_manager(school) }
  let!(:student) { create_student(venture) }

  describe "#index" do
    context "as a school manager" do
      before { create_session(guide, verified: true) }

      it "renders" do
        get :index, params: { event_slug: school.slug }

        expect(response).to have_http_status(:ok)
      end

      it "shows the balance awards are actually granted against" do
        create(:canonical_transaction, amount_cents: 25_000, date: Date.current, memo: "Funds added")
          .then { |ct| create(:canonical_event_mapping, canonical_transaction: ct, event: school) }

        get :index, params: { event_slug: school.slug }

        expect(response.body).to include("$250.00")
      end

      # Money in ACH transit must be visibly separate from money that can be awarded,
      # or a guide will grant against it and Fuime::SchoolAwardService will refuse.
      it "separates in-flight top-ups from the available balance" do
        create(:school_funding, :submitted, event: school, amount_cents: 90_000, status: "pending")

        get :index, params: { event_slug: school.slug }

        expect(response.body).to include("still on its way")
      end

      it "keeps the Stripe Dashboard fallback on the page" do
        get :index, params: { event_slug: school.slug }

        expect(response.body).to include("Stripe Dashboard")
      end

      it "attributes a Dashboard top-up rather than blaming a Fuime user" do
        create(:school_funding, :succeeded, event: school, requested_by: nil)

        get :index, params: { event_slug: school.slug }

        expect(response.body).to include("Added in Stripe")
      end
    end

    context "as a student on a venture in the programme" do
      before { create_session(student, verified: true) }

      # The assertion this file exists for. Pundit failures are rescued into a
      # redirect (ApplicationController), so the refusal shows up as "not the page"
      # rather than as an exception.
      it "refuses — the school's treasury is not a student's business" do
        get :index, params: { event_slug: school.slug }

        expect(response).not_to have_http_status(:ok)
        expect(response.body).not_to include("Add funds")
      end

      it "refuses on their own venture too, which owns no account to fund" do
        get :index, params: { event_slug: venture.slug }

        expect(response).not_to have_http_status(:ok)
      end
    end
  end

  describe "#create" do
    before { create_session(guide, verified: true) }

    it "starts a top-up and says it has not landed yet" do
      allow(Stripe::Topup).to receive(:create)
        .and_return(Stripe::Topup.construct_from(id: "tu_1", amount: 100_000, currency: "usd"))

      post :create, params: { event_slug: school.slug, amount: "1,000.00" }

      expect(SchoolFunding.last.amount_cents).to eq(100_000)
      expect(flash[:notice]).to match(/clear/i)
    end

    # A business office will paste a formatted number.
    it "accepts an amount with a dollar sign and commas" do
      allow(Stripe::Topup).to receive(:create)
        .and_return(Stripe::Topup.construct_from(id: "tu_2", amount: 250_000, currency: "usd"))

      post :create, params: { event_slug: school.slug, amount: "$2,500.00" }

      expect(SchoolFunding.last.amount_cents).to eq(250_000)
    end

    it "shows Stripe's refusal with the Dashboard fallback instead of erroring" do
      allow(Stripe::Topup).to receive(:create)
        .and_raise(Stripe::InvalidRequestError.new("Top-ups are not supported", nil))

      post :create, params: { event_slug: school.slug, amount: "1000" }

      expect(response).to redirect_to(fuime_school_fundings_path(event_slug: school.slug))
      expect(flash[:alert]).to include("Stripe Dashboard")
    end

    it "refuses a student outright" do
      create_session(student, verified: true)
      allow(Stripe::Topup).to receive(:create)

      post :create, params: { event_slug: school.slug, amount: "1000" }

      expect(SchoolFunding.count).to eq(0)
      expect(Stripe::Topup).not_to have_received(:create)
    end
  end
end
