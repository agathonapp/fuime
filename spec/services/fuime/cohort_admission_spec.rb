# frozen_string_literal: true

require "rails_helper"

# Fuime: admitting a founder that somebody already vouched for.
#
# This class advances three human gates automatically, one of which is the
# vetting decision that the whole merchant-of-record model rests on. So the
# questions here are less "does it work" than "what can it be talked into":
# can a founder admit themselves, can a dead code still admit, can a cap be
# exceeded by fifty people arriving at once, and — the one that matters most —
# does an admitted venture still have to obey the rules everybody else does.
# Tagged merchant-of-record throughout, which is not incidental. Under Connect a
# minor with no guardian cannot have a venture activated at all
# (Event::Application#activate_event!), so an untagged example here would be
# testing admission against a gate that a cohort is not entitled to move — and
# would fail for a reason that has nothing to do with this class.
RSpec.describe Fuime::CohortAdmission, :merchant_of_record do
  let(:organiser) { create(:user, :make_admin, full_name: "Ada Organiser") }

  let(:cohort) do
    Fuime::Cohort.create!(
      name: "Founders Weekend", code: "FOUNDERS26", created_by: organiser,
      rationale: "I'm running this event and I know everyone attending.",
      expires_at: 3.days.from_now, max_members: 50, risk_level: "slight"
    )
  end

  # A founder old enough to clear the operator floor, so these examples are about
  # admission rather than about eligibility.
  let(:founder) { create(:user, :minor, birthday: 16.years.ago.to_date) }

  def application_for(user = founder, in_cohort: cohort)
    create(:event_application, user:, fuime_cohort: in_cohort,
                               name: "Lawn Care", teen_led: true)
  end

  subject(:admit) { described_class.new(application: application_for).call }

  describe "admitting" do
    it "walks all three gates in one go" do
      result = admit

      expect(result).to be_admitted
      expect(result.event).to be_present
      expect(result.event.operator_vetting_status).to eq("approved")
    end

    it "attributes the vetting decision to the person who vouched" do
      event = admit.event

      expect(event.operator_vetted_by).to eq(organiser)
      expect(event.operator_vetted_at).to be_present
    end

    # The note is the reason this is honest rather than a rubber stamp. It has to
    # record what actually happened — a bulk decision by a named person, and their
    # stated basis — and must NOT read as a per-venture judgement nobody made.
    # See Event#record_vetting_decision!'s own warning about prefilled notes.
    it "records what actually happened, not a judgement about this venture" do
      notes = admit.event.operator_vetting_notes

      expect(notes).to include("Founders Weekend")
      expect(notes).to include("FOUNDERS26")
      expect(notes).to include("Ada Organiser")
      expect(notes).to include("I'm running this event")

      # Words that would put an opinion in the reviewer's mouth.
      expect(notes).not_to match(/looks legitimate|low.risk|reviewed and/i)
    end

    it "points the venture at the person who vouched, not at whoever ran the code" do
      expect(admit.event.point_of_contact).to eq(organiser)
    end

    it "stamps the cohort onto the venture so the roster can count it" do
      expect(admit.event.fuime_cohort).to eq(cohort)
      expect(cohort.reload.events).to include(admit.event)
    end
  end

  # The property that makes automatic admission safe. A cohort says "I vouch for
  # these people"; it cannot say "and the rules do not apply to them".
  describe "what admission does NOT buy" do
    it "does not let an under-age operator sell" do
      too_young = create(:user, :minor, birthday: 14.years.ago.to_date)
      event = described_class.new(application: application_for(too_young)).call.event

      expect(event.operator_vetting_status).to eq("approved")
      expect(event.accepts_payments?).to be(false)
      expect(event.selling_blockers).to include(/is 14/)
    end

    it "does not let a venture outside the launch scope sell" do
      event = admit.event
      event.update!(business_category: "crafts")

      expect(event.accepts_payments?).to be(false)
      expect(event.selling_blockers).to include(/service business/)
    end

    # Admission is not a parent. Under MoR the guardian gate is at payout, and a
    # cohort must not reach past it — otherwise "one person vouched for a group"
    # would quietly become "money moves to minors nobody is responsible for".
    it "does not stand in for a guardian when money leaves" do
      event = admit.event
      create(:fuime_payout_method, :verified, event:)

      assessment = Fuime::PayableAssessment.new(
        event:,
        policy: Fuime::PayoutPolicy.new(hold_days: 7, reserve_basis_points: 0,
                                        reserve_window_days: 90, maximum_cents: 250_00,
                                        minimum_cents: 10_00),
        period_end: Date.current
      ).call

      expect(assessment.skip_reason).to include("parent or guardian")
    end
  end

  describe "codes that must not admit" do
    it "refuses an expired cohort" do
      cohort.update_column(:expires_at, 1.hour.ago)

      result = admit

      expect(result).not_to be_admitted
      expect(result.message).to include("expired")
      expect(Event.count).to eq(0)
    end

    it "refuses an archived cohort" do
      cohort.archive!

      expect(admit).not_to be_admitted
      expect(Event.count).to eq(0)
    end

    it "refuses once the cap is reached" do
      cohort.update!(max_members: 1)
      described_class.new(application: application_for).call

      second = described_class.new(
        application: application_for(create(:user, :minor, birthday: 16.years.ago.to_date))
      ).call

      expect(second).not_to be_admitted
      expect(second.message).to include("limit")
    end

    it "does nothing at all for an application with no cohort" do
      result = described_class.new(application: application_for(founder, in_cohort: nil)).call

      expect(result.status).to eq(:not_in_cohort)
      expect(Event.count).to eq(0)
    end

    it "refuses when the cohort has automatic admission turned off" do
      cohort.update!(auto_approve: false)

      expect(admit).not_to be_admitted
      expect(Event.count).to eq(0)
    end
  end

  # A founder pressing Submit must never see an exception because an automatic
  # convenience failed. Their application IS submitted; the three gates it did
  # not pass are the ones a human was doing by hand a week ago.
  describe "when something goes wrong" do
    it "degrades to an ordinary queued application rather than raising" do
      allow_any_instance_of(Event::Application)
        .to receive(:activate_event!).and_raise(ArgumentError, "no venture slot")

      result = nil
      expect { result = admit }.not_to raise_error

      expect(result.status).to eq(:failed)
      expect(result.message).to include("no venture slot")
    end

    it "reports the failure rather than swallowing it" do
      allow_any_instance_of(Event::Application)
        .to receive(:activate_event!).and_raise(ArgumentError, "no venture slot")
      expect(Rails.error).to receive(:report).at_least(:once)

      admit
    end
  end

  # The end-to-end path: submitting an application with a code should be all a
  # founder ever does. If this breaks, the whole feature is a form field that
  # does nothing.
  describe "firing on submission" do
    it "admits the founder when they submit" do
      application = create(:event_application, user: founder, fuime_cohort: cohort,
                                               teen_led: true, name: "Lawn Care")
      allow(application).to receive(:ready_to_submit?).and_return(true)

      application.mark_submitted!

      expect(application.reload.event).to be_present
      expect(application.event.operator_vetting_status).to eq("approved")
    end

    it "leaves an application with no code exactly as it was" do
      application = create(:event_application, user: founder, teen_led: true, name: "Lawn Care")
      allow(application).to receive(:ready_to_submit?).and_return(true)

      application.mark_submitted!

      expect(application.reload.event).to be_nil
    end
  end

end
