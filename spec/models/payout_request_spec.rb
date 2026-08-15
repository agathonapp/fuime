# frozen_string_literal: true

require "rails_helper"

# Fuime: the record of a teen asking to move money and an adult agreeing.
#
# The rules here are the ownership structure from CLAUDE.md L2 expressed as
# validations: the guardian owns the funds, so an approval that is not by an
# overseeing guardian is not an approval.
RSpec.describe PayoutRequest, type: :model do
  let(:venture) { create(:event) }
  let(:minor) { create(:user, :minor) }
  let(:guardian) { create(:user, birthday: 40.years.ago.to_date) }

  # What makes `guardian` an overseeing guardian OF THIS VENTURE: the minor holds
  # a position on it, and there is an active guardianship over that minor.
  def make_overseeing_guardian!
    create(:organizer_position, event: venture, user: minor)
    create(:guardianship, :active, guardian:, minor:)
  end

  describe "amount" do
    it "requires at least a dollar" do
      request = build(:payout_request, event: venture, amount_cents: 50)

      expect(request).not_to be_valid
      expect(request.errors[:amount_cents].join).to match(/at least/i)
    end

    it "rejects a negative amount" do
      expect(build(:payout_request, event: venture, amount_cents: -5_000)).not_to be_valid
    end
  end

  describe "one open request at a time" do
    # Several pending requests can each be affordable and collectively exceed the
    # balance, which would produce a payout that fails at Stripe for a reason the
    # guardian was never shown.
    it "refuses a second pending request for the same venture" do
      create(:payout_request, event: venture)
      second = build(:payout_request, event: venture)

      expect(second).not_to be_valid
      expect(second.errors[:base].join).to match(/already has a payout request/i)
    end

    it "allows a new request once the previous one is settled" do
      create(:payout_request, :paid, event: venture)

      expect(build(:payout_request, event: venture)).to be_valid
    end

    it "allows a new request after a rejection" do
      create(:payout_request, :rejected, event: venture)

      expect(build(:payout_request, event: venture)).to be_valid
    end

    it "does not restrict a different venture" do
      create(:payout_request, event: venture)

      expect(build(:payout_request, event: create(:event))).to be_valid
    end
  end

  describe "who may be recorded as the approver" do
    it "accepts an overseeing guardian" do
      make_overseeing_guardian!
      request = create(:payout_request, event: venture, requested_by: minor)

      request.approved_by = guardian

      expect(request).to be_valid
    end

    # The rule that matters. Without it a teen could be recorded as having
    # approved their own payout, and the audit trail would assert something false.
    it "rejects the teen approving their own request" do
      make_overseeing_guardian!
      request = create(:payout_request, event: venture, requested_by: minor)

      request.approved_by = minor

      expect(request).not_to be_valid
      expect(request.errors[:approved_by].join).to match(/guardian overseeing/i)
    end

    it "rejects an unrelated adult" do
      make_overseeing_guardian!
      request = create(:payout_request, event: venture, requested_by: minor)

      request.approved_by = create(:user, birthday: 35.years.ago.to_date)

      expect(request).not_to be_valid
    end

    it "rejects a guardian of a minor who is not on this venture" do
      make_overseeing_guardian!
      other_guardian = create(:user, birthday: 40.years.ago.to_date)
      create(:guardianship, :active, guardian: other_guardian, minor: create(:user, :minor))

      request = create(:payout_request, event: venture, requested_by: minor)
      request.approved_by = other_guardian

      expect(request).not_to be_valid
    end

    # Fuime support genuinely has to resolve stuck payouts, and that exception is
    # stated in the model rather than hidden in a controller.
    it "allows an admin" do
      request = create(:payout_request, event: venture)

      request.approved_by = create(:user, :admin)

      expect(request).to be_valid
    end
  end

  describe "state machine" do
    let(:request) { create(:payout_request, event: venture) }

    it "starts pending" do
      expect(request).to be_pending
      expect(request).to be_awaiting_guardian
    end

    it "cannot be approved twice" do
      make_overseeing_guardian!
      request.update!(approved_by: guardian)
      request.approve!

      expect { request.approve! }.to raise_error(AASM::InvalidTransition)
    end

    it "cannot be rejected after approval" do
      make_overseeing_guardian!
      request.update!(approved_by: guardian)
      request.approve!

      expect { request.reject! }.to raise_error(AASM::InvalidTransition)
    end

    # A bank can return funds days after Stripe reported a payout as paid.
    # Modelling that as impossible would mean ignoring the webhook that says a
    # family did not get their money.
    it "allows a paid payout to later fail" do
      make_overseeing_guardian!
      request.update!(approved_by: guardian)
      request.approve!
      request.mark_paid!

      expect { request.mark_failed! }.not_to raise_error
      expect(request).to be_failed
    end

    it "treats paid and rejected as settled but approved as not" do
      expect(create(:payout_request, :paid, event: create(:event))).to be_settled
      expect(create(:payout_request, :rejected, event: create(:event))).to be_settled
      expect(create(:payout_request, :approved, event: create(:event))).not_to be_settled
    end
  end

  # ── Batch lines ────────────────────────────────────────────────────────────
  #
  # The third shape this record takes: not a person asking, but the weekly run
  # generating. See CreateFuimePayoutBatches for why the requester is null rather
  # than invented, and Fuime::PayoutBatchService for what generates these.
  describe "a scheduled batch line", :merchant_of_record do
    let(:batch) { create(:fuime_payout_batch) }

    def line(**attrs)
      build(:payout_request, event: venture, requested_by: nil, payout_batch: batch,
                             destination: described_class::FUIME_VENDOR_PAYMENT, **attrs)
    end

    it "is valid with no requester, because nobody asked" do
      expect(line).to be_valid
      expect(line).to be_scheduled
    end

    # The nullability exists for batch lines and must not leak into the two
    # person-initiated paths, where a request with no requester is a payout nobody
    # can be shown to have asked for.
    it "still requires a requester on a request somebody made" do
      request = build(:payout_request, event: venture, requested_by: nil)

      expect(request).not_to be_valid
      expect(request.errors[:requested_by]).to be_present
    end

    # A guardian's decision queue reads `awaiting_approval.person_initiated`. A
    # batch line appearing there would ask a parent to approve a payment Fuime
    # makes out of Fuime's own money, which is not their decision to make.
    it "neither blocks nor is blocked by a guardian's pending request" do
      create(:payout_request, event: venture, requested_by: minor)

      expect(line).to be_valid
      expect(described_class.awaiting_approval.person_initiated.count).to eq(1)
      expect(described_class.scheduled.count).to eq(0)
    end

    it "may be approved by a Fuime admin, who is not anybody's guardian" do
      request = line
      request.save!
      request.approved_by = create(:user, :make_admin)

      expect(request).to be_valid
    end
  end

  describe "the fuime_vendor_payment destination" do
    # The check that keeps the third destination honest. Under Connect the
    # customer's money is in the family's own account, so a Fuime-originated
    # payment to them would be Fuime moving a third party's money — L1, which is
    # the constraint the whole architecture is built around.
    it "is refused while Fuime is not the seller of record" do
      request = build(:payout_request, event: venture, requested_by: nil,
                                       payout_batch: create(:fuime_payout_batch),
                                       destination: described_class::FUIME_VENDOR_PAYMENT)

      expect(request).not_to be_valid
      expect(request.errors[:destination].join).to match(/seller of record/i)
    end

    it "is allowed once Fuime is the seller of record", :merchant_of_record do
      request = build(:payout_request, event: venture, requested_by: nil,
                                       payout_batch: create(:fuime_payout_batch),
                                       destination: described_class::FUIME_VENDOR_PAYMENT)

      expect(request).to be_valid
    end
  end
end
