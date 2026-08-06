# frozen_string_literal: true

require "rails_helper"

# Fuime: the auto-invite that closes the deferred-onboarding loop — the parent
# gets their guardianship link the moment the teen submits an application,
# because the form already collected their email.
RSpec.describe Fuime::GuardianInviteService do
  let(:teen) { create(:user, birthday: 15.years.ago.to_date, verified: true) }

  it "creates the pending guardianship and mails the invite" do
    expect {
      described_class.new(minor: teen, guardian_email: "Pat-Invite@Example.com").run!
    }.to have_enqueued_mail(GuardianshipMailer, :invite)

    guardianship = Guardianship.order(:id).last
    expect(guardianship.minor).to eq(teen)
    expect(guardianship.guardian.email).to eq("pat-invite@example.com")
    expect(guardianship).to be_pending
  end

  it "is idempotent — a second call neither duplicates nor re-mails" do
    first = described_class.new(minor: teen, guardian_email: "pat-invite@example.com").run!
    mails_before = ActiveJob::Base.queue_adapter.enqueued_jobs.size

    expect(described_class.new(minor: teen, guardian_email: "pat-invite@example.com").run!).to eq(first)
    expect(ActiveJob::Base.queue_adapter.enqueued_jobs.size).to eq(mails_before)
    expect(Guardianship.where(minor: teen).count).to eq(1)
  end

  it "refuses self-invites" do
    expect {
      described_class.new(minor: teen, guardian_email: teen.email).run!
    }.to raise_error(described_class::InvalidInvite, /own guardian/)
  end

  describe "on application submission" do
    it "sends the invite from cosigner_email automatically" do
      application = create(:event_application, user: teen, teen_led: true,
                                               cosigner_email: "auto-parent@example.com")
      allow(application).to receive(:ready_to_submit?).and_return(true)

      expect { application.mark_submitted! }
        .to have_enqueued_mail(GuardianshipMailer, :invite)

      guardianship = Guardianship.find_by(minor: teen)
      expect(guardianship).to be_present
      expect(guardianship.guardian.email).to eq("auto-parent@example.com")
    end

    it "does not block submission when the cosigner email is unusable" do
      application = create(:event_application, user: teen, teen_led: true,
                                               cosigner_email: teen.email) # self-invite: refused
      allow(application).to receive(:ready_to_submit?).and_return(true)

      expect { application.mark_submitted! }.not_to raise_error
      expect(application.reload.aasm_state).not_to eq("draft")
      expect(Guardianship.find_by(minor: teen)).to be_nil
    end

    it "sends nothing for a school student" do
      school = create(:event, plan_type: Event::Plan::School)
      venture = create(:event, name: "School Auto Venture", parent: school)
      OrganizerPositionInvite.create!(event: venture, user: teen, sender: teen, role: :member)

      application = create(:event_application, user: teen.reload, teen_led: true,
                                               cosigner_email: "should-not-mail@example.com")
      allow(application).to receive(:ready_to_submit?).and_return(true)

      guardianships_before = Guardianship.count
      invites_before = ActiveJob::Base.queue_adapter.enqueued_jobs
                                      .count { |j| j[:args]&.first == "GuardianshipMailer" }

      application.mark_submitted!

      invites_after = ActiveJob::Base.queue_adapter.enqueued_jobs
                                     .count { |j| j[:args]&.first == "GuardianshipMailer" }
      expect(invites_after).to eq(invites_before)
      expect(Guardianship.count).to eq(guardianships_before)
    end
  end
end
