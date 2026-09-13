# frozen_string_literal: true

require "rails_helper"

# Fuime: the sweep that gives pending Connect ledger lines their settled twins.
# The gap it closes was found empirically: a real $25 test charge produced a
# pending line and a venture balance of $0.00, forever (docs/fuime/STRIPE_PASS.md).
RSpec.describe Fuime::ConnectSettlementSweep do
  include HcbShortCodeIsolation

  let(:guardian) { create(:user, birthday: 40.years.ago.to_date) }
  let(:venture) { create(:event, name: "Sweep Venture") }

  let!(:account) do
    StripeConnectedAccount.create!(event: venture, owner: guardian,
                                   controller_profile: "cards_enabled",
                                   stripe_id: "acct_sweep_test")
  end

  # The settlement pipeline builds a CanonicalTransaction through raw CSV
  # import. assign_ledger_item then compares a memo-derived short_code to the
  # grouping-engine HcbCode and calls Rails.error.unexpected on mismatch —
  # which raises in test. That report is seed-dependent and is not what this
  # spec is proving. Stub it so a leftover Ledger::Item cannot fail a settle.
  before { allow(Rails.error).to receive(:unexpected) }

  # Same isolation as payables_ledger_spec. The token must already own an
  # HcbCode + Ledger::Item — a bare unused string falls through to HCB-000
  # and UniqueViolation-collides (see spec/support/hcb_short_code_isolation.rb).
  def unique_hcb_short_code
    isolated_hcb_short_code
  end

  def isolated_memo(text)
    "#{text} HCB-#{unique_hcb_short_code}"
  end

  def post_pending!(intent_id:, amount_cents:, memo:)
    Fuime::VentureLedger.new(event: venture).post!(
      key: Fuime::VentureLedger.payment_key(intent_id),
      amount_cents:, memo: isolated_memo(memo), date: Time.current
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
      amount_cents: -5_00, memo: isolated_memo("Refunded payment"), date: Time.current
    )
    allow(Stripe::Refund).to receive(:list)
      .with(hash_including(payment_intent: "pi_ref1"), anything)
      .and_return(Stripe::ListObject.construct_from(
                    data: [{ id: "re_1", balance_transaction: { id: "txn_r1", status: "available" } }]
                  ))

    expect(described_class.new(event: venture).sweep!).to eq(1)
    expect(venture.reload.balance_v2_cents).to eq(-5_00)
  end

  # Fuime: the rebate matched neither key regex, so it never settled. Pending
  # incoming is excluded from the balance — so the venture kept the settled fee
  # DEBIT and never got the credit that cancels it, and a fully refunded sale
  # left the operator owing Fuime its cut of money the business never kept.
  describe "the platform-fee rebate that comes with a refund" do
    # The whole shape of a refunded sale, in the order it is really written:
    # payment, Fuime's fee, then the reversal and the rebate.
    def post_refunded_sale!(intent_id:, gross_cents:, fee_cents:)
      ledger = Fuime::VentureLedger.new(event: venture)
      ledger.post!(key: Fuime::VentureLedger.payment_key(intent_id),
                   amount_cents: gross_cents, memo: isolated_memo("Sale"), date: Time.current)
      ledger.post!(key: Fuime::VentureLedger.fee_key(intent_id),
                   amount_cents: -fee_cents, memo: isolated_memo("Fuime fee"), date: Time.current)
      ledger.post!(key: Fuime::VentureLedger.reversal_key(intent_id:, kind: "refund",
                                                          object_id: "re_1", amount_cents: gross_cents),
                   amount_cents: -gross_cents, memo: isolated_memo("Refunded"), date: Time.current)
      ledger.post!(key: Fuime::VentureLedger.fee_rebate_key(intent_id:, object_id: "re_1",
                                                            reversal_cents: gross_cents),
                   amount_cents: fee_cents, memo: isolated_memo("Fuime platform fee refunded"),
                   date: Time.current)
    end

    def stub_available_refund(intent_id)
      allow(Stripe::Refund).to receive(:list)
        .with(hash_including(payment_intent: intent_id), anything)
        .and_return(Stripe::ListObject.construct_from(
                      data: [{ id: "re_1", balance_transaction: { id: "txn_r1", status: "available" } }]
                    ))
    end

    it "settles alongside the refund it belongs to" do
      post_refunded_sale!(intent_id: "pi_reb1", gross_cents: 35_00, fee_cents: 2_45)
      stub_intent("pi_reb1", status: "available")
      stub_available_refund("pi_reb1")

      described_class.new(event: venture).sweep!

      rebate_key = Fuime::VentureLedger.fee_rebate_key(intent_id: "pi_reb1", object_id: "re_1",
                                                       reversal_cents: 35_00)
      rebate_cpt = CanonicalPendingTransaction
                   .joins(:raw_pending_donation_transaction)
                   .find_by(raw_pending_donation_transactions: { donation_transaction_id: rebate_key })

      expect(rebate_cpt.canonical_pending_settled_mapping).to be_present
    end

    # The number a teenager actually reads. Fully refunded: they keep nothing and
    # they owe nothing. Before this it was −$2.45, labelled "in arrears".
    it "leaves a fully refunded sale at zero rather than in arrears" do
      post_refunded_sale!(intent_id: "pi_reb2", gross_cents: 35_00, fee_cents: 2_45)
      stub_intent("pi_reb2", status: "available")
      stub_available_refund("pi_reb2")

      described_class.new(event: venture).sweep!

      expect(venture.reload.balance_v2_cents).to eq(0)
    end

    # Exactly as conservative about disputes as the reversal line above it: a
    # rebate keyed on a dispute object is not swept, because no dispute has ever
    # been exercised against Stripe and settling one by construction is guessing.
    it "does not settle a rebate that came from a dispute" do
      Fuime::VentureLedger.new(event: venture).post!(
        key: Fuime::VentureLedger.fee_rebate_key(intent_id: "pi_reb3", object_id: "dp_1",
                                                 reversal_cents: 30_00),
        amount_cents: 2_10, memo: isolated_memo("Fuime platform fee refunded"), date: Time.current
      )

      # No Stripe stub, as in the dispute example below: a match would raise on
      # the unstubbed call, so a clean zero proves the filter held.
      expect(described_class.new(event: venture).sweep!).to eq(0)
    end
  end

  it "never touches dispute-keyed pendings" do
    Fuime::VentureLedger.new(event: venture).post!(
      key: Fuime::VentureLedger.reversal_key(intent_id: "pi_disp1", kind: "dispute",
                                             object_id: "dp_1", amount_cents: 300),
      amount_cents: -3_00, memo: isolated_memo("Disputed payment (chargeback)"), date: Time.current
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
        amount_cents:, memo: isolated_memo(memo), date: Time.current
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
      amount_cents: 10_00, memo: isolated_memo("Orphan sale"), date: Time.current
    )

    expect { described_class.new(event: orphan).sweep! }
      .to raise_error(ArgumentError, /no Stripe account to settle against/)
  end

end
