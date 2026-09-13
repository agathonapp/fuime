# frozen_string_literal: true

require "rails_helper"

# Fuime: what a teenager who opened the wizard and closed it hears about it.
#
# ── What used to be scheduled ───────────────────────────────────────────────
#
# `after_create_commit` queued four reminders at 1, 2, 7 and 14 days, subject
# "[Action Needed] Complete your Fuime application!", each carrying one of four
# "Did you know?" tips inherited from upstream HCB:
#
#   • a free online donation page for every organization
#   • reimbursement for out-of-pocket expenses
#   • physical and virtual debit cards with Apple Pay and Google Pay
#   • a mobile app for tracking fundraising and spending
#
# Fuime has none of them. Donations, reimbursements and cards are off
# (`DisabledModules`, `Event::Plan::Free`), and there is no app. So the product's
# only re-engagement sequence advertised four things that do not exist, four
# times, to a minor, at whatever hour the queue reached them.
#
# L7 (CLAUDE.md; LEGAL_RESEARCH.md) allows transactional notification of a minor
# and nothing between midnight and 6 a.m. "You left something unfinished" is at
# the edge of transactional on day one and is plainly re-engagement by day
# fourteen, which is why the series is two and not four.
RSpec.describe "reminding a founder about an unfinished draft" do
  let(:teen) { create(:user, :attested_teen, full_name: "Ira Draft") }

  # A complete draft, so `mark_submitted!` is reachable in the example that needs
  # it — `ready_to_submit?` guards the transition.
  def draft_for(user)
    create(
      :event_application,
      user:,
      teen_led: true,
      name: "Ira Bike Repair",
      description: "I fix bikes for people at my school.",
      business_category: "services",
      address_country: "US",
      cosigner_email: "parent-draft@example.com"
    )
  end

  describe "what gets scheduled" do
    it "is two reminders, not four" do
      expect { draft_for(teen) }
        .to have_enqueued_job(Event::ApplicationReminderJob).exactly(2).times
    end

    # The window is applied at SCHEDULE time rather than at send time because
    # `wait_until` is what the queue honours; a job that wakes at 3 a.m. and then
    # decides not to send has already been scheduled inside the quiet hours, and
    # any backend that runs it early has already broken L7.
    it "never schedules a send inside the quiet hours" do
      quiet_hour = ::Fuime::MinorMailWindow.zone.parse("2026-10-04 02:30:00")

      travel_to quiet_hour do
        draft_for(teen)
      end

      scheduled = ActiveJob::Base.queue_adapter.enqueued_jobs
                                 .select { |j| j[:job] == Event::ApplicationReminderJob }
                                 .map { |j| Time.at(j[:at]).in_time_zone(::Fuime::MinorMailWindow.zone) }

      expect(scheduled.size).to eq(2)
      scheduled.each do |at|
        expect(at.hour).to be >= ::Fuime::MinorMailWindow::QUIET_UNTIL_HOUR,
                           "scheduled at #{at} — inside the quiet hours L7 forbids"
      end
    end
  end

  describe "what the job does when it wakes" do
    let(:application) { draft_for(teen) }

    it "mails a draft that is still a draft" do
      expect { Event::ApplicationReminderJob.perform_now(application, 1) }
        .to have_enqueued_mail(Event::ApplicationMailer, :incomplete).once
    end

    it "says nothing once the founder has submitted" do
      application.mark_submitted!

      expect { Event::ApplicationReminderJob.perform_now(application.reload, 1) }
        .not_to have_enqueued_mail(Event::ApplicationMailer, :incomplete)
    end

    # A founder who abandoned one draft and then built a business anyway is not a
    # stalled signup, and chasing them about the abandoned one reads as the
    # product having lost track of them.
    it "says nothing to a founder who already has a venture" do
      create(:organizer_position, user: teen, event: create(:event))

      expect { Event::ApplicationReminderJob.perform_now(application.reload, 1) }
        .not_to have_enqueued_mail(Event::ApplicationMailer, :incomplete)
    end
  end

  describe "what the reminder says" do
    let(:application) { draft_for(teen) }

    # Named rather than pattern-matched: each of these is a product Fuime
    # deliberately does not have, and the failure this guards against is somebody
    # reinstating a tip from upstream without checking.
    let(:absent_products) do
      [
        /donation page/i,
        /reimburse/i,
        /debit card/i,
        /Apple Pay/i,
        /Google Pay/i,
        /mobile app/i,
        /\bour app\b/i
      ]
    end

    it "advertises nothing Fuime does not have" do
      (1..3).each do |tip|
        body = Event::ApplicationMailer.with(application:, tip_number: tip).incomplete.body.to_s

        absent_products.each do |absent|
          expect(body).not_to match(absent), "tip #{tip} advertises #{absent.source}"
        end
      end
    end

    it "does not demand anything in the subject line" do
      mail = Event::ApplicationMailer.with(application:, tip_number: 1).incomplete

      expect(mail.subject).not_to include("Action Needed")
      expect(mail.subject).to include("still a draft")
    end

    # `/setup` resumes from the database, so the link works on a device that
    # never held the wizard's session cookie. The old link went to the
    # application status page, which for a wizard draft is a form the founder
    # has never seen.
    it "sends them back to the wizard, not to the old application page" do
      body = Event::ApplicationMailer.with(application:, tip_number: 1).incomplete.body.to_s

      expect(body).to include(Rails.application.routes.url_helpers.setup_url)
    end
  end
end
