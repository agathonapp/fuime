# frozen_string_literal: true

require "rails_helper"

# Fuime: whose ledger a payment lands on when one Stripe account serves many
# ventures.
#
# Resolving purely from `event.account` was right while every venture owned its own
# account, and it stays the primary lookup. But inside a school programme the school
# owns one account for the whole tree, so the account identifies the TREE and every
# student's sale was booked to the school's own ledger — no student ever showed a
# balance, and nothing on the page said why.
#
# The narrowing step is only as safe as its verification, so most of this file is
# about what a bad `fuime_event_id` cannot do.
RSpec.describe Fuime::ConnectPaymentRecorder, "attribution inside a school programme" do
  let(:school_tree) { build_school_tree }
  let(:school)  { school_tree[0] }
  let(:cohort)  { school_tree[1] }
  let(:venture) { school_tree[2] }

  let!(:school_account) { create(:stripe_connected_account, :ready, event: school) }

  def stripe_event(type, object, account: school_account.stripe_id)
    Stripe::Event.construct_from(type:, account:, data: { object: })
  end

  def handle(object, account: school_account.stripe_id)
    described_class.new(event: stripe_event("payment_intent.succeeded", object, account:)).handle
  end

  def payment_intent(id: "pi_school_1", amount: 10_000, fee: nil, event_id: nil)
    {
      id:,
      object: "payment_intent",
      amount_received: amount,
      created: Time.current.to_i,
      description: "Lawn mowing",
      **(fee.nil? ? {} : { application_fee_amount: fee }),
      **(event_id.nil? ? {} : { metadata: { fuime_event_id: event_id.to_s } }),
    }
  end

  def lines_for(event)
    CanonicalPendingEventMapping.where(event_id: event.id).map(&:canonical_pending_transaction)
  end

  describe "booking a student's sale" do
    it "credits the student's venture, not the school that owns the account" do
      handle(payment_intent(event_id: venture.id))

      expect(lines_for(venture).map(&:amount_cents)).to contain_exactly(10_000)
      expect(lines_for(school)).to be_empty
    end

    it "credits a venture two levels below the account holder" do
      handle(payment_intent(event_id: cohort.id))

      expect(lines_for(cohort).map(&:amount_cents)).to contain_exactly(10_000)
    end

    it "credits the account holder when the metadata names it" do
      handle(payment_intent(event_id: school.id))

      expect(lines_for(school).map(&:amount_cents)).to contain_exactly(10_000)
    end

    # The fallback that keeps the family path and every pre-existing payment working.
    it "credits the account holder when there is no metadata at all" do
      handle(payment_intent)

      expect(lines_for(school).map(&:amount_cents)).to contain_exactly(10_000)
    end

    it "puts the fee line on the same venture as the payment" do
      handle(payment_intent(event_id: venture.id, fee: 400))

      expect(lines_for(venture).map(&:amount_cents)).to contain_exactly(10_000, -400)
      expect(lines_for(school)).to be_empty
    end
  end

  # The whole reason metadata is a narrowing step rather than a lookup: the claim is
  # verified against the same resolution the rest of the app uses, so it can only
  # ever name a venture already paid into this exact account.
  describe "what a bad fuime_event_id cannot do" do
    it "cannot move money to a venture in a different school" do
      other_school, _cohort, other_venture = build_school_tree(school_name: "Beta School")
      create(:stripe_connected_account, :ready, event: other_school)

      handle(payment_intent(event_id: other_venture.id))

      expect(lines_for(other_venture)).to be_empty
      expect(lines_for(school).map(&:amount_cents)).to contain_exactly(10_000)
    end

    it "cannot move money to an unrelated venture with its own account" do
      unrelated = create(:event)
      create(:stripe_connected_account, :ready, event: unrelated)

      handle(payment_intent(event_id: unrelated.id))

      expect(lines_for(unrelated)).to be_empty
      expect(lines_for(school).map(&:amount_cents)).to contain_exactly(10_000)
    end

    # An ordinary HCB-shaped child does not inherit an account, so naming one is
    # naming a venture this account does not pay.
    it "cannot move money to an ordinary sub-organization of the account holder" do
      plain_parent = create(:event)
      plain_account = create(:stripe_connected_account, :ready, event: plain_parent)
      plain_child = create(:event, parent: plain_parent)

      handle(payment_intent(event_id: plain_child.id), account: plain_account.stripe_id)

      expect(lines_for(plain_child)).to be_empty
      expect(lines_for(plain_parent).map(&:amount_cents)).to contain_exactly(10_000)
    end

    it "falls back to the account holder for a venture id that does not exist" do
      handle(payment_intent(event_id: 999_999_999))

      expect(lines_for(school).map(&:amount_cents)).to contain_exactly(10_000)
    end

    # `to_i` would have turned this into venture 0 and looked like a real lookup.
    it "falls back to the account holder for a non-numeric venture id" do
      handle(payment_intent(event_id: "not-an-id"))

      expect(lines_for(school).map(&:amount_cents)).to contain_exactly(10_000)
    end
  end

  describe "reversals" do
    # Reversals resolve through the ORIGINAL payment's ledger row rather than through
    # the account or the metadata, so they follow the payment to the student even
    # though a refund payload carries neither.
    it "books a refund against the student the payment was booked to" do
      handle(payment_intent(event_id: venture.id))

      described_class.new(
        event: stripe_event("charge.refunded", {
                              id: "ch_school_1",
                              object: "charge",
                              payment_intent: "pi_school_1",
                              amount_refunded: 2_500,
                              created: Time.current.to_i,
                            })
      ).handle

      expect(lines_for(venture).map(&:amount_cents)).to contain_exactly(10_000, -2_500)
      expect(lines_for(school)).to be_empty
    end
  end
end
