# frozen_string_literal: true

require "rails_helper"

# Fuime: the storefront is the one page shown to the public and to a demo
# audience, logged out, on a phone. These specs RENDER it — a template error
# here is invisible to a controller spec that only checks status codes, and
# would surface for the first time in front of an audience.
RSpec.describe Fuime::StorefrontsController, type: :controller do
  render_views

  let(:event) { create(:event, slug: "mayas-prints", is_public: true) }

  describe "GET #show" do
    it "renders the storefront to a logged-out visitor" do
      get :show, params: { slug: event.slug }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(event.name)
    end

    it "renders the pay form wired to the checkout endpoint" do
      get :show, params: { slug: event.slug }

      expect(response.body).to include(fuime_storefront_pay_path(slug: event.slug))
      # The button used to be hardcoded `disabled` with "coming soon" copy.
      expect(response.body).not_to include("Payment links coming soon")
    end

    it "states the platform fee rather than hiding it from the payer" do
      get :show, params: { slug: event.slug }

      expect(response.body).to include("#{Fuime::PaymentLinkService::FUIME_PLATFORM_FEE_PERCENT}%")
    end

    it "confirms the payment on return from Stripe" do
      get :show, params: { slug: event.slug, paid: 1 }

      expect(response.body).to include("Payment received")
    end

    it "redirects when the business has not published a storefront" do
      private_event = create(:event, slug: "private-biz", is_public: false)

      get :show, params: { slug: private_event.slug }

      expect(response).to redirect_to(root_path)
    end

    # Fuime's storefront is deliberately narrower than HCB's transparency page,
    # because the subject is a child. See the controller's comment.
    context "protecting a minor's data" do
      it "does not publish the account balance or a tax figure" do
        get :show, params: { slug: event.slug }

        # Not a bare /balance/ match: the shared layout uses the `text-balance`
        # CSS class, which would make this pass or fail for unrelated reasons.
        expect(response.body).not_to match(/Balance:|Current balance|account balance/i)
        expect(response.body).not_to match(/balance["'\s]*>\s*\$/i)
        # The tax estimate is the business's private figure, never public.
        expect(response.body).not_to match(/self-employment|\$400/i)
      end

      it "does not show the owner's name when the owner is a minor" do
        # `point_of_contact` must be an admin, so set the owner directly rather
        # than through the factory's validated association.
        teen = create(:user, :minor)
        minor_event = create(:event, slug: "teen-biz", is_public: true)
        minor_event.update_column(:point_of_contact_id, teen.id)

        get :show, params: { slug: minor_event.slug }

        expect(response.body).not_to include(teen.full_name)
      end
    end
  end

end
