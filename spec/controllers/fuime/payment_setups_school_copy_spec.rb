# frozen_string_literal: true

require "rails_helper"

# Fuime: the payment-setup pages speak to two legally different parties, and the
# first production render of #new (2026-08-05, Alpha School Santa Barbara) showed
# a school administrator being told "you will own this payment account" and
# "money your young founder collects" — guardian copy, wrong and alarming for an
# employee completing the form as the institution's representative.
#
# These assert the fork in both directions: school orgs get institutional copy,
# and family ventures keep the guardian copy word for word.
RSpec.describe Fuime::PaymentSetupsController do
  include SessionSupport

  render_views

  let(:guardian) { create(:user, birthday: 40.years.ago.to_date) }
  let(:minor) { create(:user, :minor) }

  def school_venture
    # plan_type is the factory's own mechanism — building the School plan up
    # front instead of deactivating the default and racing a second row.
    school = create(:event, name: "Alpha Copy Campus", plan_type: Event::Plan::School)
    create(:event, name: "Copy Screen Prints", slug: "school-screen-prints", parent: school)
  end

  def family_venture
    create(:event, name: "Maya Prints", slug: "family-maya-prints").tap do |venture|
      create(:organizer_position, event: venture, user: minor)
      create(:guardianship, :active, guardian:, minor:)
    end
  end

  def stub_stripe!
    allow(Stripe::Account).to receive(:create).and_return(
      Stripe::Account.construct_from(
        id: "acct_copy_test",
        charges_enabled: false, payouts_enabled: false, details_submitted: false,
        controller: { requirement_collection: "stripe" }, capabilities: {}, requirements: {}
      )
    )
    allow(Stripe::AccountSession).to receive(:create)
      .and_return(Stripe::AccountSession.construct_from(client_secret: "cs_test_copy"))
  end

  describe "#new" do
    it "speaks to a school administrator as the institution's representative" do
      stub_stripe!
      venture = school_venture
      manager = create(:user)
      OrganizerPositionInvite.create!(event: venture.parent, user: manager, sender: manager, role: :manager)
                               # self-invites auto-accept in after_create_commit (user == sender)
      create_session(manager, verified: true)

      get(:new, params: { event_slug: venture.slug })

      expect(response.body).to include("Your school owns this payment account")
      expect(response.body).to include("EIN")
      # The specific guardian-callout sentences, not the bare phrase "young
      # founder" — the site-wide footer disclosure legitimately says "young
      # founders operate them with guardian oversight" on every page, which a
      # broad negative assertion tripped over.
      expect(response.body).not_to include("Money your young founder collects")
      expect(response.body).not_to include("You will own this payment account")
    end

    it "keeps the guardian copy for a family venture" do
      stub_stripe!
      venture = family_venture
      create_session(guardian, verified: true)

      get(:new, params: { event_slug: venture.slug })

      expect(response.body).to include("You will own this payment account")
      expect(response.body).to include("Money your young founder collects")
      expect(response.body).not_to include("Your school owns")
    end
  end

  describe "#show" do
    it "never tells a school student to invite a guardian" do
      venture = school_venture
      # verified: true, or the invite accept below RETURNS FALSE (it does not
      # raise), the student silently ends up with no position, and Pundit
      # redirects them — which reads as an empty response body, not a failure
      # anywhere near the actual cause.
      student = create(:user, :minor, verified: true)
      OrganizerPositionInvite.create!(event: venture, user: student, sender: student, role: :member)
                               # self-invites auto-accept in after_create_commit (user == sender)
      create_session(student, verified: true)

      get(:show, params: { event_slug: venture.slug })

      expect(response).to have_http_status(:ok), "expected 200, got #{response.status} -> #{response.location.inspect} flash=#{flash.to_hash.inspect}"
      expect(response.body).to include("school administrator")
      expect(response.body).not_to include("Invite your guardian")
      expect(response.body).to include("the sponsoring school")
    end
  end
end
