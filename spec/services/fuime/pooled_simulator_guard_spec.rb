# frozen_string_literal: true

require "rails_helper"

# Fuime: the pooled-account handler is a TEST-MODE SIMULATOR.
#
# Everything it does records a payment that landed in Fuime's own platform balance
# and then credits a venture's ledger for it — the model CLAUDE.md L1 retires,
# because in production it is unlicensed money transmission and aggregation
# outside Connect. The code is kept because it exercises the ledger pipeline
# without a connected account, which is useful in development and nowhere else.
#
# This spec is what makes "test mode only" structural rather than a comment
# asking future readers to be careful.
RSpec.describe Fuime::PaymentWebhookHandler, "live-mode refusal" do
  # A plan that charges, so a recorded payment posts BOTH lines (gross + fee) and
  # "changed by 2" means what it says. The factory defaults to FeeWaived, where
  # the correct posting is one line and the assertion would be measuring the
  # waiver rather than the guard.
  let(:venture) { create(:event, plan_type: Event::Plan::Standard) }

  def payment_intent
    { id: "pi_live_guard", amount_received: 10_00, created: Time.current.to_i,
      metadata: { "fuime_event_id" => venture.id.to_s }
}
  end

  def stripe_event(livemode:)
    Stripe::Event.construct_from(
      id: "evt_live_guard",
      type: "payment_intent.succeeded",
      livemode:,
      data: { object: payment_intent }
    )
  end

  it "refuses to record a live-mode payment" do
    # A live event reaching here means real customer money is sitting in Fuime's
    # platform balance and something upstream is badly misconfigured. Refusing
    # does not un-take the money — it stops Fuime from also representing itself as
    # its custodian.
    expect(Rails.error).to receive(:report).with(
      an_instance_of(described_class::LivePooledPaymentRefused), hash_including(handled: true)
    )

    expect { described_class.new(event: stripe_event(livemode: true)).handle }
      .not_to change(CanonicalPendingTransaction, :count)
  end

  # TWO lines, not one: the pooled path posts the payment and Fuime's cut of it
  # separately (VentureLedger#payment_key and #fee_key), because in that model
  # Fuime received the gross and owed the venture the rest, so the fee has to be
  # visible as its own deduction on a teenager's ledger.
  #
  # This expectation said `by(1)` when written, which is why it is worth naming:
  # the spec was authored in the 2026-08-11 embedded-Connect work whose
  # UPSTREAM_DIVERGENCE entry records "Verification: NOT RUN" — Ruby 3.4.9 was
  # missing locally and the Docker daemon was down. It has never passed. Fixed
  # here rather than left red so the suite has an honest baseline.
  it "still records a test-mode payment" do
    expect { described_class.new(event: stripe_event(livemode: false)).handle }
      .to change(CanonicalPendingTransaction, :count).by(2)
  end

  it "records an event with no livemode field at all" do
    # Fixtures and hand-built events carry no `livemode`. Absence means "not a
    # real Stripe event", which is not the case worth failing closed on — only an
    # explicit `livemode: true` is.
    event = Stripe::Event.construct_from(
      id: "evt_no_livemode", type: "payment_intent.succeeded", data: { object: payment_intent }
    )

    expect { described_class.new(event:).handle }
      .to change(CanonicalPendingTransaction, :count).by(2)
  end
end
