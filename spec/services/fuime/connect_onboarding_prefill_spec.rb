# frozen_string_literal: true

require "rails_helper"

# Fuime: handing Stripe what Fuime already knows about the guardian.
#
# Stripe's identity flow is the single biggest drop-off in the onboarding funnel, and
# it is per family — at a school rolling out to thousands, the gap between confirming
# prefilled details and typing them into a phone is hundreds of students who never
# trade. STRIPE_PASS.md records that prefill was exercised against real Stripe and
# accepted, so this was a proven capability that was simply never wired up.
#
# The examples split into two halves, and the second matters more than the first:
# what gets sent, and what must NEVER be sent because a malformed value fails the
# whole account create and leaves a family unable to onboard at all. No prefill is a
# minor inconvenience; a rejected account is a dead venture.
RSpec.describe Fuime::ConnectOnboardingService, "guardian prefill" do
  let(:venture) { create(:event) }
  let(:guardian) do
    create(:user,
           full_name: "Marion Okonkwo",
           email: "marion@example.com",
           birthday: Date.new(1984, 3, 17))
  end

  def stub_account(id:)
    Stripe::Account.construct_from(
      id:,
      charges_enabled: false, payouts_enabled: false, details_submitted: false,
      controller: {
        losses: { payments: "stripe" }, fees: { payer: "account" },
        requirement_collection: "stripe", stripe_dashboard: { type: "none" }
      },
      capabilities: {}, requirements: {}
    )
  end

  # Capture what Stripe was actually asked to create. The params are the subject of
  # every example here, so they are read from the call rather than inferred.
  def params_for(event:, user:)
    captured = nil
    account = stub_account(id: "acct_prefill_test")
    allow(Stripe::Account).to receive(:create) do |params, *|
      captured = params
      account
    end

    described_class.new(event:, guardian: user).find_or_create_account!
    captured
  end

  def created_params
    params_for(event: venture, user: guardian)
  end

  describe "what Stripe receives" do
    it "sends the guardian's legal first and last name" do
      individual = created_params[:individual]

      expect(individual[:first_name]).to eq("Marion")
      expect(individual[:last_name]).to eq("Okonkwo")
    end

    it "sends the date of birth in Stripe's day/month/year shape" do
      expect(created_params[:individual][:dob]).to eq(day: 17, month: 3, year: 1984)
    end

    it "sends the guardian's email" do
      expect(created_params[:individual][:email]).to eq("marion@example.com")
    end

    # The prefill must not disturb anything the account already depended on.
    it "leaves the controller, capabilities and manual payout schedule alone" do
      params = created_params

      expect(params[:controller][:losses][:payments]).to eq("stripe")
      expect(params[:settings][:payouts][:schedule][:interval]).to eq("manual")
      expect(params[:metadata][:fuime_guardian_user_id]).to eq(guardian.id)
    end
  end

  describe "what it refuses to send" do
    # A guessed country code eventually guesses wrong, and a rejected create means a
    # family cannot onboard at all. One extra field for the parent is the cheaper
    # failure.
    it "omits an unverified phone number, because an unverified number is a claim" do
      guardian.update!(phone_number: "+12128675309", phone_number_verified: false)

      expect(created_params[:individual]).not_to have_key(:phone)
    end

    # Two writes on purpose: User#on_phone_number_update clears
    # phone_number_verified whenever the number changes, so setting both in one
    # update silently leaves it unverified.
    def verify_phone!(number)
      guardian.update!(phone_number: number)
      guardian.update!(phone_number_verified: true)
      guardian.reload
    end

    it "omits a verified phone number that is not unambiguous E.164" do
      verify_phone!("(212) 867-5309")

      expect(created_params[:individual]).not_to have_key(:phone)
    end

    it "sends a verified phone number that already is E.164" do
      verify_phone!("+12128675309")

      expect(created_params[:individual][:phone]).to eq("+12128675309")
    end

    # A guardian invited by email exists before they have supplied anything.
    it "omits the dob entirely when the guardian has no birthday on file" do
      no_dob = create(:user, full_name: "Sam Reyes", email: "sam@example.com", birthday: nil)

      individual = params_for(event: venture, user: no_dob)[:individual]

      expect(individual).not_to have_key(:dob)
      expect(individual[:first_name]).to eq("Sam")
    end
  end

  describe "institutional accounts" do
    # business_type is "company" there — the account holder is the school, and its
    # representative fields are a different shape. An individual block on a company
    # account is not a smaller version of this, it is wrong.
    it "sends no individual block at all" do
      school = create(:event, plan_type: Event::Plan::School)
      manager = create(:user, birthday: 40.years.ago.to_date)

      params = params_for(event: school, user: manager)

      expect(params[:business_type]).to eq("company")
      expect(params).not_to have_key(:individual)
    end
  end
end
