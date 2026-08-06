# frozen_string_literal: true

require "rails_helper"

# Fuime: the direct-to-consumer journey — one individual kid, one parent, no
# school, no LLC, no EIN — walked end to end through the real services.
#
# This spec is also the executable answer to a product question: "can
# individuals, non-businesses, use this?" Yes, and this is the mechanism — a
# kid who sells anything IS a business under US law (a sole proprietorship
# exists the moment revenue activity does; no registration, no EIN — see
# docs/fuime/LEGAL_RESEARCH.md §1), and Stripe's business_type for exactly
# that person is "individual". What Fuime deliberately does NOT serve is pure
# consumer money with no revenue activity (allowance tracking, personal
# spending cards): that is a consumer fintech program requiring a partner
# bank, the category LEGAL_RESEARCH priced out, and Stripe's Connect and
# Celtic's card terms both prohibit personal use besides.
#
# If any step here breaks, the individuals funnel is broken — this is the
# canary for the non-school half of the platform.
RSpec.describe "the D2C individual golden path", type: :model do
  it "takes a kid with no LLC from application to payment-ready venture" do
    admin = create(:user, :make_admin, birthday: 35.years.ago.to_date)
    teen = create(:user, birthday: 15.years.ago.to_date, verified: true)
    guardian = create(:user, birthday: 40.years.ago.to_date, verified: true)

    # Step 1: the guardian relationship — the legal spine of the D2C path (L2).
    Guardianship.create!(guardian:, minor: teen, status: :active)
    expect(teen.needs_guardian?).to be(false)

    # Step 2: the teen applies. Note what is absent: no entity, no EIN — the
    # application asks who they are and what they sell.
    application = create(:event_application, user: teen, teen_led: true,
                                             name: "Maya's Sticker Studio")
    application.update!(aasm_state: :approved)

    # Step 3: activation creates the venture and seats the teen as its
    # signee-manager through the same invite machinery the UI uses.
    application.activate_event!(risk_level: 0, point_of_contact: admin)
    venture = application.reload.event
    expect(venture).to be_present

    position = venture.organizer_positions.find_by(user: teen)
    expect(position).to be_present, "teen never got their position on the venture"
    expect(position.role).to eq("manager")

    # Step 4: the guardianship control resolves correctly in every direction.
    expect(EventPolicy.new(teen, venture).send(:permitted_to_operate_business?)).to be(true)
    expect(EventPolicy.new(guardian, venture).setup_payments?).to be(true),
                                                                  "the guardian must be able to connect Stripe"
    expect(EventPolicy.new(teen, venture).setup_payments?).to be(false),
                                                              "the teen must NOT be able to supply identity details"

    # Step 5: the Stripe account this journey produces is an INDIVIDUAL (sole
    # prop) account owned by the guardian — the codified answer to "can a
    # non-business use this".
    service = Fuime::ConnectOnboardingService.new(event: venture, guardian:)
    params = service.send(:account_params)
    expect(params[:business_type]).to eq("individual")
    expect(params[:email]).to eq(guardian.email)
    expect(params.dig(:settings, :payouts, :schedule, :interval)).to eq("manual"),
                                                                     "manual payouts are what make guardian approval real"
  end

  it "parks a teen with no guardian at the invite step, not inside the product" do
    teen = create(:user, birthday: 15.years.ago.to_date, verified: true)

    expect(teen.needs_guardian?).to be(true)
    expect(teen.institutionally_vouched_for?).to be(false)
    # The record-scoped gate that keeps an unbacked minor from operating
    # anything, anywhere, until a real adult accepts.
    expect(EventPolicy.new(teen, create(:event)).send(:permitted_to_operate_business?)).to be(false)
  end
end
