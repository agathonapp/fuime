# frozen_string_literal: true

module Fuime
  module Oncall
    module Checks
      # Fuime: can the app read its own database, and is the schema the one the
      # deployed code was written against?
      #
      # The migration half matters more than it looks. Render runs migrations as
      # a release command; if that step fails but the deploy proceeds, the app
      # serves traffic against a schema missing the column the new code selects.
      # The symptom is a 500 on one specific page, which nobody notices until a
      # family hits it.
      class Database < Check
        def call
          findings = []

          started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          ActiveRecord::Base.connection.select_value("SELECT 1")
          elapsed_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round

          # Not a hair trigger. A cold connection on a small Render instance can
          # take a few hundred milliseconds legitimately; a whole second for
          # `SELECT 1` means the pool is exhausted or the instance is swapping,
          # and both of those precede a real outage by minutes.
          if elapsed_ms > 1_000
            findings << finding(
              key: "database.slow",
              title: "Database round-trip took #{elapsed_ms}ms",
              severity: :sev2,
              round_trip_ms: elapsed_ms
            )
          end

          if pending_migrations?
            findings << finding(
              key: "database.pending_migrations",
              title: "Deployed code is running against an un-migrated schema",
              severity: :sev1,
              hint: "The release command did not run or did not finish. Expect 500s on any page touching the new columns."
            )
          end

          findings
        end

        private

        def pending_migrations?
          ActiveRecord::Migration.check_all_pending!
          false
        rescue ActiveRecord::PendingMigrationError
          true
        end

      end
    end
  end
end
