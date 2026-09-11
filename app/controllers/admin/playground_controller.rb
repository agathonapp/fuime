# frozen_string_literal: true

# Fuime: the pitch Playground on the same production deploy.
#
# Safe while Stripe is live — does not call DemoSandbox.guard_enabled!.
# "Become" is the existing admin impersonation (SessionsHelper#impersonate_user,
# the same helper UsersController#impersonate calls): admin-only, one-hour
# session, exits through the normal unimpersonate. There is no second login
# door here; #start and #fresh_founder only save the presenter two clicks
# by resetting a persona and impersonating them in one POST.
module Admin
  class PlaygroundController < Admin::BaseController
    def show
      @status = Fuime::Playground.new.status
    end

    # Reset everything: Maya's ledger rewritten with recent dates, the sample
    # products restored, the welcome tour re-armed, Sam back to a blank slate.
    def seed
      result = Fuime::Playground.new.seed!
      redirect_to playground_admin_index_path,
                  flash: { success: "Playground reset: /#{result[:event].slug} rewritten, Sam is fresh, Maya's welcome tour is re-armed.#{warning_suffix(result)}" }
    rescue => e
      redirect_to playground_admin_index_path, flash: { error: e.message }
    end

    # Reset, then Become Maya, landing on her venture home.
    def start
      authorize current_user, :impersonate?

      result = Fuime::Playground.new.seed!
      impersonate_user(result[:teen])
      redirect_to event_path(result[:event]),
                  flash: { info: "You're Maya now. This venture is a playground — nothing here moves real money.#{warning_suffix(result)}" }
    rescue => e
      redirect_to playground_admin_index_path, flash: { error: e.message }
    end

    # Put Sam back to "never used Fuime", then Become Sam — the very first
    # signup screen is where they land.
    def fresh_founder
      authorize current_user, :impersonate?

      playground = Fuime::Playground.new
      user = playground.reset_new_founder!
      impersonate_user(user)
      redirect_to root_path,
                  flash: { info: "You're Sam now — a founder who has never used Fuime. Everything you do here is reset on the next Playground reset." }
    rescue => e
      redirect_to playground_admin_index_path, flash: { error: e.message }
    end

    private

    def warning_suffix(result)
      warnings = result[:warnings]
      warnings.any? ? " (#{warnings.size} warning#{"s" if warnings.size > 1}: #{warnings.to_sentence})" : ""
    end

  end
end
