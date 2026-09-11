# frozen_string_literal: true

require "rails_helper"

RSpec.describe Admin::PlaygroundController, type: :controller do
  include SessionSupport

  let(:admin) { create(:user, :make_admin) }
  let(:teen) { create(:user, full_name: "Maya Okafor", birthday: 16.years.ago.to_date, email: Fuime::Playground::TEEN_EMAIL) }
  let(:event) { create(:event, :demo_mode, slug: Fuime::Playground::SLUG, is_public: true) }
  let(:sam) { create(:user, :unknown_age, full_name: nil, email: Fuime::Playground::NEW_FOUNDER_EMAIL) }

  let(:playground) do
    instance_double(
      Fuime::Playground,
      seed!: { event:, teen:, guardian: create(:user), new_founder: sam, warnings: [] },
      reset_new_founder!: sam,
      status: {
        slug: Fuime::Playground::SLUG, event: nil, teen: nil, guardian: nil, new_founder: nil,
        new_founder_fresh: false, offers: [], published_offer: nil, published: 0, ledger_lines: 0,
        last_seeded_at: nil, stripe_live: true, warnings: []
      }
    )
  end

  before do
    create_session(admin, verified: true)
    allow(Fuime::Playground).to receive(:new).and_return(playground)
  end

  describe "GET #show" do
    it "renders while Stripe is live and does not call DemoSandbox.guard_enabled!" do
      allow(StripeService).to receive(:live?).and_return(true)
      allow(Fuime::DemoSandbox).to receive(:guard_enabled!)

      get :show

      expect(response).to have_http_status(:ok)
      expect(Fuime::DemoSandbox).not_to have_received(:guard_enabled!)
    end
  end

  # Reset + Become in one POST. The session it leaves behind is the same
  # impersonated session UsersController#impersonate creates.
  describe "POST #start" do
    it "reseeds, impersonates the teen and lands on the venture" do
      post :start

      expect(playground).to have_received(:seed!)
      expect(response).to redirect_to(event_path(event))
      session = current_session!
      expect(session.user).to eq(teen)
      expect(session).to be_impersonated
      expect(session.impersonated_by).to eq(admin)
    end
  end

  describe "POST #fresh_founder" do
    it "resets the new founder, impersonates them and lands on the root (which sends them to onboarding)" do
      post :fresh_founder

      expect(playground).to have_received(:reset_new_founder!)
      expect(playground).not_to have_received(:seed!)
      expect(response).to redirect_to(root_path)
      session = current_session!
      expect(session.user).to eq(sam)
      expect(session).to be_impersonated
    end
  end

  context "when signed in as a non-admin" do
    let(:admin) { create(:user) }

    it "refuses every action" do
      get :show
      expect(response).not_to have_http_status(:ok)

      post :start
      expect(playground).not_to have_received(:seed!)

      post :fresh_founder
      expect(playground).not_to have_received(:reset_new_founder!)
    end
  end
end
