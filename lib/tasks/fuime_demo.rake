# frozen_string_literal: true

# Fuime: spin up (and tear down) the demo sandbox.
#
#   rake fuime:demo                 reset + seed + print the 15-minute path
#   rake fuime:demo:status
#   rake fuime:demo:login_code[demo+admin@fuime.test]
#   rake fuime:demo:remind
#   rake fuime:demo:smoke
#   rake fuime:demo:reset
#
# Then open /admin/demo and Become each persona (existing impersonate).
# Stripe test only. Hidden when Stripe is live.
namespace :fuime do
  namespace :demo do
    def demo_sandbox
      Fuime::DemoSandbox.new
    end

    def demo_abort(error)
      abort "fuime:demo: #{error.message}"
    end

    desc "Reset + seed the demo cast and print the 15-minute checklist"
    task setup: :environment do
      sandbox = demo_sandbox
      sandbox.setup!
      puts sandbox.banner
    rescue Fuime::DemoSandbox::Error => e
      demo_abort(e)
    end

    desc "Seed / refresh the demo cast without wiping first"
    task seed: :environment do
      result = demo_sandbox.seed!
      puts "Seeded #{result[:users]} demo users, #{result[:events]} ventures."
      result[:warnings].each { |w| puts "  ! #{w}" }
      puts
      puts "Prefer: rake fuime:demo   (reset + seed + banner)"
      puts "        open /admin/demo  (checklist + Become)"
    rescue Fuime::DemoSandbox::Error => e
      demo_abort(e)
    end

    desc "Print the demo roster, queue counts, and the living checklist"
    task status: :environment do
      puts demo_sandbox.banner
    rescue Fuime::DemoSandbox::Error => e
      demo_abort(e)
    end

    desc "Mint a 15-minute login code for a demo+…@fuime.test user"
    task :login_code, [:email] => :environment do |_t, args|
      email = args[:email].presence || Fuime::DemoSandbox.email("admin")
      code = demo_sandbox.mint_login_code!(email)
      puts email.to_s
      puts "  code   #{code.pretty}"
      puts "  expires in #{LoginCode::EXPIRATION.inspect}"
      puts "  Prefer Become on /admin/demo. This code is for testing /login itself."
    rescue Fuime::DemoSandbox::Error => e
      demo_abort(e)
    end

    desc "Send day-3 / day-6 reminder mail for due DEMO invites only"
    task remind: :environment do
      demo_sandbox.remind_now!
      puts "Demo guardian reminders sent. Check letter_opener / logs."
    rescue Fuime::DemoSandbox::Error => e
      demo_abort(e)
    end

    desc "Assert the seeded world is internally consistent (no Stripe calls)"
    task smoke: :environment do
      checks = demo_sandbox.smoke_checks
      failed = checks.reject { |_name, ok| ok }
      checks.each do |name, ok|
        puts "  #{ok ? '✓' : '✗'} #{name}"
      end
      abort "smoke failed (#{failed.size})" if failed.any?
      puts "smoke ok (#{checks.size})"
    rescue Fuime::DemoSandbox::Error => e
      demo_abort(e)
    end

    desc "Delete only the demo+@fuime.test cast and demo-* ventures"
    task reset: :environment do
      result = demo_sandbox.reset!
      puts "Removed #{result[:users_removed]} users, #{result[:events_removed]} ventures."
    rescue Fuime::DemoSandbox::Error => e
      demo_abort(e)
    end
  end

  desc "Reset + seed the demo cast and print the 15-minute checklist"
  task demo: "fuime:demo:setup"
end
