# frozen_string_literal: true

require "rails_helper"

RSpec.describe MockTransactionEngineService::GenerateMockTransaction do
  let(:rows) { described_class.new.run }

  it "only generates income and the Free take-rate as a Fuime service fee" do
    expect(Event::Plan::Free::REVENUE_FEE).to eq(0.07)
    expect(described_class::SERVICE_FEE_RATE).to eq(Event::Plan::Free::REVENUE_FEE)
    expect(described_class::SERVICE_FEE_LABEL).to eq("Fuime service fee (7%)")

    memos = rows.map { |row| row.local_hcb_code.custom_memo }
    expect(memos).to include(described_class::SERVICE_FEE_LABEL)
    expect(memos.grep(/fiscal sponsorship|hack club|disco|donation from/i)).to be_empty
    expect(memos.grep(/business cards|booth fee|restaurant depot|filament|card reader/i)).to be_empty

    income = rows.select { |row| row.amount_cents.positive? }
    fees = rows.select { |row| row.amount_cents.negative? }
    expect(income).to be_present
    expect(fees).to be_present
    expect(fees).to all(satisfy { |row| row.local_hcb_code.custom_memo == described_class::SERVICE_FEE_LABEL })

    income_memos = income.map { |row| row.local_hcb_code.custom_memo }
    expect(income_memos).to all(match(/lawn|hedge|tutor/i))
  end

  it "charges 7% of each sale, not an invented 4% or 5%" do
    pairs = rows.each_slice(2).to_a
    expect(pairs).to be_present

    pairs.each do |sale, fee|
      expect(sale.amount_cents).to be_positive
      expect(fee.local_hcb_code.custom_memo).to eq(described_class::SERVICE_FEE_LABEL)
      expect(fee.amount_cents.abs.to_f / sale.amount_cents).to be_within(0.005).of(described_class::SERVICE_FEE_RATE)
    end
  end
end
