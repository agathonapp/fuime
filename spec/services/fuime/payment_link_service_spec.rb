# frozen_string_literal: true

require "rails_helper"

# Fuime: the shape of the one Stripe call every sale goes through.
#
# Nothing pinned this before. The merchant-of-record session is the single place
# where the legal structure becomes an API call, and the three things that make
# it lawful are all ABSENCES — no `stripe_account:`, no `application_fee_amount`,
# the fee carried as metadata the ledger later reads. Absences are exactly what a
# refactor removes without noticing, because nothing fails when they come back.
#
# ── The descriptor ──────────────────────────────────────────────────────────
#
# `statement_descriptor_suffix` used to be `"FUIME #{name}"[0..21].strip` — no
# character filter and no prefix budget. Stripe forbids `' " < > \ *` in a
# suffix, so a venture called "Maya's Bakes" raised Stripe::InvalidRequestError
# on every checkout, which `Fuime::CheckoutsController` turns into "We couldn't
# start that payment. Please try again." That venture could never take a payment
# and was told to retry indefinitely. An apostrophe in a business name is
# ordinary; this is the first name a teenager reaches for.
RSpec.describe Fuime::PaymentLinkService, :merchant_of_record do
  # `business_category` is what `Fuime::OperatorEligibility` gates on, and the
  # factory leaves it nil so that the gate itself is testable elsewhere. A
  # venture that cannot sell never reaches the Stripe call this file is about.
  let(:event) { create(:event, name: "Nova Dog Walking", business_category: "services") }

  subject(:service) do
    described_class.new(event:, amount_cents: 3_500, description: "One walk")
  end

  def create_session!(svc = service)
    svc.create_mor_checkout_session(
      success_url: "https://fuime.com/thanks",
      cancel_url: "https://fuime.com/pay/nova"
    )
  end

  # Captures the params Stripe would have received, without reaching Stripe.
  def captured_params
    captured = nil
    allow(Stripe::Checkout::Session).to receive(:create) do |params, _opts|
      captured = params
      Stripe::Checkout::Session.construct_from(id: "cs_test_pinned", url: "https://checkout.stripe.test/cs_test_pinned")
    end
    yield
    captured
  end

  describe "the statement descriptor" do
    # The bug, stated as the buyer's experience rather than as a regex.
    it "lets a venture with an apostrophe in its name take a payment" do
      event.update!(name: "Maya's Bakes")

      params = captured_params { create_session! }
      suffix = params.dig(:payment_intent_data, :statement_descriptor_suffix)

      expect(suffix).not_to include("'")
      expect(suffix).to eq("Mayas Bakes")
    end

    # Every character Stripe documents as forbidden in a suffix, in one name.
    it "strips everything Stripe rejects" do
      event.update!(name: %(A'B"C<D>E\\F*G))

      params = captured_params { create_session! }
      suffix = params.dig(:payment_intent_data, :statement_descriptor_suffix)

      expect(suffix).to match(/\A[a-zA-Z0-9\-_ ]*\z/)
    end

    # The account's own prefix is prepended by Stripe and counts against the 22.
    # The old code spent six of the fifteen remaining characters re-stating the
    # brand, so the buyer read "Fuime* FUIME Nova D".
    it "does not repeat the brand the account prefix already supplies" do
      params = captured_params { create_session! }
      suffix = params.dig(:payment_intent_data, :statement_descriptor_suffix)

      expect(suffix).not_to match(/fuime/i)
      expect(suffix.length).to be <= StripeService::StatementDescriptor::SUFFIX_CHAR_LIMIT
    end

    it "falls back to the brand rather than sending an empty suffix" do
      event.update!(name: "日本語だけ")

      params = captured_params { create_session! }

      expect(params.dig(:payment_intent_data, :statement_descriptor_suffix)).to eq("Fuime")
    end

    it "prefers the short name when the venture set one" do
      event.update!(name: "Nova Dog Walking and Sitting", short_name: "Nova Walks")

      params = captured_params { create_session! }

      expect(params.dig(:payment_intent_data, :statement_descriptor_suffix)).to eq("Nova Walks")
    end
  end

  # These three are the merchant-of-record structure itself. If any of them
  # changes, Fuime is doing something other than selling its own goods, and L1
  # is back in play.
  describe "what makes the session merchant-of-record" do
    it "is not created on a connected account" do
      captured = nil
      opts = nil
      allow(Stripe::Checkout::Session).to receive(:create) do |params, options|
        captured = params
        opts = options
        Stripe::Checkout::Session.construct_from(id: "cs_test_pinned")
      end

      create_session!

      expect(captured).not_to have_key(:stripe_account)
      expect(opts).not_to have_key(:stripe_account)
    end

    it "takes no application fee" do
      params = captured_params { create_session! }

      expect(params).not_to have_key(:application_fee_amount)
      expect(params[:payment_intent_data]).not_to have_key(:application_fee_amount)
    end

    # The ledger deducts what this stamps. A number computed twice is a number
    # that eventually disagrees with itself, so the webhook reads the metadata
    # rather than recomputing (Fuime::PaymentWebhookHandler).
    it "stamps the fee at exactly the value the ledger will deduct" do
      params = captured_params { create_session! }

      expect(params[:metadata][:fuime_fee_cents]).to eq(event.fuime_fee_cents_on(3_500))
      expect(params.dig(:payment_intent_data, :metadata, :fuime_fee_cents))
        .to eq(params[:metadata][:fuime_fee_cents])
    end

    it "names the venture so the webhook can find it" do
      params = captured_params { create_session! }

      expect(params[:metadata][:fuime_event_id]).to eq(event.id)
      expect(params.dig(:payment_intent_data, :metadata, :fuime_event_id)).to eq(event.id)
    end

    # Under MoR the buyer's counterparty is the legal entity, not the teenager.
    # A product description naming the venture as the seller would contradict
    # the terms of sale the buyer accepted.
    it "names the legal entity as the seller on the line item" do
      params = captured_params { create_session! }

      expect(params[:line_items].first.dig(:price_data, :product_data, :description))
        .to include(Rails.configuration.constants.legal_entity_name)
    end
  end

  describe "when the venture may not sell" do
    it "refuses rather than creating a session" do
      allow(event).to receive(:selling_blockers).and_return(["Fuime has not reviewed this business yet"])

      expect(Stripe::Checkout::Session).not_to receive(:create)
      expect { create_session! }.to raise_error(described_class::NotAcceptingPayments, /not been reviewed|not reviewed|not eligible/i)
    end
  end
end
