# frozen_string_literal: true

require "rails_helper"

# Fuime: the storefront must not promise a ledger the venture has not published.
#
# ── What a customer saw ────────────────────────────────────────────────────
#
# Every storefront rendered a "Public Ledger" card, unconditionally, saying
# "This business's finances are transparent. You can view their complete
# transaction history and see exactly how funds are being used" — with a
# "View full ledger" link.
#
# `publishes_ledger` defaults to FALSE (AddPublishesLedgerToEvents), so for the
# ordinary teen venture both halves were wrong at once. The claim was untrue
# about a child's finances, and the link went to `event_path`, whose policy is
# `publishes_ledger? || auditor_or_reader?` — so the customer who followed it,
# on the one public page Fuime ever shows them, was bounced to a login screen.
RSpec.describe "the storefront's public-ledger card", type: :request do
  let(:venture) do
    create(:event, business_category: "services", is_public: true, name: "Nova Dog Walking").tap do |e|
      e.update!(operator_vetting_status: "approved")
    end
  end

  let!(:offer) { create(:fuime_offer, event: venture, name: "Dog walk", price_cents: 1_500).tap(&:publish!) }

  context "when the venture has not published its ledger (the default)" do
    it "does not claim the finances are transparent" do
      get fuime_storefront_path(slug: venture.slug)

      expect(response).to have_http_status(:ok)
      expect(venture.reload.publishes_ledger?).to be(false)
      expect(response.body).not_to include("Public Ledger")
      expect(response.body).not_to include("finances are transparent")
    end

    # The half that made it a broken link and not only a wrong sentence.
    it "does not offer a link a customer would be refused at" do
      get fuime_storefront_path(slug: venture.slug)
      expect(response.body).not_to include("View full ledger")

      get event_path(venture)
      expect(response).not_to have_http_status(:ok)
    end
  end

  context "when the venture has chosen to publish its ledger" do
    before { venture.update!(publishes_ledger: true) }

    it "shows the card, because now the claim is true" do
      get fuime_storefront_path(slug: venture.slug)

      expect(response.body).to include("Public Ledger")
      expect(response.body).to include("View full ledger")
    end

    it "and the link actually resolves for a stranger" do
      get event_path(venture)

      expect(response).to have_http_status(:ok)
    end
  end
end
