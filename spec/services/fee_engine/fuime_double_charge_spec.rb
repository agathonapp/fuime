# frozen_string_literal: true

require "rails_helper"

# Fuime: the fee must be charged once.
#
# Upstream, FeeEngine IS how the platform takes its cut — a positive canonical
# transaction accrues `event.revenue_fee` into `fee_balance`, which
# `Event#balance_available_v2_cents` then subtracts. Correct when the accrual is
# the only place the fee is taken.
#
# It is not, for Fuime. Under Stripe Connect the platform fee is deducted by
# STRIPE at the moment of the charge (`application_fee_amount`) and posted as its
# own explicit ledger line by Fuime::ConnectPaymentRecorder. So a $100 sale
# arrives already broken out as +$100 gross, −$4 Fuime, −$3.20 Stripe — and this
# engine, seeing the +$100, used to accrue another $4.
#
# Two consequences, both live before this guard:
#
#   * a teenager was charged 8% for a 4% product;
#   * the venture dashboard (which subtracts fee_balance) and the payouts page
#     (which does not) disagreed by exactly that amount, with no explanation
#     available on either page.
#
# Found while pointing operator-facing views at Fuime::PayablesLedger — the two
# numbers had to be reconciled before they could share a figure.
RSpec.describe FeeEngine::Create, "Fuime fees are not charged twice" do
  # Standard, so the control example below can prove a fee is actually CHARGED.
  # `create(:event)` falls back to a plan whose revenue_fee is 0, which would make
  # "still charges the fee" pass on a zero and assert nothing.
  let(:event) { create(:event, plan_type: Event::Plan::Standard) }

  def fee_for(memo, amount_cents: 100_00)
    ct = create(:canonical_transaction, amount_cents:, memo:, event:)
    mapping = CanonicalEventMapping.find_by!(canonical_transaction: ct, event:)
    described_class.new(canonical_event_mapping: mapping).run

    Fee.find_by(canonical_event_mapping: mapping)
  end

  # The regression. A Fuime sale carries its ledger key in the memo, and Fuime's
  # cut is already gone from the amount by the time it lands.
  it "waives the accrual on a Fuime sale, whose fee Stripe already took" do
    fee = fee_for("Payment from a customer [fuime_pi_double_charge]")

    expect(fee).to be_present
    expect(fee.reason).to eq("revenue_waived")
    expect(fee.amount_cents_as_decimal).to eq(0)
  end

  # `revenue_waived` rather than an early return, deliberately: the row still has
  # to be written, or `CanonicalEventMapping.missing_fee` keeps returning this
  # mapping and the hourly job re-examines every Fuime transaction ever, forever.
  it "still writes a fee row, so the hourly job stops reconsidering the mapping" do
    ct = create(:canonical_transaction, amount_cents: 100_00,
                                        memo: "Payment [fuime_pi_missing_fee]", event:)
    mapping = CanonicalEventMapping.find_by!(canonical_transaction: ct, event:)

    expect { described_class.new(canonical_event_mapping: mapping).run }
      .to change { Fee.where(canonical_event_mapping: mapping).count }.by(1)

    expect(CanonicalEventMapping.missing_fee).not_to include(mapping)
  end

  # Every Fuime-posted line, not just sales — the key scheme covers payouts,
  # refunds, card spend and awards too, and none of them should accrue a fee.
  it "waives the accrual on any line carrying a Fuime ledger key" do
    %w[
      fuime_award_7_student
      fuime_funding_tu_1
      fuime_payoutrev_po_1
    ].each do |key|
      fee = fee_for("Some movement [#{key}]")

      expect(fee.reason).to eq("revenue_waived"), "expected #{key} to be waived"
    end
  end

  # The guard must be narrow. A transaction that did not come from Fuime's own
  # posting path has had no fee taken from it yet, so upstream's behaviour is
  # still the correct behaviour and must survive untouched.
  it "still charges the fee on a transaction Fuime did not post" do
    fee = fee_for("Some other deposit")

    expect(fee.reason).to eq("revenue")
    expect(fee.amount_cents_as_decimal).to be > 0
  end

  # A memo that merely mentions the word must not trip it. The pattern is
  # anchored on the bracketed key, which is what VentureLedger.settled_memo
  # actually writes.
  it "is not fooled by a memo that happens to mention fuime" do
    fee = fee_for("Refund from fuime supplies co")

    expect(fee.reason).to eq("revenue")
  end
end
