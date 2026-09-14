# frozen_string_literal: true

require "rails_helper"

# Fuime: telling a founder's own server about their sales.
#
# PADDLE_GAP_ANALYSIS §3.8 called this the first-order developer gap. Most of
# what is pinned here is not the happy path — it is the two things that make an
# outbound webhook dangerous rather than merely useful: it is a server-side
# fetch to a user-supplied address (SSRF), and it carries a minor's sale data to
# a third party.
RSpec.describe "outbound webhooks", :merchant_of_record do
  let(:event) { create(:event) }

  def endpoint(url: "https://hooks.example.com/fuime")
    Fuime::WebhookEndpoint.create!(event:, url:)
  end

  describe Fuime::WebhookEndpoint do
    it "mints a secret the founder never has to invent" do
      expect(endpoint.secret).to start_with(Fuime::WebhookEndpoint::SECRET_PREFIX)
    end

    it "refuses plaintext http — a sale payload names a venture and an amount" do
      bad = Fuime::WebhookEndpoint.new(event:, url: "http://hooks.example.com/x")

      expect(bad).not_to be_valid
      expect(bad.errors[:url].join).to match(/https/)
    end

    # The textbook SSRF shape: Fuime would make these requests from inside its
    # own perimeter, on a user's instruction.
    it "refuses addresses that reach inside the network" do
      [
        "https://localhost/x", "https://127.0.0.1/x", "https://10.0.0.5/x",
        "https://192.168.1.1/x", "https://169.254.169.254/latest/meta-data/"
      ].each do |url|
        blocked = Fuime::WebhookEndpoint.new(event:, url:)
        expect(blocked).not_to be_valid, "#{url} was accepted"
        expect(blocked.errors[:url].join).to match(/private address/)
      end
    end

    it "caps how many places a venture's sale data is fanned out to" do
      Fuime::WebhookEndpoint::MAX_ENDPOINTS_PER_EVENT.times do |i|
        Fuime::WebhookEndpoint.create!(event:, url: "https://hooks.example.com/#{i}")
      end

      extra = Fuime::WebhookEndpoint.new(event:, url: "https://hooks.example.com/one-more")
      expect(extra).not_to be_valid
    end
  end

  describe Fuime::WebhookEmitter do
    it "queues a delivery per enabled endpoint, sharing one event id" do
      a = endpoint(url: "https://hooks.example.com/a")
      b = endpoint(url: "https://hooks.example.com/b")

      deliveries = described_class.emit(
        event:, event_type: described_class::SALE_COMPLETED, data: { amount_cents: 500 }
      )

      expect(deliveries.size).to eq(2)
      expect(deliveries.map(&:event_id).uniq.size).to eq(1)
      expect(deliveries.map(&:endpoint)).to contain_exactly(a, b)
    end

    it "skips a disabled endpoint" do
      endpoint.disable!

      expect(described_class.emit(event:, event_type: described_class::SALE_COMPLETED, data: {}))
        .to be_empty
    end

    # A replayed Stripe event reaching the emitter twice must not double-notify.
    it "is idempotent on the event id" do
      endpoint

      2.times do
        described_class.emit(event:, event_type: described_class::SALE_COMPLETED,
                             data: {}, idempotency_key: "evt_sale_pi_123")
      end

      expect(Fuime::WebhookDelivery.where(event_id: "evt_sale_pi_123").count).to eq(1)
    end

    it "refuses an event type nobody agreed to publish" do
      endpoint

      expect(described_class.emit(event:, event_type: "venture.secrets.leaked", data: {}))
        .to be_empty
    end

    # Every caller is on a money path. A founder's broken endpoint must never
    # stop a sale landing on the ledger.
    it "never raises, whatever goes wrong underneath" do
      endpoint
      allow(Fuime::WebhookDelivery).to receive(:create!).and_raise("boom")
      expect(Rails.error).to receive(:report)

      expect {
        described_class.emit(event:, event_type: described_class::SALE_COMPLETED, data: {})
      }.not_to raise_error
    end
  end

  describe Fuime::WebhookDelivery do
    let(:delivery) do
      Fuime::WebhookDelivery.create!(endpoint: endpoint, event_id: "evt_1",
                                     event_type: "sale.completed", payload: {},
                                     next_attempt_at: Time.current)
    end

    it "backs off further on each failure" do
      delivery.record_failure!(error: "HTTP 500")
      first = delivery.next_attempt_at

      delivery.record_failure!(error: "HTTP 500")
      expect(delivery.next_attempt_at).to be > first
      expect(delivery).not_to be_failed
    end

    it "gives up after the ladder rather than retrying a dead host forever" do
      Fuime::WebhookDelivery::MAX_ATTEMPTS.times { delivery.record_failure!(error: "HTTP 500") }

      expect(delivery).to be_failed
      expect(delivery.next_attempt_at).to be_nil
    end

    it "stops retrying once delivered" do
      delivery.record_success!(response_code: 200)

      expect(delivery).to be_delivered
      expect(delivery.next_attempt_at).to be_nil
      expect(delivery.endpoint.reload.last_delivered_at).to be_present
    end
  end
end
