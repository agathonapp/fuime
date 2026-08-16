# frozen_string_literal: true

require "rails_helper"

RSpec.describe Fuime::PayoutBatch do
  describe "the lifecycle" do
    it "starts as a draft" do
      expect(create(:fuime_payout_batch)).to be_draft
    end

    it "goes draft → approved → paid" do
      batch = create(:fuime_payout_batch)

      batch.approve!
      expect(batch).to be_approved

      batch.mark_paid!
      expect(batch).to be_paid
    end

    it "cannot be marked paid without being approved first" do
      expect { create(:fuime_payout_batch).mark_paid! }.to raise_error(AASM::InvalidTransition)
    end

    # A run can be approved on Thursday and stopped on Friday morning. Modelling
    # that as impossible would mean the only way to stop it is editing the
    # database.
    it "can be cancelled from draft or from approved" do
      expect { create(:fuime_payout_batch).cancel! }.not_to raise_error
      expect { create(:fuime_payout_batch, :approved, period_end: Date.current - 7).cancel! }.not_to raise_error
    end

    it "cannot be cancelled once it has paid" do
      expect { create(:fuime_payout_batch, :paid).cancel! }.to raise_error(AASM::InvalidTransition)
    end
  end

  describe "uniqueness on the period" do
    # The guarantee that a double-click on Generate cannot produce two runs that
    # each think they own the same week. Enforced in the database, because two
    # workers racing is the case a Ruby-side check does not cover.
    it "refuses a second live run for the same period" do
      create(:fuime_payout_batch, period_end: Date.new(2026, 8, 15))

      expect { create(:fuime_payout_batch, period_end: Date.new(2026, 8, 15)) }
        .to raise_error(ActiveRecord::RecordNotUnique)
    end

    it "allows a fresh run for a period whose earlier run was cancelled" do
      create(:fuime_payout_batch, :cancelled, period_end: Date.new(2026, 8, 15))

      expect { create(:fuime_payout_batch, period_end: Date.new(2026, 8, 15)) }.not_to raise_error
    end
  end

  describe "validations" do
    it "refuses a period that ends before it starts" do
      batch = build(:fuime_payout_batch, period_start: Date.current, period_end: Date.current - 1)

      expect(batch).not_to be_valid
      expect(batch.errors[:period_end]).to be_present
    end

    it "refuses a negative dial" do
      expect(build(:fuime_payout_batch, reserve_basis_points: -1)).not_to be_valid
    end
  end

  # Tagged because a `fuime_vendor_payment` line only validates under the model
  # that gives Fuime money of its own to pay out — see
  # PayoutRequest#destination_must_suit_the_account.
  describe "#summary", :merchant_of_record do
    it "says what a reviewer needs before saying yes" do
      batch = create(:fuime_payout_batch, payout_on: Date.new(2026, 8, 21))
      create(:payout_request, payout_batch: batch, requested_by: nil, amount_cents: 90_00,
                              destination: PayoutRequest::FUIME_VENDOR_PAYMENT,
                              event: create(:event))

      expect(batch.summary).to include("1 operator")
      expect(batch.summary).to include("$90.00")
      expect(batch.summary).to include("Friday 21 August")
    end
  end

  describe "#policy" do
    # A batch answers with the rules it was generated under, never with today's.
    it "reads its own frozen dials rather than the environment" do
      batch = create(:fuime_payout_batch, hold_days: 30, reserve_basis_points: 250)

      expect(batch.policy.hold_days).to eq(30)
      expect(batch.policy.reserve_percentage).to eq(2.5)
    end
  end
end
