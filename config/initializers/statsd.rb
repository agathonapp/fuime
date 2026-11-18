# frozen_string_literal: true

# Fuime: metrics are opt-in.
#
# Upstream HCB hard-coded STATSD_ADDR to telemetry.hackclub.com:8125 for every
# non-local environment. That had this fork reporting to Hack Club's own
# telemetry (CLAUDE.md Rule 4), and when Hack Club removed that DNS record in
# late October 2026 the `StatsD.increment("startup")` below started raising
# Socket::ResolutionError on every boot: app.fuime.com crash-looped until Render
# suspended it (2026-11-02), and assets:precompile failed every build after.
#
# Now: metrics go over UDP only when STATSD_ADDR is set to a host Fuime runs.
# Without it, production and staging discard them (NullSink), and development
# keeps the gem's default of writing them to the log.
Rails.application.configure do
  statsd_addr = ENV["STATSD_ADDR"].presence

  ENV["STATSD_ENV"] ||= "production" if statsd_addr && !Rails.env.local?
  ENV["STATSD_PREFIX"] ||= "#{Rails.env}.hcb"

  StatsD::Instrument::Environment.setup

  if statsd_addr.nil? && !Rails.env.local?
    StatsD.singleton_client = StatsD::Instrument::Client.new(
      sink: StatsD::Instrument::NullSink.new,
      prefix: ENV["STATSD_PREFIX"]
    )
  end

  StatsD.increment("startup", 1)
end
