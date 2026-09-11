# frozen_string_literal: true

require "rails_helper"

# Operator-facing BankFee / pending-fee copy. Fiscal sponsorship is HCB leftover
# and must not appear on the ledger. Legal contract models are out of scope.
RSpec.describe "Fuime service fee copy" do
  describe "HcbCode#memo" do
    it "labels a pending take-rate Fuime service fee" do
      bank_fee = create(:bank_fee, amount_cents: -3_173)
      hcb_code = HcbCode.find_or_create_by!(hcb_code: bank_fee.hcb_code)

      expect(hcb_code.memo).to eq("Fuime service fee")
      expect(hcb_code.memo).not_to match(/fiscal sponsorship/i)
    end

    it "labels a fee-for-range and a fee credit" do
      revenue = create(:fee_revenue, start: Date.new(2026, 9, 1), end: Date.new(2026, 9, 7))
      ranged = create(:bank_fee, amount_cents: -4_442, fee_revenue: revenue)
      credit = create(:bank_fee, amount_cents: 50)

      expect(HcbCode.find_or_create_by!(hcb_code: ranged.hcb_code).memo)
        .to eq("Fuime service fee for 9/1 to 9/7")
      expect(HcbCode.find_or_create_by!(hcb_code: credit.hcb_code).memo)
        .to eq("Fuime service fee credit")
    end
  end

  describe "Ledger::Item" do
    def item_for(bank_fee)
      item = Ledger::Item.new(
        amount_cents: bank_fee.amount_cents,
        memo: "Initial",
        datetime: Time.current,
        linked_object: bank_fee
      )
      item.save(validate: false)
      item.refresh!
      item.reload
    end

    it "uses Fuime service fee for system memo and humanized type" do
      bank_fee = create(:bank_fee, amount_cents: -3_173)
      item = item_for(bank_fee)

      expect(item.system_memo).to eq("Fuime service fee")
      expect(item.humanized_type).to eq("Fuime service fee")
      expect(item.system_memo).not_to match(/fiscal sponsorship/i)
    end
  end

  describe "RawPendingBankFeeTransaction#memo" do
    it "is Fuime service fee" do
      bank_fee = create(:bank_fee, amount_cents: -3_173)
      raw = create(:raw_pending_bank_fee_transaction, bank_fee_transaction_id: bank_fee.id)

      expect(raw.memo).to eq("Fuime service fee")
    end
  end
end
