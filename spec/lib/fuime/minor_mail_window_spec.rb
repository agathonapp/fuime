# frozen_string_literal: true

require "rails_helper"

# Fuime L7: no mail to a minor between midnight and 6 a.m. local.
RSpec.describe Fuime::MinorMailWindow do
  let(:zone_name) { "America/Los_Angeles" }
  let(:zone) { ActiveSupport::TimeZone[zone_name] }

  describe ".earliest_send_time" do
    it "is now when the local hour is already past the quiet window" do
      now = zone.local(2026, 9, 12, 9, 30, 0)

      expect(described_class.earliest_send_time(now:, zone_name:)).to eq(now)
    end

    it "holds a 1 a.m. send until 6 a.m. the same local morning" do
      now = zone.local(2026, 9, 12, 1, 0, 0)

      result = described_class.earliest_send_time(now:, zone_name:).in_time_zone(zone)
      expect(result.hour).to eq(6)
      expect(result.to_date).to eq(now.to_date)
    end

    it "reads the local hour, not UTC" do
      # 08:00 UTC is 01:00 in Los Angeles — quiet there, fine in UTC. The whole
      # point of naming a zone is that this case is held.
      now = Time.utc(2026, 9, 12, 8, 0, 0)

      expect(described_class.earliest_send_time(now:, zone_name:)).not_to eq(now)
      expect(described_class).to be_quiet(now:, zone_name:)
    end

    it "falls back to the default zone for an unknown name" do
      now = zone.local(2026, 9, 12, 1, 0, 0)

      expect(described_class.earliest_send_time(now:, zone_name: "Not/A_Zone"))
        .to eq(described_class.earliest_send_time(now:, zone_name: described_class::DEFAULT_ZONE))
    end
  end
end
