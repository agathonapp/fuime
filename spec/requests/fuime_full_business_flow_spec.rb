# frozen_string_literal: true

require "rails_helper"

# Fuime: the whole thing, end to end — a teenager with nothing to a business
# taking money for a named thing at a price they set.
#
# `d2c_golden_path_spec.rb` already covers application → venture → the Stripe
# account shape. This picks up where that stops and drives the halves built
# since: the business-type fork, offers, the storefront a customer actually sees,
# a purchase, the ledger, and the payout run.
#
# Written as one long example on purpose. Each step depends on the last, and the
# value is in the *sequence* — a suite of isolated units all passing while the
# journey is broken end to end is the failure mode this exists to catch.
#
# ── What this does NOT prove ────────────────────────────────────────────────
#
# Stripe. `PaymentLinkService` is stubbed at the boundary, so this asserts Fuime
# asks for the right charge, not that Stripe accepts it. The only thing ever
# exercised against real Stripe is the direct-charge shape (2026-08-14,
# EMBEDDED_CONNECT.md §7); every webhook path is still documentation-derived.
# Do not read a green run here as "the money works".
RSpec.describe "the full business flow", type: :request do
  let(:admin) { create(:user, :make_admin, birthday: 35.years.ago.to_date, verified: true) }
  let(:teen) { create(:user, birthday: 16.years.ago.to_date, verified: true) }
  let(:guardian) { create(:user, birthday: 40.years.ago.to_date, verified: true) }

  let(:payment_link) do
    instance_double(Fuime::PaymentLinkService,
                    create_checkout_session: double(url: "https://checkout.stripe.test/s"))
  end

  it "takes a teenager from signup to a paid sale and a payout run" do
    # ── 1. The guardian relationship, which everything else rests on (L2) ────
    Guardianship.create!(guardian:, minor: teen, status: :active)
    expect(teen.needs_guardian?).to be(false)

    # ── 2. The application, including the business-type fork ────────────────
    application = create(:event_application, user: teen, teen_led: true,
                                             name: "Sunset Lawn Care",
                                             description: "I mow lawns in my neighbourhood",
                                             starting_point: "have_idea",
                                             service_type: "lawn_and_garden")

    expect(application.business_category).to eq("services"),
                                             "the category has to be derived, or the venture is born unable to sell"
    expect(application.service.name).to eq("Lawn & garden")

    # ── 3. Activation creates the venture and seats the teen ────────────────
    application.update!(aasm_state: :approved)
    application.activate_event!(risk_level: 0, point_of_contact: admin)
    venture = application.reload.event

    expect(venture).to be_present
    expect(venture.business_category).to eq("services"),
                                         "the category must survive the trip, or vetting blocks a venture nobody mispriced"
    expect(venture.organizer_positions.find_by(user: teen)&.role).to eq("manager")

    # ── 4. Vetting binds before anything can be sold ────────────────────────
    #
    # The column defaults to unvetted, so this is the state every real venture
    # starts in. A human approving each operator is the compensating control for
    # letting minors sell at all.
    venture.update!(operator_vetting_status: :unvetted)
    expect(venture.accepts_payments?).to be(false)

    venture.record_vetting_decision!(status: "approved", by: admin, notes: "Lawn care, 16, services only.")
    expect(venture.reload.operator_vetting_approved?).to be(true)

    # Still cannot sell — vetting is necessary and not sufficient. Payment setup
    # is the guardian's job and has not happened.
    expect(venture.accepts_payments?).to be(false)

    # ── 5. The teen lists what they sell, at their own price ────────────────
    offer = venture.fuime_offers.create!(
      name: "Front and back lawn mow",
      description: "Includes edging. I bring my own mower.",
      unit_label: "per visit",
      price_cents: 35_00
    )

    expect(offer).to be_draft
    # Publishing is refused until the venture can actually take money — a
    # published offer is a public promise that a payment will work.
    expect(offer.publish!).to be(false)
    expect(offer.reload).to be_draft

    # ── 6. The guardian finishes payment setup ──────────────────────────────
    allow_any_instance_of(Event).to receive(:accepts_payments?).and_return(true)

    expect(offer.publish!).to be_truthy
    expect(offer.reload).to be_published

    # ── 7. A customer sees the storefront ───────────────────────────────────
    venture.update!(is_public: true)
    get "/b/#{venture.slug}"

    body = CGI.unescapeHTML(response.body)
    expect(response).to have_http_status(:ok)
    expect(body).to include("Front and back lawn mow")
    expect(body).to include("$35.00 per visit")

    # The guarantee that survives every rewording of the storefront: nothing on a
    # public page names an operator or states their age.
    venture.selling_blockers.each do |blocker|
      expect(body).not_to include(blocker)
    end
    expect(body).not_to include(teen.email)

    # ── 8. …and buys it, at the price the operator set ──────────────────────
    allow(Fuime::PaymentLinkService).to receive(:new).and_return(payment_link)
    expect(Fuime::PaymentLinkService).to receive(:new)
      .with(hash_including(amount_cents: 35_00, description: offer.payment_description))
      .and_return(payment_link)

    # …and a tampered amount alongside the offer changes nothing.
    post "/b/#{venture.slug}/pay", params: { offer_id: offer.id, amount: "1.00" }
    expect(response).to have_http_status(:redirect)

    # ── 9. The sale reaches the ledger ──────────────────────────────────────
    #
    # Posted directly rather than driven through the webhook: no webhook path has
    # ever run against Stripe (see the header), so driving one here would assert
    # a fiction. What is being checked is that a settled sale is classified,
    # explained and payable — the part that is Fuime's own code.
    create(:canonical_transaction, event: venture, amount_cents: 35_00,
                                   date: 30.days.ago.to_date,
                                   memo: "Payment from a customer [fuime_pi_e2e]")
    create(:canonical_transaction, event: venture, amount_cents: -2_45,
                                   date: 30.days.ago.to_date,
                                   memo: "Fuime platform fee [fuime_fee_pi_e2e]")

    payables = Fuime::PayablesLedger.new(event: venture.reload)
    expect(payables.gross_sales_cents).to eq(35_00)
    expect(payables.fuime_fee_cents).to eq(2_45)
    expect(payables.net_payable_cents).to eq(32_55)

    # The legal framing, which is the product: an amount owed on a stated date,
    # never a balance held on deposit (L1/L5).
    expect(payables.owed_sentence).to match(/Fuime owes you/)
    expect(payables.disclosure).to match(/not a bank balance/)
    expect(payables.disclosure).to match(/not a deposit/)

    # ── 10. …and a payout run picks it up ───────────────────────────────────
    with_merchant_of_record do
      batch = Fuime::PayoutBatchService.new.generate!(period_end: Date.current)
      line = batch.payout_requests.find_by(event: venture)

      expect(line).to be_present, "a settled, aged sale must produce a payout line"
      # 10% rolling reserve on $35 of trailing volume.
      expect(line.reserve_held_cents).to eq(3_50)
      expect(line.amount_cents).to eq(29_05)
      expect(line.requested_by).to be_nil, "nobody asks for a batch line — the schedule generates it"

      # Approval releases; only marking paid moves the ledger.
      Fuime::PayoutBatchService.new.approve!(batch:, approver: admin)
      expect { Fuime::PayoutBatchService.new.mark_paid!(batch:, paid_by: admin) }
        .to change { Fuime::PayablesLedger.new(event: venture.reload).net_payable_cents }
        .by(-29_05)
    end
  end

  # `:merchant_of_record` is an example-level tag and this is one example, so the
  # flag is flipped inline for the payout half — the rest of the journey has to
  # run under the shipping posture (Connect), which is where a real teenager is.
  def with_merchant_of_record
    allow(Fuime::Features).to receive(:merchant_of_record?).and_return(true)
    yield
  end
end
