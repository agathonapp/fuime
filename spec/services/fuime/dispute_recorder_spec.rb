# frozen_string_literal: true

require "rails_helper"

# Fuime: a chargeback is the one money event where the platform, not the
# operator, is the party on the hook — Fuime is merchant of record, so Fuime
# answers it and Fuime pays if nobody does. These examples pin the two things
# that were missing: a record with the deadline on it, and the money going back
# when Fuime wins.
RSpec::Matchers.define_negated_matcher :not_enqueue_mail, :have_enqueued_mail

RSpec.describe Fuime::DisputeRecorder do
  let(:event) { create(:event, plan_type: Event::Plan::Standard) }

  def stripe_event(type, object)
    Stripe::Event.construct_from(type:, data: { object: })
  end

  def handle(type, object)
    Fuime::PaymentWebhookHandler.new(event: stripe_event(type, object)).handle
  end

  def payment_intent(id: "pi_test_1", amount: 10_000)
    {
      id:,
      object: "payment_intent",
      amount_received: amount,
      created: Time.current.to_i,
      description: "Lawn mowing",
      metadata: { "fuime_event_id" => event.id.to_s },
    }
  end

  def dispute_object(status: "needs_response", amount: 10_000, due_by: 10.days.from_now,
                     id: "dp_test_1", reason: "fraudulent")
    {
      id:,
      object: "dispute",
      payment_intent: "pi_test_1",
      charge: "ch_test_1",
      amount:,
      currency: "usd",
      reason:,
      status:,
      created: Time.current.to_i,
      evidence_details: { due_by: due_by&.to_i },
    }
  end

  def fee_on(cents) = event.fuime_fee_cents_on(cents)

  # The number the payable is computed from: unsettled outgoing counts against
  # an operator, and a declined row is not unsettled. See Fuime::PayablesLedger.
  def pending_outgoing = event.pending_outgoing_balance_v2_cents

  before { handle("payment_intent.succeeded", payment_intent) }

  describe "opening a dispute" do
    it "records the case file with its reason and deadline" do
      handle("charge.dispute.created", dispute_object)

      dispute = Fuime::Dispute.sole
      expect(dispute.event).to eq(event)
      expect(dispute.stripe_dispute_id).to eq("dp_test_1")
      expect(dispute.stripe_payment_intent_id).to eq("pi_test_1")
      expect(dispute.amount_cents).to eq(10_000)
      expect(dispute.reason).to eq("fraudulent")
      expect(dispute.status).to eq("needs_response")
      expect(dispute.evidence_due_at).to be_within(1.minute).of(10.days.from_now)
      expect(dispute).to be_actionable
    end

    # Stripe retries. A second delivery must land on the same case, not open a
    # second one against the same chargeback.
    it "is idempotent across re-delivery" do
      2.times { handle("charge.dispute.created", dispute_object) }

      expect(Fuime::Dispute.count).to eq(1)
    end

    it "still records the ledger reversal" do
      handle("charge.dispute.created", dispute_object)

      expect(pending_outgoing).to eq(-fee_on(10_000) - 10_000)
    end

    # The dispute reaches us before any Fuime::Sale row exists if the sale came
    # in through a path that did not write one. The case file is still worth
    # having, so `sale` is optional rather than a precondition.
    it "records a case even when no sale row exists" do
      expect { handle("charge.dispute.created", dispute_object) }
        .to change(Fuime::Dispute, :count).by(1)
      expect(Fuime::Dispute.sole.sale).to be_nil
    end

    it "ignores a dispute against a payment it never recorded" do
      expect {
        handle("charge.dispute.created", dispute_object(id: "dp_other").merge(payment_intent: "pi_unknown"))
      }.not_to change(Fuime::Dispute, :count)
    end
  end

  describe "when Fuime wins" do
    before { handle("charge.dispute.created", dispute_object) }

    # The bug this class was written for: `closed` was unhandled, so a won
    # dispute left the operator debited forever — the reversal is excluded from
    # the settlement sweep on purpose, so it never settles and never clears.
    it "gives the operator their money back" do
      expect(pending_outgoing).to eq(-fee_on(10_000) - 10_000)

      handle("charge.dispute.closed", dispute_object(status: "won"))

      expect(pending_outgoing).to eq(-fee_on(10_000))
      expect(Fuime::Dispute.sole).to be_reinstated
    end

    it "declines the fee rebate alongside the reversal" do
      handle("charge.dispute.closed", dispute_object(status: "won"))

      rebates = CanonicalPendingEventMapping
                .where(event_id: event.id)
                .map(&:canonical_pending_transaction)
                .select { |cpt| cpt.memo.to_s.match?(/fee refunded/i) }

      expect(rebates).to be_present
      expect(rebates).to all(satisfy { |cpt| CanonicalPendingDeclinedMapping.exists?(canonical_pending_transaction_id: cpt.id) })
    end

    it "reinstates exactly once however many times the event is re-delivered" do
      3.times { handle("charge.dispute.closed", dispute_object(status: "won")) }

      expect(pending_outgoing).to eq(-fee_on(10_000))
      expect(CanonicalPendingDeclinedMapping.count).to eq(2) # the reversal and its rebate
    end

  end

  # A refund of the same payment is a separate reversal that really did happen.
  # Winning a chargeback must not back that out too.
  #
  # The dispute here is PARTIAL on purpose: a full chargeback reverses the whole
  # sale, and the recorder's outstanding cap then correctly refuses to post
  # anything for a later refund — so a full dispute cannot exercise this at all.
  describe "when Fuime wins a partial dispute and the payment was also refunded" do
    before do
      handle("charge.dispute.created", dispute_object(amount: 6_000))
      handle("charge.refunded", {
               id: "ch_test_1",
               object: "charge",
               payment_intent: "pi_test_1",
               amount: 10_000,
               amount_refunded: 2_000,
               created: Time.current.to_i,
             })
    end

    it "backs out only the chargeback" do
      expect(pending_outgoing).to eq(-fee_on(10_000) - 6_000 - 2_000)

      handle("charge.dispute.closed", dispute_object(amount: 6_000, status: "won"))

      # The $20 refund stands; only the $60 chargeback was backed out.
      expect(pending_outgoing).to eq(-fee_on(10_000) - 2_000)
    end

    # The refund's own fee rebate is keyed on the REFUND object, not the dispute,
    # which is the whole reason the rebate prefix carries the dispute id.
    it "leaves the refund's fee rebate in place" do
      handle("charge.dispute.closed", dispute_object(amount: 6_000, status: "won"))

      rebates = CanonicalPendingEventMapping
                .where(event_id: event.id)
                .map(&:canonical_pending_transaction)
                .select { |cpt| cpt.memo.to_s.match?(/fee refunded/i) }

      live = rebates.reject { |cpt| CanonicalPendingDeclinedMapping.exists?(canonical_pending_transaction_id: cpt.id) }
      expect(live.size).to eq(1)
    end
  end

  # A dispute in a `warning_*` status is an inquiry: the issuer is asking a
  # question and Stripe has withdrawn nothing. Debiting a teenager then charges
  # them for money nobody has taken.
  describe "an inquiry, before any money moves" do
    it "records the case without touching the operator's payable" do
      expect { handle("charge.dispute.created", dispute_object(status: "warning_needs_response", due_by: nil)) }
        .not_to change { pending_outgoing }

      dispute = Fuime::Dispute.sole
      expect(dispute).to be_early_warning
      expect(dispute.status).to eq("warning_needs_response")
    end

    # The expensive half of getting this wrong. An inquiry that escalates keeps
    # the SAME dispute object and arrives as `updated` — so a rule of "debit only
    # on created" would mean a real chargeback never debits at all, and Fuime
    # pays out money it has lost.
    it "debits when the inquiry escalates into a real chargeback" do
      handle("charge.dispute.created", dispute_object(status: "warning_needs_response", due_by: nil))
      handle("charge.dispute.updated", dispute_object(status: "needs_response"))

      expect(pending_outgoing).to eq(-fee_on(10_000) - 10_000)
    end

    it "debits exactly once however many updates arrive" do
      handle("charge.dispute.created", dispute_object(status: "warning_needs_response", due_by: nil))
      3.times { handle("charge.dispute.updated", dispute_object(status: "under_review")) }

      expect(pending_outgoing).to eq(-fee_on(10_000) - 10_000)
    end

    it "takes nothing when the inquiry simply closes" do
      handle("charge.dispute.created", dispute_object(status: "warning_needs_response", due_by: nil))

      expect { handle("charge.dispute.closed", dispute_object(status: "warning_closed", due_by: nil)) }
        .not_to change { pending_outgoing }
      expect(pending_outgoing).to eq(-fee_on(10_000))
    end
  end

  describe "when Fuime loses" do
    before { handle("charge.dispute.created", dispute_object) }

    it "leaves the debit standing" do
      handle("charge.dispute.closed", dispute_object(status: "lost"))

      expect(pending_outgoing).to eq(-fee_on(10_000) - 10_000)
      dispute = Fuime::Dispute.sole
      expect(dispute).to be_lost
      expect(dispute).not_to be_reinstated
      expect(dispute.closed_at).to be_present
    end
  end

  describe "telling somebody" do
    # The whole point. Before this, `charge.dispute.created` reversed the ledger
    # and notified no human being at all.
    it "alerts ops when a dispute opens" do
      expect { handle("charge.dispute.created", dispute_object) }
        .to have_enqueued_mail(Fuime::DisputeMailer, :ops_alert)
    end

    it "alerts ops again when the outcome lands" do
      handle("charge.dispute.created", dispute_object)

      expect { handle("charge.dispute.closed", dispute_object(status: "won")) }
        .to have_enqueued_mail(Fuime::DisputeMailer, :ops_alert)
    end

    # `dispute.updated` fires for our own evidence submission among other things.
    # An alert that arrives on every one of those is an alert people mute.
    it "stays quiet when nothing about the status changed" do
      handle("charge.dispute.created", dispute_object)

      expect { handle("charge.dispute.updated", dispute_object) }
        .not_to have_enqueued_mail(Fuime::DisputeMailer, :ops_alert)
    end

    it "tells the operator why their payable moved" do
      expect { handle("charge.dispute.created", dispute_object) }
        .to have_enqueued_mail(Fuime::DisputeMailer, :operator_notice)
    end

    # An early warning is the network's heads-up and may never become a
    # chargeback. Ops should see it; a 14-year-old should not be told their
    # money is at risk over something that usually is not.
    it "does not tell the operator about an early warning" do
      expect { handle("charge.dispute.created", dispute_object(status: "warning_needs_response", due_by: nil)) }
        .to have_enqueued_mail(Fuime::DisputeMailer, :ops_alert)
        .and not_enqueue_mail(Fuime::DisputeMailer, :operator_notice)
    end
  end

  # An alert whose template raises is an alert that never arrives, and nothing
  # else here renders one: `have_enqueued_mail` only proves it was queued.
  describe "the alerts themselves" do
    let(:dispute) do
      handle("charge.dispute.created", dispute_object)
      Fuime::Dispute.sole
    end

    it "renders the ops alert with the deadline and the link on it" do
      mail = Fuime::DisputeMailer.with(dispute:).ops_alert

      expect(mail.subject).to include("ACTION NEEDED").and include(event.name)
      expect(mail.body.encoded).to include(dispute.stripe_dispute_id)
      expect(mail.body.encoded).to include("merchant of record")
    end

    it "renders the operator notice without asking a teenager to do anything" do
      create(:organizer_position, user: create(:user, :minor), event:)
      mail = Fuime::DisputeMailer.with(dispute:).operator_notice

      expect(mail.to).to be_present
      body = mail.body.encoded
      expect(body).to include("You do not need to do anything")
      # L5: what moved is what Fuime OWES them, never a balance held anywhere.
      expect(body).not_to match(/\bbank\b|\bdeposit|\bFDIC/i)
    end
  end

  # The Dashboard checkbox list. Losing either of these is how the won-dispute
  # bug comes back, silently.
  it "documents the dispute events the platform endpoint must register" do
    expect(Fuime::PaymentWebhookHandler::HANDLED_TYPES).to include(
      "charge.dispute.created",
      "charge.dispute.updated",
      "charge.dispute.closed"
    )
  end
end
