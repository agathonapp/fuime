# frozen_string_literal: true

# Fuime: pitch Playground on the same production deploy.
#
# Safe while Stripe is live — does not call DemoSandbox.guard_enabled!.
# Become is UsersController#impersonate.
module Admin
  class PlaygroundController < Admin::BaseController
    def show
      @status = Fuime::Playground.new.status
    end

    def seed
      result = Fuime::Playground.new.seed!
      warning = result[:warnings].any? ? " (#{result[:warnings].size} warning(s))" : ""
      redirect_to playground_admin_index_path,
                  flash: { success: "Playground ready: /#{result[:event].slug}. Become Maya and click What you sell.#{warning}" }
    rescue StandardError => e
      redirect_to playground_admin_index_path, flash: { error: e.message }
    end
  end
end
