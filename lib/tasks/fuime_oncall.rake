# frozen_string_literal: true

# Fuime: on-call from a shell.
#
# The console at /admin/oncall is the everyday surface. These exist for the two
# situations where it is not available: the first setup on a fresh deploy (there
# is no roster yet, so nobody would be paged if anything went wrong during it),
# and an incident where the web service itself is the thing that is broken.
namespace :fuime do
  namespace :oncall do
    desc "Who is on call, what is open, and whether the last page landed"
    task status: :environment do
      responders = Fuime::Oncall::Responder.order(:escalation_position, :id)

      puts "\n── Roster ─────────────────────────────────────────────"
      if responders.none?
        puts "  EMPTY. Nobody would be paged for anything."
        puts "  rake 'fuime:oncall:add[Your Name,you@fuime.com]'"
      else
        responders.each do |r|
          channels = [("email" if r.email_configured?), ("sms/voice" if r.sms_configured?),
                      ("push:#{r.push_kind}" if r.push_configured?)].compact
          puts format("  %d. %-20s %-28s %s%s", r.escalation_position, r.name, r.email.to_s,
                      channels.join(", "),
                      r.pageable? ? "" : "   ⚠️  EMAIL ONLY — cannot wake anybody")
        end
      end

      puts "\n── Open incidents ─────────────────────────────────────"
      incidents = Fuime::Incident.live.by_urgency
      puts "  none" if incidents.none?
      incidents.each do |i|
        puts format("  %-5s %-34s %s", i.severity.upcase, i.key, i.title)
        puts format("        opened %s · %d pages · %s", i.opened_at.utc.strftime("%b %-d %H:%M UTC"),
                    i.page_count, i.status)
      end

      puts "\n── Last 10 delivery attempts ──────────────────────────"
      attempts = Fuime::IncidentNotification.recent.limit(10)
      puts "  none — the pager has never fired. Run fuime:oncall:test_page." if attempts.none?
      attempts.each do |n|
        puts format("  %s  %-6s %-24s %s%s", n.attempted_at.utc.strftime("%b %-d %H:%M"), n.channel,
                    n.target_redacted.to_s, n.status, n.error.present? ? " — #{n.error}" : "")
      end

      puts "\n── External watchdog ──────────────────────────────────"
      if ENV["FUIME_HEARTBEAT_URL"].present?
        puts "  configured"
      else
        puts "  ⚠️  FUIME_HEARTBEAT_URL unset. Nothing outside this app would notice if it died."
      end
      puts
    end

    desc "Add somebody to the on-call roster: rake 'fuime:oncall:add[Name,email]'"
    task :add, [:name, :email] => :environment do |_t, args|
      raise ArgumentError, "name and email are required" if args[:name].blank? || args[:email].blank?

      responder = Fuime::Oncall::Responder.create!(
        name: args[:name], email: args[:email],
        escalation_position: (Fuime::Oncall::Responder.maximum(:escalation_position) || 0) + 1
      )

      puts "Added #{responder.name} <#{responder.email}> at position #{responder.escalation_position}."
      puts
      puts "They now receive the daily digest and the full detail of every incident."
      # Said plainly rather than left to be discovered on the night it matters.
      puts "They CANNOT be woken up: email is not a page. Add a phone number or a"
      puts "push URL at /admin/oncall, then run fuime:oncall:test_page."
    end

    # The one command between "I have a roster" and "my phone makes a noise".
    #
    # Separate from :add because they fail differently and at different times.
    # Adding somebody is bookkeeping and either works or does not. Wiring a push
    # relay is a guess about a third party that reports success and then goes
    # quiet, so this one ends by actually firing a page — the only check that
    # means anything.
    desc "Point a responder at a push relay and page them: rake 'fuime:oncall:push[ntfy,https://ntfy.sh/topic,token]'"
    task :push, [:kind, :url, :credential] => :environment do |_t, args|
      kind = args[:kind].to_s
      unless Fuime::Oncall::Responder::PUSH_KINDS.include?(kind)
        raise ArgumentError, "kind must be one of #{Fuime::Oncall::Responder::PUSH_KINDS.join(', ')}"
      end
      raise ArgumentError, "a push URL is required" if args[:url].blank?

      responder = Fuime::Oncall::Responder.paging.first
      raise "The roster is empty. rake 'fuime:oncall:add[Name,email]' first." if responder.nil?

      responder.update!(push_kind: kind, push_url: args[:url], push_credential: args[:credential].presence)

      puts "#{responder.name} now pages over #{kind} at #{URI.parse(args[:url]).host}."
      unless responder.push_private?
        # Said here rather than only in the docs, because this is the moment the
        # decision is made and the consequence is invisible from the phone.
        puts
        puts "⚠️  No credential, so this relay is treated as PUBLIC: anyone who guesses"
        puts "    the topic receives Fuime's alerts. Pages over it are reduced to a"
        puts "    severity and a link — no venture names, no amounts, no ack link."
      end
      puts
      puts "Firing a test page now."
      Rake::Task["fuime:oncall:test_page"].invoke
    end

    desc "Run every check now. Does not page — use test_page for that."
    task sweep: :environment do
      result = Fuime::Oncall::Sweep.run!(page: false)
      puts "Checked #{result.checked.size}: #{result.raised.size} raised, " \
           "#{result.resolved.size} resolved, #{result.errored.size} could not run."
      result.raised.each { |i| puts "  RAISED   #{i.severity.upcase} #{i.key} — #{i.title}" }
      result.errored.each { |name| puts "  ERRORED  #{name} (whatever it watches is unmonitored)" }
    end

    desc "Fire a real sev-1 page through the real path. Your phone should ring."
    task test_page: :environment do
      incident = Fuime::Incident.raise!(
        key: "oncall.test_page", check_name: "manual_test",
        title: "Test page from the command line", severity: :sev1,
        detail: { "note" => "This is a test. Nothing is broken." }
      )

      Fuime::Oncall::Pager.page!(incident)
      attempts = incident.notifications.reload
      incident.resolve!

      if attempts.none?
        puts "Nothing was attempted — the roster is empty."
      else
        attempts.each do |n|
          puts format("  %-6s %-24s %s%s", n.channel, n.target_redacted.to_s, n.status,
                      n.error.present? ? " — #{n.error}" : "")
        end
      end
      puts
      puts "A 'delivered' above means the relay accepted it, NOT that a phone made a noise."
      puts "If nothing arrives in the next minute, that channel is broken even though it reported success."
    end
  end
end
