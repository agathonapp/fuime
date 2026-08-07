# frozen_string_literal: true

require "rails_helper"

# Fuime: the storefront's "money in" entry point.
#
# `PaymentLinkService` and `PaymentWebhookHandler` both existed, but nothing
# called the service — the storefront Pay button was hardcoded `disabled`, so
# no payment could be started at all (PRODUCTION_READINESS.md §2.1).
#
# This is a public, unauthenticated endpoint that talks to Stripe and writes to
# a child's business ledger, so the guards below matter more than usual.
RSpec.describe Fuime::CheckoutsController, type: :controller do
  let(:event) { create(:event, slug: "mayas-prints", is_public: true) }

  # The controller refuses at `event.accepts_payments?` before it ever reaches the
  # service, so stubbing Fuime::PaymentLinkService is not enough to exercise the
  # happy path — the venture needs a guardian-owned Stripe account that Stripe is
  # willing to charge on.
  #
  # These specs were written against the pooled-account model, where Fuime's own
  # balance was always available and no such precondition existed. Five of them
  # broke silently when the guard landed with Stripe Connect. The refusal branch is
  # covered explicitly below.
  let!(:connected_account) { create(:stripe_connected_account, :ready, event:) }

  let(:stripe_session) { double("Stripe::Checkout::Session", url: "https://checkout.stripe.com/c/pay/cs_test_123") }

  def stub_checkout
    service = instance_double(Fuime::PaymentLinkService, create_checkout_session: stripe_session)
    allow(Fuime::PaymentLinkService).to receive(:new).and_return(service)
    service
  end

  describe "POST #create" do
    it "starts a Stripe Checkout session and redirects the payer to it" do
      service = stub_checkout

      post :create, params: { slug: event.slug, amount: "25.00", description: "Custom print" }

      expect(Fuime::PaymentLinkService).to have_received(:new).with(
        event:, amount_cents: 2500, description: "Custom print"
      )
      expect(service).to have_received(:create_checkout_session)
      expect(response).to redirect_to("https://checkout.stripe.com/c/pay/cs_test_123")
    end

    it "accepts amounts written with a dollar sign and separators" do
      stub_checkout

      post :create, params: { slug: event.slug, amount: "$1,250.50" }

      expect(Fuime::PaymentLinkService).to have_received(:new).with(
        hash_including(amount_cents: 125_050)
      )
    end

    it "falls back to a default description when none is given" do
      stub_checkout

      post :create, params: { slug: event.slug, amount: "10" }

      expect(Fuime::PaymentLinkService).to have_received(:new).with(
        hash_including(description: "Payment to #{event.name}")
      )
    end

    context "guards" do
      # The guard that makes the storefront honest under the connected-account
      # model: before it, `accepts_payments?` defaulted to true and every activated
      # venture presented a working form with nowhere for the money to go.
      it "refuses a venture whose guardian has not finished Stripe setup" do
        connected_account.update!(charges_enabled: false, capabilities: {})
        allow(Fuime::PaymentLinkService).to receive(:new)

        post :create, params: { slug: event.slug, amount: "25" }

        expect(Fuime::PaymentLinkService).not_to have_received(:new)
        expect(response).to redirect_to(fuime_storefront_path(slug: event.slug))
        expect(flash[:alert]).to match(/isn't set up to accept payments/i)
      end

      it "refuses a venture with no Stripe account at all" do
        connected_account.destroy!
        allow(Fuime::PaymentLinkService).to receive(:new)

        post :create, params: { slug: event.slug, amount: "25" }

        expect(Fuime::PaymentLinkService).not_to have_received(:new)
      end

      it "refuses a business that has not published a storefront" do
        private_event = create(:event, slug: "private-biz", is_public: false)
        allow(Fuime::PaymentLinkService).to receive(:new)

        post :create, params: { slug: private_event.slug, amount: "25" }

        expect(Fuime::PaymentLinkService).not_to have_received(:new)
        expect(response).to redirect_to(root_path)
      end

      it "rejects an amount below the minimum" do
        allow(Fuime::PaymentLinkService).to receive(:new)

        post :create, params: { slug: event.slug, amount: "0.50" }

        expect(Fuime::PaymentLinkService).not_to have_received(:new)
        expect(response).to redirect_to(fuime_storefront_path(slug: event.slug))
      end

      it "rejects an amount above the maximum" do
        allow(Fuime::PaymentLinkService).to receive(:new)

        post :create, params: { slug: event.slug, amount: "10001" }

        expect(Fuime::PaymentLinkService).not_to have_received(:new)
        expect(response).to redirect_to(fuime_storefront_path(slug: event.slug))
      end

      it "rejects a non-numeric amount rather than raising" do
        allow(Fuime::PaymentLinkService).to receive(:new)

        expect {
          post :create, params: { slug: event.slug, amount: "abc" }
        }.not_to raise_error

        expect(Fuime::PaymentLinkService).not_to have_received(:new)
      end

      # The description is typed by an anonymous payer and ends up in the ledger
      # memo a teenager reads.
      it "truncates an overlong description" do
        stub_checkout

        post :create, params: { slug: event.slug, amount: "25", description: "x" * 500 }

        expect(Fuime::PaymentLinkService).to have_received(:new).with(
          hash_including(description: "#{'x' * 117}...")
        )
      end

      it "strips control characters from the description" do
        stub_checkout

        post :create, params: { slug: event.slug, amount: "25", description: "Custom\u0000\u0007 print" }

        expect(Fuime::PaymentLinkService).to have_received(:new).with(
          hash_including(description: "Custom print")
        )
      end

      it "does not leak a Stripe error to the payer" do
        service = instance_double(Fuime::PaymentLinkService)
        allow(service).to receive(:create_checkout_session)
          .and_raise(Stripe::StripeError.new("No such price: sk_live leaked"))
        allow(Fuime::PaymentLinkService).to receive(:new).and_return(service)

        post :create, params: { slug: event.slug, amount: "25" }

        expect(response).to redirect_to(fuime_storefront_path(slug: event.slug))
        expect(flash[:alert]).not_to include("sk_live")
      end
    end
  end

end
