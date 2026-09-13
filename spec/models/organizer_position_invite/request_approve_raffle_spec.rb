# frozen_string_literal: true

require "rails_helper"

# FUIME-DISABLED: the FIRST Worlds 3D-printer raffle enrolment on invite approval.
#
# Upstream, approving an OrganizerPositionInvite::Request whose requester shared
# a FIRST affiliation with the event auto-enrolled them in Hack Club's
# `first-worlds-2026-printer` giveaway, drawn at the FIRST Robotics World
# Championship. That made this a LIVE path into a Hack Club programme inside a
# feature Fuime keeps — invite requests — so it kept writing Raffle rows for a
# draw that is not ours. The `/raffles` routes are gone too (config/routes.rb).
#
# The original examples pinned the affiliation-MATCH requirement, because an
# earlier upstream implementation granted an entry to any hand-approved
# requester. That distinction no longer exists: nobody is enrolled at all. These
# examples are inverted to pin the disabled state, so restoring the callback
# trips a red suite.
RSpec.describe OrganizerPositionInvite::Request, type: :model do
  describe "#approve! after-callback raffle enrollment" do
    let(:requester) { create(:user, verified: true) }
    let(:event) { create(:event) }

    def build_request_for(event:, requester:)
      link = event.organizer_position_invite_links.create!(
        creator: requester,
        expires_in: 0,
      )
      described_class.create!(requester:, link:)
    end

    it "does not enroll the requester even when the event affiliation matches theirs" do
      requester.affiliations.create!(name: "first", league: "frc", team_number: "1234")
      event.affiliations.create!(name: "first", league: "frc", team_number: "1234")

      request_record = build_request_for(event:, requester:)

      expect {
        request_record.approve!
      }.not_to change {
        Raffle.where(user: requester, program: "first-worlds-2026-printer").count
      }
    end

    it "still approves the request" do
      requester.affiliations.create!(name: "first", league: "frc", team_number: "1234")
      event.affiliations.create!(name: "first", league: "frc", team_number: "1234")

      request_record = build_request_for(event:, requester:)
      request_record.approve!

      expect(request_record.reload).to be_approved
    end

    it "does not enroll the requester when the event has no FIRST affiliation match for them" do
      requester.affiliations.create!(name: "first", league: "frc", team_number: "1234")
      # Event has a FIRST affiliation but for a different team.
      event.affiliations.create!(name: "first", league: "frc", team_number: "9999")

      request_record = build_request_for(event:, requester:)

      expect {
        request_record.approve!
      }.not_to(change {
        Raffle.where(user: requester, program: "first-worlds-2026-printer").count
      })
    end

    it "does not enroll the requester when neither party has a FIRST affiliation" do
      request_record = build_request_for(event:, requester:)

      expect {
        request_record.approve!
      }.not_to(change { Raffle.where(program: "first-worlds-2026-printer").count })
    end

    it "is idempotent — re-approving doesn't create a duplicate raffle entry" do
      requester.affiliations.create!(name: "first", league: "frc", team_number: "1234")
      event.affiliations.create!(name: "first", league: "frc", team_number: "1234")

      request_record = build_request_for(event:, requester:)
      request_record.approve!

      # Even if the after-callback fires twice for some reason, find_or_create_by!
      # must keep the raffle entry count at 1.
      Raffle.find_or_create_by!(user: requester, program: "first-worlds-2026-printer")

      expect(Raffle.where(user: requester, program: "first-worlds-2026-printer").count).to eq(1)
    end
  end
end
