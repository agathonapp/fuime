# frozen_string_literal: true

module Fuime
  module Oncall
    module Checks
      # Fuime: jobs that exhausted every retry and gave up.
      #
      # This is the highest signal-per-line check in the set, and it was
      # previously watched by nobody. Sidekiq retries 25 times over roughly three
      # weeks before a job lands in the dead set, so a row there is not a blip —
      # it is work that was supposed to happen and now never will, with no
      # exception left anywhere a human looks.
      #
      # In this app that includes `Fuime::DeliverWebhookJob` (a founder's
      # integration silently stopped receiving sales), the payment webhook
      # handlers (a sale that never reached a ledger), and the mailers (a
      # guardian invite that was never sent, which stalls an entire onboarding).
      #
      # ── The threshold is one ───────────────────────────────────────────────
      #
      # Not a rate, not a percentage. A single dead job in a payments system is
      # a thing somebody has to look at, and the volume here is low enough that
      # "one" will not be noisy. If that stops being true the right response is
      # to fix the job, not to raise the threshold.
      class DeadJobs < Check
        def call
          dead = ::Sidekiq::DeadSet.new
          return [] if dead.size.zero?

          # A sample rather than the whole set: the incident detail is read on a
          # phone, and the first few are almost always the same class anyway.
          sample = dead.first(5).map do |job|
            { job: job.klass, queue: job.queue, error: job.item["error_class"],
              message: job.item["error_message"].to_s.truncate(200),
              failed_at: job.item["failed_at"]
}
          end

          [finding(
            key: "workers.dead_jobs",
            title: "#{dead.size} background #{'job'.pluralize(dead.size)} died after exhausting every retry",
            # Sev-2 rather than sev-1: by the time a job is dead it has been
            # failing for weeks, so the marginal harm of waiting until morning is
            # small — but it must not be allowed to wait indefinitely, which is
            # what happened before this existed.
            severity: :sev2,
            dead_count: dead.size,
            retry_count: ::Sidekiq::RetrySet.new.size,
            sample:
          )]
        end

      end
    end
  end
end
