# frozen_string_literal: true

require "rails_helper"

# Fuime: under merchant-of-record, the Connect screens must be gone — not just
# hidden from the nav.
#
# ── The bug this file exists for ────────────────────────────────────────────
#
# PR #68 hid the "Payments" nav item under MoR. That was right and it was half
# the job: every action on Fuime::PaymentSetupsController stayed reachable at its
# URL, and the payouts page still linked to it. So an operator on a
# merchant-of-record venture could land on a screen reading:
#
#   "Before <venture> can accept money, a parent or guardian needs to set up a
#    payment account; money settles to their bank, not to Fuime."
#
# Under MoR every clause of that is false — there is no account to open, the
# money settles to FUIME as the seller, and no parent can do anything about it.
# A page that cannot be reached from the nav but can be reached from a link is
# still a page people reach, which is the general lesson worth keeping.
#
# The root cause was the same in all three places: reading `payment_account`
# (the Connect account) to decide what to say, when under MoR that association is
# nil forever by design.
RSpec.describe "the Connect screens under merchant-of-record", type: :request do
  def login_as!(user)
    post logins_path, params: { email: user.email, login: { purpose: "" } }
    login = Login.order(:id).last
    post email_login_path(login)
    code = LoginCode.active.where(user:).order(:id).last
    post complete_login_path(login), params: { method: "email", login_code: code.code }
    expect(User::Session.where(user:)).to exist, "login failed for #{user.email}"
  end

  let(:guardian) { create(:user, birthday: 40.years.ago.to_date, verified: true) }
  let(:teen) { create(:user, :minor, birthday: 16.years.ago.to_date, verified: true) }

  let(:event) do
    create(:event, business_category: "services", is_public: true, name: "Sunset Lawn Care").tap do |e|
      e.update!(operator_vetting_status: :approved, operator_vetted_at: Time.current)
      create(:organizer_position, event: e, user: teen)
    end
  end

  describe "the payment setup screen", :merchant_of_record do
    before { login_as!(teen) }

    it "is not reachable — it sends the operator to the payout destination instead" do
      get fuime_payment_setup_path(event_slug: event.slug)

      expect(response).to redirect_to(fuime_payout_method_path(event_slug: event.slug))
    end

    # Every action, not just #show. The one an operator actually clicks from a
    # stale link is as likely to be the onboarding starter as the status page.
    it "is not reachable by starting onboarding either" do
      get new_fuime_payment_setup_path(event_slug: event.slug)

      expect(response).to redirect_to(fuime_payout_method_path(event_slug: event.slug))
    end

    it "never renders the sentence that started this" do
      get fuime_payment_setup_path(event_slug: event.slug)
      follow_redirect!

      expect(response.body).not_to include("needs to set up a payment")
      expect(response.body).not_to include("settles to their bank")
    end
  end

  describe "the payouts page" do
    before { login_as!(teen) }

    context "under merchant-of-record", :merchant_of_record do
      it "names the real blocker instead of asking for a Stripe account" do
        get fuime_payouts_path(event_slug: event.slug)

        expect(response.body).to include("No payout destination set up yet")
        expect(response.body).not_to include("set up this venture's payment account")
      end

      it "points at the payout destination, not at Connect onboarding" do
        get fuime_payouts_path(event_slug: event.slug)

        expect(response.body).to include(fuime_payout_method_path(event_slug: event.slug))
      end

      it "also names the guardian, because money cannot move without one" do
        get fuime_payouts_path(event_slug: event.slug)

        expect(response.body).to include("parent or guardian")
        expect(response.body).to include(teen.name)
      end

      it "stops warning once the destination and the guardian are both there" do
        create(:fuime_payout_method, :verified, event:)
        create(:guardianship, :active, guardian:, minor: teen)

        get fuime_payouts_path(event_slug: event.slug)

        expect(response.body).not_to include("Money can't be sent out yet")
      end
    end

    # The Connect path is untouched: there the guardian really does own the Stripe
    # account, and a venture without one really is waiting on them.
    context "under Connect" do
      # A guardian, because under Connect a parentless minor cannot act on the
      # venture at all (User#permitted_to_operate_business?) and gets redirected
      # before the page renders — which would make this pass or fail for a reason
      # that has nothing to do with the copy being asserted.
      it "still asks for the payment account" do
        create(:guardianship, :active, guardian:, minor: teen)

        get fuime_payouts_path(event_slug: event.slug)

        expect(response.body).to include("payment account")
      end
    end
  end

  # The public one, and the worst of the three: it stated a reason, to strangers,
  # that was both false and about the wrong thing.
  describe "the public storefront", :merchant_of_record do
    let(:blocked_event) do
      create(:event, business_category: "services", is_public: true, name: "Sunset Lawn Care").tap do |e|
        e.update!(operator_vetting_status: :unvetted)
        create(:organizer_position, event: e, user: teen)
      end
    end

    it "does not tell a stranger a parent has not finished setting up" do
      get fuime_storefront_path(slug: blocked_event.slug)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("isn't taking payments right now")
      expect(response.body).not_to include("parent or guardian still needs")
    end

    # The reason under MoR is a vetting or eligibility decision about a child's
    # business. It is nobody's business but the operator's, their guardian's and
    # Fuime's, and these strings state children's ages.
    it "still says nothing about why" do
      get fuime_storefront_path(slug: blocked_event.slug)

      expect(response.body).not_to include("suspended")
      expect(response.body).not_to include("approved by Fuime")
      expect(response.body).not_to include(teen.name)
    end
  end

end
