# frozen_string_literal: true

require "rails_helper"

RSpec.describe Admin::PlaygroundController, type: :controller do
  include SessionSupport

  let(:admin) { create(:user, :make_admin) }

  before { create_session(admin, verified: true) }

  describe "GET #show" do
    it "renders while Stripe is live and does not call DemoSandbox.guard_enabled!" do
      allow(StripeService).to receive(:live?).and_return(true)
      allow(Fuime::DemoSandbox).to receive(:guard_enabled!)

      get :show

      expect(response).to have_http_status(:ok)
      expect(Fuime::DemoSandbox).not_to have_received(:guard_enabled!)
    end
  end
end
