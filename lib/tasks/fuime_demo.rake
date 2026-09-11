# frozen_string_literal: true

# Fuime: spin up (and tear down) the demo sandbox.
#
#   rake fuime:demo:seed
#   rake fuime:demo:status
#   rake fuime:demo:login_code[demo+admin@fuime.test]
#   rake fuime:demo:remind
#   rake fuime:demo:smoke
#   rake fuime:demo:reset
#
# Walkthrough: docs/fuime/TESTING_WALKTHROUGH.md
namespace :fuime do
  namespace :demo do
    def demo_sandbox
      Fuime::DemoSandbox.new
    end

    def demo_abort(error)
      abort "fuime:demo: #{error.message}"
    end

    desc "Seed the demo cast (teens, parents, waitlist, queues, storefront)"
    task seed: :environment do
      result = demo_sandbox.seed!
      puts "Seeded #{result[:users]} demo users, #{result[:events]} ventures."
      result[:warnings].each { |w| puts "  ! #{w}" }
      puts
      puts "Next: rake fuime:demo:status"
      puts "      rake fuime:demo:login_code[demo+admin@fuime.test]"
      puts "      docs/fuime/TESTING_WALKTHROUGH.md"
    rescue Fuime::DemoSandbox::Error => e
      demo_abort(e)
    end

    desc "Print the demo roster, queue counts, and URLs"
    task status: :environment do
      status = demo_sandbox.status
      puts "enabled=#{status[:enabled]}  stripe=#{status[:stripe_mode]}  " \
           "MoR=#{status[:merchant_of_record]}  waitlist=#{status[:waitlist_configured]}"
      status[:warnings].each { |w| puts "  ! #{w}" }
      puts

      if (admin = status[:admin])
        puts "Admin  #{admin[:email]}  ##{admin[:id]}  #{admin[:name]}"
      else
        puts "Admin  (missing — rake fuime:demo:seed)"
      end
      puts

      puts "People"
      status[:people].each do |row|
        mark = row[:present] ? "✓" : "·"
        puts "  #{mark} #{row[:email].ljust(36)}  #{row[:purpose]}"
      end
      puts

      if status[:waitlist].any?
        puts "Waitlist"
        status[:waitlist].each do |signup|
          invited = signup.invited_at ? "invited" : "uninvited"
          puts "  #{signup.email.ljust(36)}  #{invited}"
        end
        puts
      end

      if (cohort = status[:cohort])
        puts "Cohort  #{cohort[:code]}  #{cohort[:name]}  " \
             "live=#{cohort[:live]}  members=#{cohort[:members]}"
        puts
      end

      puts "Ventures"
      status[:ventures].each do |row|
        if row[:present]
          pay = row[:accepts_payments] ? "can sell" : "cannot sell"
          vetted = row[:vetted] ? "vetted" : "unvetted"
          puts "  /#{row[:slug]}  #{row[:name]}  #{vetted}  #{pay}"
          puts "    offer: #{row[:offer]}" if row[:offer]
        else
          puts "  /#{row[:slug]}  (missing)"
        end
      end
      puts

      puts "Queues (this cast only)"
      status[:queues].each do |name, count|
        label = count.nil? ? "n/a (no waitlist store)" : count
        puts "  #{name.to_s.ljust(28)} #{label}"
      end
      puts
      puts "Admin pages: /admin/demo  /admin/waitlist  /admin/applications"
      puts "             /admin/cohorts  /admin/operator_vetting  /admin/guardianships"
      puts "Storefront:  /b/demo-lawn-care   pay: /pay/demo-lawn-care/front-and-back"
      puts "Billing:     /my/billing as demo+parent.store@fuime.test"
    rescue Fuime::DemoSandbox::Error => e
      demo_abort(e)
    end

    desc "Mint a 15-minute login code for a demo+…@fuime.test user"
    task :login_code, [:email] => :environment do |_t, args|
      email = args[:email].presence || Fuime::DemoSandbox.email("admin")
      code = demo_sandbox.mint_login_code!(email)
      puts "#{email}"
      puts "  code   #{code.pretty}"
      puts "  expires in #{LoginCode::EXPIRATION.inspect}"
      puts "  sign in at /login then enter that code (or letter_opener if mail is on)"
    rescue Fuime::DemoSandbox::Error => e
      demo_abort(e)
    end

    desc "Run GuardianInviteReminderJob now (day-3 / day-6 mail for due invites)"
    task remind: :environment do
      demo_sandbox.remind_now!
      puts "GuardianInviteReminderJob finished. Check letter_opener / logs."
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
end
