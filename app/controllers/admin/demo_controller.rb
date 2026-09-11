# frozen_string_literal: true

# Fuime: the demo sandbox roster. Seed/reset stay available here in
# development (and on staging only when FUIME_DEMO_SANDBOX=1 and Stripe is
# test). Never reachable when Stripe is live.
module Admin
  class DemoController < Admin::BaseController
    before_action :require_demo_sandbox!

    def show
      @status = Fuime::DemoSandbox.new.status
    end

    def seed
      result = Fuime::DemoSandbox.new.seed!
      warning = result[:warnings].any? ? " (#{result[:warnings].size} warning(s) — see the page)" : ""
      redirect_to demo_admin_index_path,
                  flash: { success: "Demo cast seeded: #{result[:users]} users, #{result[:events]} ventures.#{warning}" }
    rescue Fuime::DemoSandbox::Error => e
      redirect_to demo_admin_index_path, flash: { error: e.message }
    end

    def reset
      unless params[:confirm].to_s == "reset"
        redirect_to demo_admin_index_path, flash: { error: "Type reset in the confirm box." }
        return
      end

      result = Fuime::DemoSandbox.new.reset!
      redirect_to demo_admin_index_path,
                  flash: { success: "Removed #{result[:users_removed]} demo users and #{result[:events_removed]} ventures." }
    rescue Fuime::DemoSandbox::Error => e
      redirect_to demo_admin_index_path, flash: { error: e.message }
    end

    def login_code
      code = Fuime::DemoSandbox.new.mint_login_code!(params[:email])
      redirect_to demo_admin_index_path,
                  flash: { success: "Login code for #{params[:email]}: #{code.pretty} (15 minutes)" }
    rescue Fuime::DemoSandbox::Error => e
      redirect_to demo_admin_index_path, flash: { error: e.message }
    end

    def remind
      Fuime::DemoSandbox.new.remind_now!
      redirect_to demo_admin_index_path,
                  flash: { success: "Guardian invite reminder job ran. Check letter_opener / logs." }
    rescue Fuime::DemoSandbox::Error => e
      redirect_to demo_admin_index_path, flash: { error: e.message }
    end

    private

    def require_demo_sandbox!
      return if Fuime::DemoSandbox.enabled?

      redirect_to admin_tools_path, flash: { error: "Demo sandbox is off (Stripe live, or FUIME_DEMO_SANDBOX is unset)." }
    end
  end
end
