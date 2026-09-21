# frozen_string_literal: true

module Fuime
  module Oncall
    # Fuime: run every check, reconcile what they found against the open
    # incidents, then hand the result to the pager.
    #
    # ── The three rules that keep this from becoming noise ─────────────────
    #
    # 1. **A check that RAISES is not a check that found nothing.** If
    #    Checks::Stripe throws, Stripe's health is unknown — not good. So an
    #    exception raises an incident about the check itself and, critically,
    #    leaves that check's existing incidents open. Auto-resolving them would
    #    mean a broken detector silently closes the outage it was detecting.
    #
    # 2. **Absence of a finding is a resolution.** A check that ran cleanly and
    #    did not report key K is asserting K is fixed, so K auto-resolves. This
    #    is what stops the incident list from being a graveyard that nobody
    #    trusts enough to read.
    #
    # 3. **One check's failure must not stop the others.** The loop is
    #    individually rescued. A sweep that aborts halfway through on the first
    #    exception would mean the Stripe outage hides the dispute deadline.
    class Sweep
      Result = Struct.new(:raised, :resolved, :errored, :checked, keyword_init: true)

      def self.run!(checks: Check.all, page: true)
        new(checks:, page:).run!
      end

      def initialize(checks: Check.all, page: true)
        @checks = checks
        @page = page
      end

      def run!
        result = Result.new(raised: [], resolved: [], errored: [], checked: [])

        @checks.each do |klass|
          result.checked << klass.check_name

          begin
            findings = Array(klass.new.call)
          rescue => e
            result.errored << klass.check_name
            record_check_failure(klass, e)
            # Rule 1: do NOT reconcile. This check's incidents stay as they are.
            next
          end

          # The check ran, so its previous complaint about itself is over.
          ::Fuime::Incident.auto_resolve!(key: check_failure_key(klass))

          findings.each do |f|
            incident = ::Fuime::Incident.raise!(
              key: f.key, check_name: klass.check_name, title: f.title,
              severity: f.severity, detail: (f.detail || {}).deep_stringify_keys
            )
            result.raised << incident if incident
          end

          # Rule 2.
          live_keys = ::Fuime::Incident.live.where(check_name: klass.check_name).pluck(:key)
          (live_keys - findings.map(&:key)).each do |stale_key|
            resolved = ::Fuime::Incident.auto_resolve!(key: stale_key)
            result.resolved << resolved if resolved
          end
        end

        Pager.dispatch! if @page

        Rails.logger.info(
          "[Fuime::Oncall] swept #{result.checked.size} checks: " \
          "#{result.raised.size} raised, #{result.resolved.size} resolved, #{result.errored.size} errored"
        )

        result
      end

      private

      def check_failure_key(klass) = "oncall.check_failed.#{klass.check_name}"

      # A detector that cannot run is itself an incident, at the severity of the
      # thing it was watching — a Stripe check that will not run leaves money-in
      # unmonitored, and that is not a sev-3 just because the symptom is a
      # backtrace rather than an outage.
      def record_check_failure(klass, error)
        Rails.error.report(error, handled: true, context: { check: klass.check_name })

        ::Fuime::Incident.raise!(
          key: check_failure_key(klass),
          check_name: klass.check_name,
          title: "The #{klass.check_name.humanize.downcase} check is failing to run",
          severity: :sev2,
          detail: {
            "error_class" => error.class.name,
            "error"       => error.message.to_s.truncate(300),
            "backtrace"   => Array(error.backtrace).first(5),
            "impact"      => "Whatever this check watches is currently unmonitored."
          }
        )
      end

    end
  end
end
