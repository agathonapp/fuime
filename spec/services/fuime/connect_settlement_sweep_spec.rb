# frozen_string_literal: true

require "rails_helper"

# Fuime: the sweep that gives pending Connect ledger lines their settled twins.
# The gap it closes was found empirically: a real $25 test charge produced a
# pending line and a venture balance of $0.00, forever (docs/fuime/STRIPE_PASS.md).
RSpec.describe Fuime::ConnectSettlementSweep do
  let(:guardian) { create(:user, birthday: 40.years.ago.to_date) }
  let(:venture) { create(:event, name: "Sweep Venture") }

  let!(:account) do
    StripeConnectedAccount.create!(event: venture, owner: guardian,
                                   controller_profile: "cards_enabled",
                                   stripe_id: "acct_sweep_test")
  end

  def post_pending!(intent_id:, amount_cents:, memo:)
    Fuime::VentureLedger.new(event: venture).post!(
      key: Fuime::VentureLedger.payment_key(intent_id),
      amount_cents:, memo:, date: Time.current
    )
    CanonicalPendingTransaction.order(:id).last
  end

  def stub_intent(intent_id, status:)
    allow(Stripe::PaymentIntent).to receive(:retrieve)
      .with(hash_including(id: intent_id), anything)
      .and_return(
        Stripe::PaymentIntent.construct_from(
          id: intent_id,
          latest_charge: { id: "ch_#{intent_id}", balance_transaction: { id: "txn_1", status: } }
        )
      )
  end

  it "settles an available payment into the canonical pipeline" do
    cpt = post_pending!(intent_id: "pi_available1", amount_cents: 25_00, memo: "Sweep sale")
    stub_intent("pi_available1", status: "available")

    expect { described_class.new(event: venture).sweep! }
      .to change { CanonicalPendingSettledMapping.count }.by(1)

    ct = cpt.reload.canonical_pending_settled_mapping.canonical_transaction
    expect(ct.amount_cents).to eq(25_00)
    expect(CanonicalEventMapping.where(canonical_transaction: ct, event: venture)).to exist
    # The point of the whole exercise: the venture's balance finally moves.
    expect(venture.reload.balance_v2_cents).to eq(25_00)
  end

  it "leaves a still-pending balance transaction alone" do
    post_pending!(intent_id: "pi_pending1", amount_cents: 10_00, memo: "Not yet")
    stub_intent("pi_pending1", status: "pending")

    expect { described_class.new(event: venture).sweep! }
      .not_to(change { CanonicalPendingSettledMapping.count })
  end

  it "is idempotent across a crash between raw row and settle" do
    cpt = post_pending!(intent_id: "pi_crashy1", amount_cents: 5_00, memo: "Crashy")
    stub_intent("pi_crashy1", status: "available")

    sweep = described_class.new(event: venture)
    # Simulate the partial run: the raw settled row exists, nothing else does.
    sweep.send(:settle_one!, cpt)
    expect(CanonicalPendingSettledMapping.count).to eq(1)

    # A full re-sweep must not create a second raw row, CT, or mapping.
    expect { sweep.sweep! }
      .to change { RawCsvTransaction.count }.by(0)
      .and change { CanonicalPendingSettledMapping.count }.by(0)
    expect(venture.reload.balance_v2_cents).to eq(5_00)
  end

  it "settles a refund reversal once its balance transactions are available" do
    Fuime::VentureLedger.new(event: venture).post!(
      key: Fuime::VentureLedger.reversal_key(intent_id: "pi_ref1", kind: "refund",
                                             object_id: "ch_1", amount_cents: 500),
      amount_cents: -5_00, memo: "Refunded payment", date: Time.current
    )
    allow(Stripe::Refund).to receive(:list)
      .with(hash_including(payment_intent: "pi_ref1"), anything)
      .and_return(Stripe::ListObject.construct_from(
                    data: [{ id: "re_1", balance_transaction: { id: "txn_r1", status: "available" } }]
                  ))

    expect(described_class.new(event: venture).sweep!).to eq(1)
    expect(venture.reload.balance_v2_cents).to eq(-5_00)
  end

  it "never touches dispute-keyed pendings" do
    Fuime::VentureLedger.new(event: venture).post!(
      key: Fuime::VentureLedger.reversal_key(intent_id: "pi_disp1", kind: "dispute",
                                             object_id: "dp_1", amount_cents: 300),
      amount_cents: -3_00, memo: "Disputed payment (chargeback)", date: Time.current
    )
    # No Stripe stub on purpose: matching a dispute key would raise on the
    # unstubbed call, so a clean pass proves the key filter excluded it.
    expect(described_class.new(event: venture).sweep!).to eq(0)
  end
  # Fuime: the sweep under merchant-of-record, where there is no connected account.
  #
  # The regression this pins was silent and total. `.sweep_all` drove off
  # StripeConnectedAccount, which under MoR has zero rows, so the scheduled job
  # ran and did nothing — sales stayed pending forever, gross sales stayed $0, and
  # the weekly payout run would have generated $0 for every operator. Calling
  # `#sweep!` directly did not even fail usefully: it raised NoMethodError on nil
  # from inside a Stripe call. Found 2026-08-20, one day before the first live
  # sales.
  describe "under merchant-of-record", :merchant_of_record do
    # No StripeConnectedAccount at all — that is the whole point of the model.
    let(:mor_venture) { create(:event, name: "MoR Venture") }

    def post_mor_pending!(intent_id:, amount_cents:, memo:)
      Fuime::VentureLedger.new(event: mor_venture).post!(
        key: Fuime::VentureLedger.payment_key(intent_id),
        amount_cents:, memo:, date: Time.current
      )
      CanonicalPendingTransaction.order(:id).last
    end

    it "finds ventures by their unsettled lines rather than by connected account" do
      post_mor_pending!(intent_id: "pi_mor1", amount_cents: 25_00, memo: "MoR sale")

      expect(described_class.events_with_unsettled_lines).to include(mor_venture)
      expect(StripeConnectedAccount.where(event: mor_venture)).not_to exist
    end

    # The charge is Fuime's own sale on Fuime's own balance, so the lookup must
    # carry no `stripe_account:`. Sending one would ask a connected account about
    # a PaymentIntent that does not exist there.
    it "asks Stripe about the platform balance, not a connected account" do
      post_mor_pending!(intent_id: "pi_mor2", amount_cents: 25_00, memo: "MoR sale")

      expect(Stripe::PaymentIntent).to receive(:retrieve) do |params, opts|
        expect(params[:id]).to eq("pi_mor2")
        expect(opts).not_to have_key(:stripe_account)
        Stripe::PaymentIntent.construct_from(
          id: "pi_mor2",
          latest_charge: { id: "ch_mor2", balance_transaction: { id: "txn_mor2", status: "available" } }
        )
      end

      described_class.new(event: mor_venture).sweep!
    end

    it "settles the sale so the operator is finally owed something" do
      cpt = post_mor_pending!(intent_id: "pi_mor3", amount_cents: 25_00, memo: "MoR sale")
      allow(Stripe::PaymentIntent).to receive(:retrieve).and_return(
        Stripe::PaymentIntent.construct_from(
          id: "pi_mor3",
          latest_charge: { id: "ch_mor3", balance_transaction: { id: "txn_mor3", status: "available" } }
        )
      )

      expect { described_class.new(event: mor_venture).sweep! }
        .to change { CanonicalPendingSettledMapping.count }.by(1)

      expect(cpt.reload.canonical_pending_settled_mapping).to be_present
      expect(mor_venture.reload.balance_v2_cents).to eq(25_00)
    end
  end

  # Under Connect the account is still required, and its absence must say so
  # rather than surfacing as NoMethodError from inside a Stripe call.
  it "explains itself when a Connect venture was never onboarded" do
    orphan = create(:event, name: "Never onboarded")
    Fuime::VentureLedger.new(event: orphan).post!(
      key: Fuime::VentureLedger.payment_key("pi_orphan"),
      amount_cents: 10_00, memo: "Orphan sale", date: Time.current
    )

    expect { described_class.new(event: orphan).sweep! }
      .to raise_error(ArgumentError, /no Stripe account to settle against/)
  end

end
