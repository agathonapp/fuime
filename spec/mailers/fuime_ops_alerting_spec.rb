# frozen_string_literal: true

require "rails_helper"

# Fuime: where operational alerts actually go.
#
# Every example here is about a failure that is SILENT in production —
# `ApplicationMailer.deliver_mail` drops a message with no recipients without
# raising, so "nobody is being told" and "everything is fine" look identical
# from inside the app. That is what made these worth pinning.
RSpec.describe "Fuime operational alerting" do
  # No ClimateControl in this repo; same save-and-restore shape as
  # spec/services/fuime/operator_eligibility_spec.rb.
  def with_env(key, value)
    old = ENV[key]
    ENV[key] = value
    yield
  ensure
    old.nil? ? ENV.delete(key) : ENV[key] = old
  end

  describe ApplicationMailer, ".ops_recipients" do
    it "falls back to Fuime's own inbox rather than to nobody" do
      expect(described_class.ops_recipients).to eq(["support@fuime.com"])
    end

    it "takes a comma-separated list so the person on call changes without a deploy" do
      with_env("FUIME_OPS_EMAIL", "a@fuime.com, b@fuime.com") do
        expect(described_class.ops_recipients).to eq(["a@fuime.com", "b@fuime.com"])
      end
    end
  end

  # Upstream addressed these to Hack Club's Slack notification address and a
  # Hack Club staff member's production public_id. Neither resolves here, so the
  # four scheduled anomaly detectors were warning nobody.
  describe AdminMailer do
    it "sends ledger anomalies to Fuime, not to an empty list" do
      event = create(:event)
      mail = described_class.balance_anomalies(anomalous_events: [event], anomalous_card_grants: [])

      expect(mail.to).to eq(["support@fuime.com"])
    end

    it "does not require an engineer to have an account on the platform they operate" do
      event = create(:event)

      with_env("FUIME_ENGINEER_EMAILS", "oncall@fuime.com") do
        mail = described_class.fee_anomalies(anomalous_events: [event])
        expect(mail.to).to eq(["oncall@fuime.com"])
      end
    end
  end

  # These four public_ids were Hack Club staff. `find_by_public_id` decodes a
  # hashid against THIS app's salt, so on Fuime they resolve to whichever user
  # sits at the decoded integer — and the effect of being on the list is that
  # every email to that person is silently removed from every recipient list.
  describe "the earmuff list" do
    it "is empty, so no Fuime user has their mail silently dropped" do
      expect(ApplicationMailer::EARMUFFED_USER_IDS).to be_empty
    end
  end

  describe Fuime::OpsDigestMailer do
    it "renders, and says what is waiting" do
      create(:event, operator_vetting_status: :unvetted)
      mail = described_class.daily

      expect(mail.to).to eq(["support@fuime.com"])
      expect(mail.subject).to include("waiting")
      expect(mail.body.encoded).to include("cannot sell yet")
    end

    # An absent email means "nothing to do", "the worker is down" and "SMTP is
    # broken" equally well. On a launch week the last two are what you need.
    it "still sends on a quiet day, with the sales heartbeat on it" do
      mail = described_class.daily

      expect(mail.subject).to include("All clear")
      expect(mail.body.encoded).to include("Last 24 hours")
    end

    # The deadline categories are the only ones with a consequence attached to
    # the delay, so they have to survive being skimmed in a subject line.
    it "leads with anything past its deadline" do
      event = create(:event)
      Fuime::Dispute.create!(event:, stripe_dispute_id: "dp_digest_1",
                             stripe_payment_intent_id: "pi_digest_1", amount_cents: 3_000,
                             status: "needs_response", opened_at: 20.days.ago,
                             evidence_due_at: 2.days.ago)

      expect(described_class.daily.subject).to include("OVERDUE")
    end
  end
end
