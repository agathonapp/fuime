# frozen_string_literal: true

require "rails_helper"

# Fuime: moving money out of a venture. The guardian owns the account and the
# funds, so every example here is ultimately about the adult decision being real
# and the numbers being checked against Stripe rather than against Fuime's memory.
RSpec.describe Fuime::PayoutService do
  let(:venture) { create(:event) }
  let(:minor) { create(:user, :minor) }
  let(:guardian) { create(:user, birthday: 40.years.ago.to_date) }
  let!(:account) { create(:stripe_connected_account, :ready, event: venture, owner: guardian) }

  let(:service) { described_class.new(event: venture) }

  before do
    create(:organizer_position, event: venture, user: minor)
    create(:guardianship, :active, guardian:, minor:)
  end

  def stub_balance(available_cents)
    allow(Stripe::Balance).to receive(:retrieve).and_return(
      Stripe::Balance.construct_from(
        available: [
          # A non-USD entry is included because Stripe returns one row per
          # currency and picking `.first` would eventually read the wrong one.
          { currency: "cad", amount: 999_999 },
          { currency: "usd", amount: available_cents },
        ]
      )
    )
  end

  def stub_payout(id: "po_test_1")
    payout = Stripe::Payout.construct_from(id:, amount: 5_000, currency: "usd")
    allow(Stripe::Payout).to receive(:create).and_return(payout)
    payout
  end

  describe "#available_balance_cents" do
    it "reads the USD available balance" do
      stub_balance(12_345)

      expect(service.available_balance_cents).to eq(12_345)
    end

    it "returns 0 when payments were never set up" do
      account.destroy!

      expect(described_class.new(event: venture.reload).available_balance_cents).to eq(0)
    end

    # A balance Fuime cannot read must not take down the venture's dashboard.
    it "returns nil rather than raising when Stripe is unreachable" do
      allow(Stripe::Balance).to receive(:retrieve).and_raise(Stripe::APIError.new("boom"))

      expect(service.available_balance_cents).to be_nil
    end
  end

  describe "#request!" do
    it "creates a pending request when the balance covers it" do
      stub_balance(10_000)

      request = service.request!(amount_cents: 5_000, requested_by: minor)

      expect(request).to be_pending
      expect(request.amount_cents).to eq(5_000)
      expect(request.requested_by).to eq(minor)
    end

    it "refuses more than the available balance" do
      stub_balance(4_000)

      expect {
        service.request!(amount_cents: 5_000, requested_by: minor)
      }.to raise_error(Fuime::PayoutService::InsufficientFunds, /less than/i)
    end

    it "refuses when the venture has not finished payment setup" do
      account.destroy!

      expect {
        described_class.new(event: venture.reload).request!(amount_cents: 5_000, requested_by: minor)
      }.to raise_error(Fuime::PayoutService::NotSetUp)
    end

    # Charging is allowed before bank details clear, so this is a real state and
    # must produce an explanation rather than a Stripe error later.
    it "refuses when Stripe cannot pay this account out yet" do
      account.update!(payouts_enabled: false)
      stub_balance(10_000)

      expect {
        service.request!(amount_cents: 5_000, requested_by: minor)
      }.to raise_error(Fuime::PayoutService::PayoutsDisabled, /bank account/i)
    end

    it "refuses when the balance cannot be confirmed" do
      allow(Stripe::Balance).to receive(:retrieve).and_raise(Stripe::APIError.new("boom"))

      expect {
        service.request!(amount_cents: 5_000, requested_by: minor)
      }.to raise_error(Fuime::PayoutService::StripeRejected)
    end
  end

  describe "#approve!" do
    let!(:request) { create(:payout_request, event: venture, requested_by: minor, amount_cents: 5_000) }

    it "creates a Stripe payout and records it against the request" do
      stub_balance(10_000)
      payout = stub_payout

      service.approve!(request:, approver: guardian)

      expect(request.reload).to be_approved
      expect(request.stripe_payout_id).to eq(payout.id)
      expect(request.approved_by).to eq(guardian)
      expect(request.approved_at).to be_present
    end

    it "sends the payout on the venture's own connected account, not Fuime's" do
      stub_balance(10_000)
      stub_payout

      service.approve!(request:, approver: guardian)

      expect(Stripe::Payout).to have_received(:create).with(
        hash_including(amount: 5_000, currency: "usd"),
        hash_including(stripe_account: account.stripe_id)
      )
    end

    # Guards a retried HTTP call that Stripe actually processed but whose response
    # Fuime never saw. Without it, the retry sends the family's money twice.
    it "sends a Stripe idempotency key derived from the request" do
      stub_balance(10_000)
      stub_payout

      service.approve!(request:, approver: guardian)

      expect(Stripe::Payout).to have_received(:create).with(
        anything,
        hash_including(idempotency_key: "fuime_payout_request_#{request.id}")
      )
    end

    # The scenario the re-read exists for: teen asks Tuesday, chargeback lands
    # Wednesday, parent approves Thursday.
    it "refuses if the balance dropped after the request was made" do
      stub_balance(1_000)

      expect {
        service.approve!(request:, approver: guardian)
      }.to raise_error(Fuime::PayoutService::InsufficientFunds, /balance changed/i)

      expect(request.reload).to be_pending
    end

    it "leaves the request pending when Stripe rejects the payout" do
      stub_balance(10_000)
      allow(Stripe::Payout).to receive(:create)
        .and_raise(Stripe::InvalidRequestError.new("insufficient funds", nil, code: "balance_insufficient"))

      expect {
        service.approve!(request:, approver: guardian)
      }.to raise_error(Fuime::PayoutService::StripeRejected, /couple of days/i)

      # An approved request with no payout behind it would show a family money as
      # sent that never left.
      expect(request.reload).to be_pending
      expect(request.stripe_payout_id).to be_nil
    end

    it "refuses to approve a request that was already decided" do
      stub_balance(10_000)
      stub_payout
      service.approve!(request:, approver: guardian)

      expect {
        service.approve!(request: request.reload, approver: guardian)
      }.to raise_error(Fuime::PayoutService::Error, /already been decided/i)
    end

    it "will not record a non-guardian as the approver" do
      stub_balance(10_000)
      stub_payout

      expect {
        service.approve!(request:, approver: create(:user, birthday: 30.years.ago.to_date))
      }.to raise_error(ActiveRecord::RecordInvalid)

      expect(request.reload).to be_pending
    end
  end

  describe "#reject!" do
    let!(:request) { create(:payout_request, event: venture, requested_by: minor) }

    it "records the decision and the reason" do
      service.reject!(request:, approver: guardian, reason: "Let's reinvest it.")

      expect(request.reload).to be_rejected
      expect(request.rejection_reason).to eq("Let's reinvest it.")
      expect(request.rejected_at).to be_present
    end

    # A rejection is not an approval, so nobody is recorded as having approved it.
    it "does not record an approver" do
      service.reject!(request:, approver: guardian, reason: "No")

      expect(request.reload.approved_by).to be_nil
    end

    it "never contacts Stripe" do
      allow(Stripe::Payout).to receive(:create)

      service.reject!(request:, approver: guardian)

      expect(Stripe::Payout).not_to have_received(:create)
    end

    it "refuses to reject an already-decided request" do
      service.reject!(request:, approver: guardian)

      expect {
        service.reject!(request: request.reload, approver: guardian)
      }.to raise_error(Fuime::PayoutService::Error, /already been decided/i)
    end
  end
end
