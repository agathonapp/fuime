# frozen_string_literal: true

module Fuime
  module Oncall
    # Fuime: the base class for "is this thing broken?".
    #
    # A check is a plain object with one job: look at the world and return zero
    # or more findings. It does not page, does not write incidents, and does not
    # know what severity means operationally — the sweep does all of that. That
    # separation is what makes a check safe to run from `/up`, from a rake task,
    # and from a spec without any of them sending a real page.
    #
    # ── Returning an empty array is a positive statement ───────────────────────
    #
    # "No findings" means the check LOOKED and saw nothing wrong, and the sweep
    # acts on it: any open incident this check previously raised is auto-resolved.
    # So a check that cannot do its job must raise, not return `[]` — otherwise a
    # Stripe outage that makes the Stripe check throw would read as Stripe being
    # healthy, which is the exact inversion this subsystem exists to prevent.
    # `Sweep` catches the exception and raises an incident about the check itself.
    #
    # ── Why checks are cheap and dumb ─────────────────────────────────────────
    #
    # Every check here runs unattended, on a schedule, against production, with
    # nobody watching. A check that is slow blocks the ones behind it; a check
    # that is clever is a check whose false positives nobody can reason about at
    # 3am. Prefer a query with an obvious threshold over an inference.
    class Check
      # What a check found. `key` is the stable identity of the PROBLEM — the
      # same broken thing must produce the same key on every run, or the
      # deduplication in Fuime::Incident does nothing and the pager turns into a
      # mailing list.
      Finding = Struct.new(:key, :title, :severity, :detail, keyword_init: true) do
        # Defaults spelled out rather than patched on after `super`: a Finding is
        # built from three different places (the `finding` helper, the health
        # endpoint, specs) and a nil severity reaching Fuime::Incident would
        # decide how loudly somebody is woken.
        def initialize(key:, title:, severity: :sev2, detail: {})
          super(key:, title:, severity:, detail:)
        end
      end

      # Registered in escalating order of cost: infrastructure first, because if
      # the database is gone every check after it will fail in a less legible
      # way.
      def self.all
        [
          Checks::Database,
          Checks::Redis,
          Checks::Workers,
          Checks::DeadJobs,
          Checks::Stripe,
          Checks::MoneyIn,
          Checks::WebhookDeliveries,
          Checks::Obligations,
          Checks::Alerting,
        ]
      end

      # The subset safe to run inside a web request, for `/up`. Anything that
      # makes a network call to a third party is excluded: a slow Stripe is not
      # a reason for a load balancer to pull the app out of rotation, and a
      # health endpoint that can hang is a health endpoint that causes outages.
      def self.infrastructure
        [Checks::Database, Checks::Redis, Checks::Workers]
      end

      def self.check_name = name.demodulize.underscore

      delegate :check_name, to: :class

      def call
        raise NotImplementedError
      end

      private

      def finding(key:, title:, severity: :sev2, **detail)
        Finding.new(key:, title:, severity:, detail:)
      end

    end
  end
end
