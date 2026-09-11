# frozen_string_literal: true

require "rails_helper"

# Fuime: the storefront is the one page shown to the public and to a demo
# audience, logged out, on a phone. These specs RENDER it — a template error
# here is invisible to a controller spec that only checks status codes, and
# would surface for the first time in front of an audience.
RSpec.describe Fuime::StorefrontsController, type: :controller do
  render_views

  # The name is pinned, not left to Faker, because several examples assert on
  # `include(event.name)` against RENDERED HTML. A Faker name containing an
  # apostrophe or ampersand ("O'Brien & Sons") is escaped to `O&#39;Brien &amp;
  # Sons` in the output and the match fails — a seed-dependent flake that passes on
  # most runs and fails on some. "Maya Prints" contains nothing ERB will escape.
  let(:event) { create(:event, name: "Maya Prints", slug: "mayas-prints", is_public: true) }

  # A venture can only be paid once its guardian has finished Stripe setup — the
  # view gates the whole pay form on `@accepts_payments`, because rendering it
  # without an account puts a dead "Pay" button on a public URL a teenager has
  # shared with real customers.
  #
  # These specs predate that gate and were written when the storefront always
  # rendered the form (the pooled-account model, where Fuime's own balance was
  # always available). Four of them broke silently when the gate landed. The
  # connected account belongs here rather than in each example because "this
  # venture can take money" is the precondition for a storefront being worth
  # rendering at all; the un-set-up branch is covered explicitly below.
  let!(:connected_account) { create(:stripe_connected_account, :ready, event:) }

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

      # Asserted in the format the view actually renders. It reads
      # `event.plan.revenue_fee` through `number_to_percentage(precision: 1)` — so
      # "4.0%", not "4%" — because the constant this replaced ignored the plan
      # entirely and advertised 4% to a Founders-plan venture that pays nothing.
      # Derived rather than hardcoded so a plan change cannot leave this passing
      # against the wrong number.
      expected = ActiveSupport::NumberHelper.number_to_percentage(
        event.plan.revenue_fee * 100, precision: 1
      )

      expect(response.body).to include(expected)
    end

    # The other side of the gate, which nothing pinned before. A storefront whose
    # guardian has not finished setup must say so rather than showing a button that
    # the checkout endpoint would refuse.
    context "when the guardian has not finished payment setup" do
      let!(:connected_account) { create(:stripe_connected_account, :incomplete, event:) }

      it "explains the venture cannot be paid instead of rendering a dead form" do
        get :show, params: { slug: event.slug }

        expect(response).to have_http_status(:ok)
        # Plain apostrophe: this sentence is static template text, so ERB does not
        # HTML-escape it. Only `<%= %>` output becomes `&#39;` — which is why the
        # test-mode examples above assert the entity and this one does not.
        expect(response.body).to include("isn't set up to take payments yet")
        expect(response.body).not_to include(fuime_storefront_pay_path(slug: event.slug))
      end
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

    it "offers Fuime checkout as seller of record" do
      get :show, params: { slug: event.slug }

      expect(response.body).to include("Pay #{event.name}")
      expect(response.body).to include("Pay via Fuime checkout")
      expect(response.body).to include("Ninth Street Labs, LLC")
      expect(response.body).not_to include("a real card will not be charged")
      expect(response.body).not_to include("4242 4242 4242 4242")
    end

    it "confirms a received payment without calling it a trial charge" do
      get :show, params: { slug: event.slug, paid: 1 }

      expect(response.body).to include("Payment received")
      expect(response.body).not_to include("test payment")
    end
  end

end
