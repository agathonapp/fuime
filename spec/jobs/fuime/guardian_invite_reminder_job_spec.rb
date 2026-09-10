# frozen_string_literal: true

require "rails_helper"

# Fuime: the daily sweep that nudges a parent who has not accepted yet.
#
# The property: only still-pending, still-live tokens get mail, and a replay
# does not send again. Accepted / expired / revoked are silent.
RSpec.describe Fuime::GuardianInviteReminderJob do
  let(:adult) { create(:user, birthday: 40.years.ago.to_date) }
  let(:teen) { create(:user, :minor) }

  it "sends the day-3 reminder and is idle on a second run" do
    create(:guardianship, :due_for_day3_reminder, guardian: adult, minor: teen)

    expect { described_class.perform_now }
      .to have_enqueued_mail(GuardianshipMailer, :invite_reminder)

    expect { described_class.perform_now }
      .not_to have_enqueued_mail(GuardianshipMailer, :invite_reminder)
  end

  it "does not mail accepted or expired invites" do
    create(:guardianship, :active, guardian: adult, minor: teen)
    create(:guardianship, :expired_invite,
           guardian: create(:user, birthday: 41.years.ago.to_date),
           minor: create(:user, :minor))

    expect { described_class.perform_now }
      .not_to have_enqueued_mail(GuardianshipMailer, :invite_reminder)
  end
end
