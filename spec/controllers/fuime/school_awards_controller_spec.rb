# frozen_string_literal: true

require "rails_helper"

# Fuime: the awards page, rendered.
#
# `render_views` because the two things most likely to go wrong here are view-layer:
# the nav item and the grant form appearing for the wrong person, and the reference
# field failing to tell a school administrator not to type a grade into it.
RSpec.describe Fuime::SchoolAwardsController do
  include SessionSupport

  render_views

  let(:school_tree) { build_school_tree }
  let(:school)  { school_tree[0] }
  let(:venture) { school_tree[2] }

  let!(:school_account) { create(:stripe_connected_account, :ready, event: school) }
  let!(:guide)   { create_school_manager(school) }
  let!(:student) { create_student(venture) }

  def fund_school!(cents)
    ct = create(:canonical_transaction, amount_cents: cents, date: Date.current, memo: "Funding")
    create(:canonical_event_mapping, canonical_transaction: ct, event: school)
  end

  describe "#index" do
    it "shows the guide the school's available balance and a grant form" do
      fund_school!(100_000)
      create_session(guide, verified: true)

      get :index, params: { event_slug: venture.slug }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Who earned it?")
      expect(response.body).to include("$1,000.00")
    end

    # The student sees their money but cannot hand out the school's.
    it "shows the student the awards without the grant form" do
      fund_school!(100_000)
      create_session(student, verified: true)

      get :index, params: { event_slug: venture.slug }

      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include("Who earned it?")
    end

    # The one thing a school administrator must not do with this field.
    it "tells the granter not to put grades in the reference field" do
      fund_school!(100_000)
      create_session(guide, verified: true)

      get :index, params: { event_slug: venture.slug }

      expect(response.body).to match(/don't put grades or coursework here/i)
      expect(response.body).to match(/doesn't store student academic\s+records/i)
    end

    it "says so plainly on a venture with no school behind it" do
      ordinary = create(:event)
      create(:stripe_connected_account, :ready, event: ordinary)
      owner = create(:user, birthday: 40.years.ago.to_date)
      create(:organizer_position, event: ordinary, user: owner, role: :manager)

      create_session(owner, verified: true)
      get :index, params: { event_slug: ordinary.slug }

      # Not the full sentence: the callout's `title:` is emitted through `<%=` in the
      # partial, so its apostrophe arrives HTML-escaped as `isn&#39;t`. Literal view
      # text elsewhere in this file is not escaped, which is why those assertions can
      # keep their apostrophes.
      expect(response.body).to include("part of a school programme")
    end

    it "warns the school once a student passes the $600 reporting threshold" do
      fund_school!(100_000)
      6.times do
        Fuime::SchoolAwardService.new(venture:)
                                 .grant!(amount_cents: 10_000, awarded_to: student, awarded_by: guide)
      end

      create_session(guide, verified: true)
      get :index, params: { event_slug: venture.slug }

      expect(response.body).to include("Reporting threshold reached")
      expect(response.body).to match(/1099-MISC/)
      # Fuime is not the withholding agent and must not imply otherwise.
      expect(response.body).to match(/school's filing obligation, not Fuime's/)
    end

    it "does not warn below the threshold" do
      fund_school!(100_000)
      Fuime::SchoolAwardService.new(venture:)
                               .grant!(amount_cents: 10_000, awarded_to: student, awarded_by: guide)

      create_session(guide, verified: true)
      get :index, params: { event_slug: venture.slug }

      expect(response.body).not_to include("Reporting threshold reached")
    end
  end

  describe "#create" do
    before { fund_school!(100_000) }

    it "lets a school manager award money" do
      create_session(guide, verified: true)

      post :create, params: { event_slug: venture.slug, amount: "$100.00",
                              awarded_to_id: student.id, reference: "gradebook-4417"
}

      expect(SchoolAward.count).to eq(1)
      expect(venture.reload.balance_v2_cents).to eq(10_000)
    end

    # The direction that makes this different from a payout: there is no student verb.
    it "refuses the student" do
      create_session(student, verified: true)

      post :create, params: { event_slug: venture.slug, amount: "100",
                              awarded_to_id: student.id
}

      expect(SchoolAward.count).to eq(0)
    end

    it "refuses a manager of a different school" do
      other_school, _cohort, _v = build_school_tree(school_name: "Beta School")
      create_session(create_school_manager(other_school), verified: true)

      post :create, params: { event_slug: venture.slug, amount: "100",
                              awarded_to_id: student.id
}

      expect(SchoolAward.count).to eq(0)
    end

    it "surfaces the underfunded message rather than a stack trace" do
      create_session(guide, verified: true)

      post :create, params: { event_slug: venture.slug, amount: "5000",
                              awarded_to_id: student.id
}

      expect(flash[:alert]).to match(/available to award/)
      expect(SchoolAward.count).to eq(0)
    end
  end

  describe "#void" do
    before { fund_school!(100_000) }

    let(:award) do
      Fuime::SchoolAwardService.new(venture:)
                               .grant!(amount_cents: 10_000, awarded_to: student, awarded_by: guide)
    end

    it "lets a school manager reverse an award" do
      create_session(guide, verified: true)

      post :void, params: { event_slug: venture.slug, id: award.id, void_reason: "Entered twice" }

      expect(award.reload).to be_voided
      expect(venture.reload.balance_v2_cents).to eq(0)
      expect(school.reload.balance_v2_cents).to eq(100_000)
    end

    it "refuses the student" do
      create_session(student, verified: true)

      post :void, params: { event_slug: venture.slug, id: award.id }

      expect(award.reload).not_to be_voided
    end
  end
end
