# frozen_string_literal: true

# Fuime: seed the pitch Playground venture on this app.
#
#   rake fuime:playground
#
# Safe while Stripe is live. Does not call DemoSandbox.guard_enabled!.
namespace :fuime do
  desc "Seed / refresh the pitch Playground venture (safe on live Stripe)"
  task playground: :environment do
    playground = Fuime::Playground.new
    result = playground.seed!
    puts playground.banner
    result[:warnings].each { |warning| puts "  ! #{warning}" }
    puts "open /admin/playground"
  end
end
