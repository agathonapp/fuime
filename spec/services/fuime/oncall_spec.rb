# frozen_string_literal: true

require "rails_helper"

# Fuime: the on-call pager.
#
# Nearly every example here pins a behaviour whose failure mode is SILENCE. That
# is the recurring shape of alerting bugs in this codebase — AdminMailer
# addressed to an unset credential, `deliver_mail` returning early on an empty
# recipient list, EARMUFFED_USER_IDS subtracting real users from every recipient
# list — and in all three the system reported perfect health precisely because
# it was doing nothing. A pager inherits that failure mode by default and
# inherits it worse, because it is trusted more.
#
# So the tests worth having are not "does it send when something breaks". They
# are "does it still send on the second occurrence", "does it stop when
# acknowledged", "does a broken detector close the outage it was detecting", and
# "does a page over a public relay leak a venture's name".
RSpec.describe "Fuime on-call" do
  describe Fuime::Oncall::Responder do
    # A roster that looks staffed and reaches nobody is the worst of both worlds:
    # it removes the prompt to fix it.
    it "refuses a responder nobody can reach" do
      responder = described_class.new(name: "Unreachable")

      expect(responder).not_to be_valid
      expect(responder.errors.full_messages.join).to include("not on call")
    end

    it "distinguishes being on the roster from being wakeable" do
      email_only = described_class.create!(name: "Accountant", email: "books@fuime.com")
      pageable = described_class.create!(name: "Founder", email: "f@fuime.com", phone_number: "+14155551234")

      expect(email_only).not_to be_pageable
      expect(pageable).to be_pageable
    end

    # Severity gates the CHANNEL, not the recipient. Escalating a sev-3 by adding
    # more people to it is how a team learns to mute the tool.
    it "rings the phone only for a sev-1" do
      responder = described_class.create!(
        name: "On call", email: "o@fuime.com", phone_number: "+14155551234",
        push_kind: "ntfy", push_url: "https://ntfy.sh/topic"
      )

      expect(responder.channels_for(:sev1)).to include(:voice)
      expect(responder.channels_for(:sev2)).not_to include(:voice)
      expect(responder.channels_for(:sev3)).to eq([:email])
    end

    # A bare ntfy.sh topic is readable by anyone who guesses the name, and Fuime's
    # incidents carry the names of businesses run by minors.
    it "treats an unauthenticated relay as public" do
      public_topic = described_class.create!(name: "A", email: "a@fuime.com",
                                             push_kind: "ntfy", push_url: "https://ntfy.sh/guessable")
      private_topic = described_class.create!(name: "B", email: "b@fuime.com", push_kind: "ntfy",
                                              push_url: "https://ntfy.sh/private", push_credential: "tok_123")

      expect(public_topic).not_to be_push_private
      expect(private_topic).to be_push_private
    end
  end

  describe Fuime::Incident do
    def raise_incident(**overrides)
      described_class.raise!(
        **{ key: "test.thing", check_name: "workers", title: "Something broke", severity: :sev2 }.merge(overrides)
      )
    end

    # Without this, a check on a 5-minute schedule finding the same broken thing
    # creates 288 incidents a day and the reader writes a filter rule — which is
    # still there for the next, different outage.
    it "raises one incident per problem, however many times the check runs" do
      first = raise_incident
      second = raise_incident(title: "Something broke, still")

      expect(second.id).to eq(first.id)
      expect(described_class.live.count).to eq(1)
      expect(first.reload.title).to eq("Something broke, still")
    end

    # A check that flaps between severities should be treated as the worst it
    # reached until a human closes it, not as whatever it happened to say last.
    it "escalates severity but never lowers it" do
      raise_incident(severity: :sev2)
      incident = raise_incident(severity: :sev1)
      expect(incident.severity).to eq("sev1")

      incident = raise_incident(severity: :sev3)
      expect(incident.severity).to eq("sev1")
    end

    it "keeps resolved incidents so the same problem can recur" do
      first = raise_incident
      described_class.auto_resolve!(key: "test.thing")
      second = raise_incident

      expect(second.id).not_to eq(first.id)
      expect(described_class.where(key: "test.thing").count).to eq(2)
    end

    # This is the contract that makes acknowledging worth doing. If pages keep
    # arriving after "I am on it", the only way left to stop them is to mute the
    # channel — and a muted channel is what the next incident arrives on.
    it "stops paging once acknowledged" do
      incident = raise_incident(severity: :sev1)
      incident.update!(last_paged_at: 1.hour.ago)
      expect(incident).to be_page_due

      incident.acknowledge!
      expect(incident).not_to be_page_due
    end

    it "throttles repeat pages to the severity's interval" do
      incident = raise_incident(severity: :sev1)
      incident.update!(last_paged_at: 2.minutes.ago)
      expect(incident).not_to be_page_due

      incident.update!(last_paged_at: 11.minutes.ago)
      expect(incident).to be_page_due
    end

    it "climbs the roster while a sev-1 goes unacknowledged" do
      incident = raise_incident(severity: :sev1, key: "test.escalating")
      incident.update!(opened_at: 40.minutes.ago)

      expect(incident.target_escalation_position).to be > 1
    end

    # ── The content rules ────────────────────────────────────────────────────
    #
    # A page lands on a lock screen, having travelled through a third party. The
    # rule is that it says what BROKE and never who it happened to.
    describe "what a page is allowed to say" do
      let(:incident) do
        raise_incident(key: "test.leaky", title: "42 webhook deliveries failed to Maya's Cookies")
      end

      it "withholds the title entirely from an unauthenticated relay" do
        expect(incident.page_title(private: false)).not_to include("Maya")
        expect(incident.page_text(private: false)).not_to include("Maya")
      end

      it "names the problem on an authenticated one" do
        expect(incident.page_title(private: true)).to include("Maya's Cookies")
      end

      # The ack token is a capability: anyone holding it can silence this
      # incident's repaging. Acceptable on an authenticated relay, not on a topic
      # anybody can read.
      it "withholds the acknowledgement link from a public relay" do
        expect(incident.page_text(private: false)).not_to include(incident.ack_token)
        expect(incident.page_text(private: true)).to include(incident.ack_token)
      end

      # Spoken by Twilio at 3am to somebody who has just woken up.
      it "speaks without ids or punctuation a speech engine would mangle" do
        spoken = incident.page_spoken

        expect(spoken).to include("severity 2")
        expect(spoken).not_to include("_")
        expect(spoken).not_to match(/https?:\/\//)
      end
    end
  end

  describe Fuime::Oncall::Sweep do
    # A detector that cannot run has NOT reported health. Auto-resolving its
    # incidents would mean a broken check silently closes the outage it was
    # detecting — the single most dangerous behaviour this class could have.
    it "does not close a check's incidents when that check is failing to run" do
      failing = Class.new(Fuime::Oncall::Check) do
        def self.check_name = "workers"
        def call = raise(StandardError, "boom")
      end

      Fuime::Incident.raise!(key: "workers.none_running", check_name: "workers",
                             title: "No workers", severity: :sev1)

      described_class.run!(checks: [failing], page: false)

      expect(Fuime::Incident.live.find_by(key: "workers.none_running")).to be_present
      expect(Fuime::Incident.live.find_by(key: "oncall.check_failed.workers")).to be_present
    end

    # The other half: a check that DID run and did not report a key is asserting
    # that key is fixed. Without this the incident list becomes a graveyard
    # nobody trusts enough to read.
    it "closes an incident the check stopped reporting" do
      clean = Class.new(Fuime::Oncall::Check) do
        def self.check_name = "workers"
        def call = []
      end

      Fuime::Incident.raise!(key: "workers.none_running", check_name: "workers",
                             title: "No workers", severity: :sev1)

      described_class.run!(checks: [clean], page: false)

      incident = Fuime::Incident.find_by(key: "workers.none_running")
      expect(incident).to be_status_resolved
      # Recorded as auto-resolved rather than looking like a human closing it: a
      # check that opens and auto-resolves twenty times is itself the bug.
      expect(incident.auto_resolved).to be(true)
    end

    it "keeps going when one check explodes" do
      exploding = Class.new(Fuime::Oncall::Check) do
        def self.check_name = "exploding"
        def call = raise(StandardError, "boom")
      end
      working = Class.new(Fuime::Oncall::Check) do
        def self.check_name = "working"
        def call = [Fuime::Oncall::Check::Finding.new(key: "working.bad", title: "Bad", severity: :sev2)]
      end

      result = described_class.run!(checks: [exploding, working], page: false)

      expect(result.errored).to eq(["exploding"])
      expect(Fuime::Incident.live.find_by(key: "working.bad")).to be_present
    end
  end

  describe Fuime::Oncall::Pager do
    let(:incident) do
      Fuime::Incident.raise!(key: "test.page", check_name: "workers",
                             title: "Broken", severity: :sev2)
    end

    # "There was nobody to page" is the single most important fact about an
    # incident nobody answered, and the hardest to reconstruct later.
    it "records that there was nobody to page rather than skipping silently" do
      described_class.page!(incident)

      notification = incident.notifications.last
      expect(notification.status).to eq("failed")
      expect(notification.error).to include("No responder is on call")
      expect(incident.reload.page_count).to eq(1)
    end

    it "writes down every attempt, so 'did the page land' is a query" do
      Fuime::Oncall::Responder.create!(name: "On call", email: "o@fuime.com", escalation_position: 1)

      described_class.page!(incident)

      expect(incident.notifications.pluck(:channel)).to include("email")
      expect(incident.notifications.last.status).to eq("delivered")
    end

    # Escalation ADDS people. Handing over assumes the first responder is
    # unavailable, when the commonest reason for a missed page is that the page
    # never arrived — and handing over would stop retrying the one channel that
    # might still work.
    it "keeps paging position 1 when it escalates to position 2" do
      first = Fuime::Oncall::Responder.create!(name: "First", email: "1@fuime.com", escalation_position: 1)
      second = Fuime::Oncall::Responder.create!(name: "Second", email: "2@fuime.com", escalation_position: 2)

      incident.update!(severity: :sev1, opened_at: 40.minutes.ago)
      described_class.page!(incident)

      paged = incident.notifications.map(&:responder_id)
      expect(paged).to include(first.id, second.id)
    end
  end

  describe Fuime::Oncall::Checks::Alerting do
    # The check that watches the watchman. Its own failure mode is the one this
    # whole subsystem exists to eliminate, so it is worth more coverage than the
    # checks that merely watch Stripe.
    it "treats an empty roster as a sev-1 in its own right" do
      finding = described_class.new.call.find { |f| f.key == "alerting.no_responders" }

      # Sev-1 because an empty roster means every FUTURE sev-1 goes nowhere.
      # It is the outage that hides all the others.
      expect(finding).to be_present
      expect(finding.severity).to eq(:sev1)
    end

    it "notices a roster of people who cannot be woken" do
      Fuime::Oncall::Responder.create!(name: "Email only", email: "e@fuime.com")

      keys = described_class.new.call.map(&:key)

      expect(keys).to include("alerting.nobody_pageable")
      expect(keys).not_to include("alerting.no_responders")
    end

    # A channel that failed every time it was tried is a channel you do not
    # have — and the point is to learn that BEFORE the outage that depends on it.
    #
    # This also pins a Rails behaviour the check quietly relies on: for an
    # integer-backed enum, `group(:channel, :status).count` returns the enum's
    # STRING value in the key. If that ever changes, the comparison below
    # silently stops matching and the check goes quiet — which is exactly the
    # failure it was written to catch.
    it "notices a channel that has failed every time for a day" do
      responder = Fuime::Oncall::Responder.create!(name: "On call", email: "o@fuime.com",
                                                   push_kind: "ntfy", push_url: "https://ntfy.sh/t")
      incident = Fuime::Incident.raise!(key: "test.dead_channel", check_name: "workers",
                                        title: "Broken", severity: :sev2)
      3.times do
        Fuime::IncidentNotification.create!(incident:, responder:, channel: "push",
                                            status: :failed, attempted_at: 1.hour.ago)
      end

      finding = described_class.new.call.find { |f| f.key == "alerting.channel_dead.push" }

      expect(finding).to be_present
      expect(finding.detail[:attempts]).to eq(3)
    end

    # Regression: a "nobody to page" row has no responder, and counting it as a
    # channel failure would report a dead push relay when the real problem is an
    # empty roster — sending somebody to debug the wrong thing at 3am.
    it "does not mistake an empty roster for a dead push channel" do
      incident = Fuime::Incident.raise!(key: "test.nobody", check_name: "workers",
                                        title: "Broken", severity: :sev2)
      Fuime::Oncall::Pager.page!(incident)

      keys = described_class.new.call.map(&:key)

      expect(keys).to include("alerting.no_responders")
      expect(keys).not_to include("alerting.channel_dead.push")
    end

    it "stays quiet about a channel that sometimes works" do
      responder = Fuime::Oncall::Responder.create!(name: "On call", email: "o@fuime.com",
                                                   push_kind: "ntfy", push_url: "https://ntfy.sh/t")
      incident = Fuime::Incident.raise!(key: "test.flaky", check_name: "workers",
                                        title: "Broken", severity: :sev2)
      Fuime::IncidentNotification.create!(incident:, responder:, channel: "push",
                                          status: :failed, attempted_at: 1.hour.ago)
      Fuime::IncidentNotification.create!(incident:, responder:, channel: "push",
                                          status: :delivered, attempted_at: 30.minutes.ago)

      keys = described_class.new.call.map(&:key)

      expect(keys).not_to include("alerting.channel_dead.push")
    end
  end

  describe Fuime::Oncall::Checks::Obligations do
    let(:event) { create(:event) }

    # A dispute nobody answers by its deadline is lost by default, and under
    # merchant of record Fuime pays it while the teenager has already been
    # debited. It is the only thing in the check set where another night of
    # delay changes the outcome, which is why it is the sev-1.
    it "raises a sev-1 for a chargeback deadline that has already passed" do
      Fuime::Dispute.create!(event:, stripe_dispute_id: "dp_overdue", stripe_payment_intent_id: "pi_1",
                             amount_cents: 5_000, status: "needs_response",
                             opened_at: 20.days.ago, evidence_due_at: 2.days.ago)

      finding = described_class.new.call.find { |f| f.key == "obligations.disputes_overdue" }

      expect(finding).to be_present
      expect(finding.severity).to eq(:sev1)
    end

    # An incident raised the day a dispute is due is useless — assembling
    # evidence takes longer than that. The warning has to arrive while there is
    # still time to act or it is not a warning.
    it "warns while there is still time to do something about it" do
      Fuime::Dispute.create!(event:, stripe_dispute_id: "dp_soon", stripe_payment_intent_id: "pi_2",
                             amount_cents: 5_000, status: "needs_response",
                             opened_at: 1.day.ago, evidence_due_at: 2.days.from_now)

      finding = described_class.new.call.find { |f| f.key == "obligations.disputes_due_soon" }

      expect(finding).to be_present
      expect(finding.severity).to eq(:sev2)
    end

    it "says nothing when every deadline is comfortably away" do
      Fuime::Dispute.create!(event:, stripe_dispute_id: "dp_far", stripe_payment_intent_id: "pi_3",
                             amount_cents: 5_000, status: "needs_response",
                             opened_at: 1.day.ago, evidence_due_at: 20.days.from_now)

      expect(described_class.new.call).to be_empty
    end
  end

  describe Fuime::Oncall::Channels::Push do
    let(:incident) do
      Fuime::Incident.raise!(key: "test.push", check_name: "workers",
                             title: "Maya's Cookies cannot take payments", severity: :sev1)
    end

    # ── Priority is the entire feature ──────────────────────────────────────
    #
    # A push notification at default priority is swallowed by Do Not Disturb.
    # It is delivered, the relay reports success, this app records success — and
    # nobody hears it. Pinning the header is pinning the difference between a
    # page and a rumour.
    it "sends an ntfy sev-1 at maximum priority" do
      responder = Fuime::Oncall::Responder.create!(
        name: "On call", push_kind: "ntfy", push_url: "https://ntfy.sh/private-topic",
        push_credential: "tok_abc"
      )
      stub = stub_request(:post, "https://ntfy.sh/private-topic").to_return(status: 200)

      result = described_class.new(responder:, incident:).deliver!

      expect(result.ok).to be(true)
      expect(stub.with { |req| req.headers["Priority"] == "5" }).to have_been_made
    end

    it "does not shout for a sev-3, which belongs in the digest" do
      responder = Fuime::Oncall::Responder.create!(name: "On call", push_kind: "ntfy",
                                                   push_url: "https://ntfy.sh/t", push_credential: "tok")
      incident.update!(severity: :sev3)
      stub = stub_request(:post, "https://ntfy.sh/t").to_return(status: 200)

      described_class.new(responder:, incident:).deliver!

      expect(stub.with { |req| req.headers["Priority"] == "3" }).to have_been_made
    end

    # A bare ntfy topic is readable by anyone who guesses the name, and this
    # incident names a business run by a minor.
    it "strips the venture's name when the relay is unauthenticated" do
      responder = Fuime::Oncall::Responder.create!(name: "On call", push_kind: "ntfy",
                                                   push_url: "https://ntfy.sh/guessable")
      stub = stub_request(:post, "https://ntfy.sh/guessable").to_return(status: 200)

      described_class.new(responder:, incident:).deliver!

      expect(stub.with { |req|
        !req.body.include?("Maya") && !req.headers["Title"].to_s.include?("Maya")
      }).to have_been_made
    end

    # Pushover rejects an emergency-priority message outright if it has no retry
    # cadence and expiry, so the sev-1 path would fail entirely without these.
    it "sends a Pushover sev-1 at emergency priority with a retry cadence" do
      responder = Fuime::Oncall::Responder.create!(
        name: "On call", push_kind: "pushover",
        push_url: "https://api.pushover.net/1/messages.json", push_credential: "apptoken:userkey"
      )
      stub = stub_request(:post, "https://api.pushover.net/1/messages.json").to_return(status: 200)

      described_class.new(responder:, incident:).deliver!

      expect(stub.with { |req|
        body = Rack::Utils.parse_nested_query(req.body)
        body["priority"] == "2" && body["retry"].present? && body["expire"].present? &&
          body["token"] == "apptoken" && body["user"] == "userkey"
      }).to have_been_made
    end

    # A relay that is down must produce a recorded failure, never an exception
    # that takes the rest of the channels down with it.
    it "reports a failure rather than raising when the relay is down" do
      responder = Fuime::Oncall::Responder.create!(name: "On call", push_kind: "ntfy",
                                                   push_url: "https://ntfy.sh/t")
      stub_request(:post, "https://ntfy.sh/t").to_timeout

      result = described_class.new(responder:, incident:).deliver!

      expect(result.ok).to be(false)
      expect(result.error).to be_present
    end
  end

  describe ApplicationMailer, ".ops_recipients" do
    # The original complaint this whole feature came from: an admin held every
    # permission in the console and still never learned that a chargeback had
    # arrived, because admin status and alert routing had no connection at all.
    it "routes the digest to the roster, not only to an environment variable" do
      Fuime::Oncall::Responder.create!(name: "Rushil", email: "rushil@fuime.com")

      expect(described_class.ops_recipients).to include("rushil@fuime.com")
    end

    it "still falls back to the shared inbox when the roster is empty" do
      expect(described_class.ops_recipients).to eq(["support@fuime.com"])
    end

    it "honours somebody who wants the digest but not to be woken" do
      Fuime::Oncall::Responder.create!(name: "Digest only", email: "d@fuime.com", receives_pages: false)

      expect(described_class.ops_recipients).to include("d@fuime.com")
      expect(Fuime::Oncall::Responder.paging).to be_empty
    end

    # A lookup that raises here would be the most ironic outage in this
    # codebase: alerts failing to send because the alert-routing table broke.
    it "degrades to the fallback rather than raising if the roster cannot be read" do
      allow(Fuime::Oncall::Responder).to receive(:digesting).and_raise(ActiveRecord::StatementInvalid, "no table")

      expect(described_class.ops_recipients).to eq(["support@fuime.com"])
    end
  end

  describe Fuime::OpsDigestMailer do
    it "reaches the person on the roster" do
      Fuime::Oncall::Responder.create!(name: "Rushil", email: "rushil@fuime.com")

      expect(described_class.daily.to).to include("rushil@fuime.com")
    end
  end
end
