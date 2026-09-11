# frozen_string_literal: true

# Fuime playground seed — a product-ready Playground Mode venture.
#
#   bundle exec rails runner script/seed_playground_org.rb
#
# Delegates to Fuime::Playground. Safe while Stripe is live (no DemoSandbox
# guard, no Checkout). Prefer `rake fuime:playground` or /admin/playground.

result = Fuime::Playground.new.seed!
event = result[:event]
teen = result[:teen]
guardian = result[:guardian]

puts "[fuime-playground] === SEEDOK ==="
puts "[fuime-playground] org         /#{event.slug}   (##{event.id}, demo_mode=#{event.demo_mode})"
puts "[fuime-playground] offers      #{event.fuime_offers.live.count} live (#{event.fuime_offers.published.count} published)"
puts "[fuime-playground] owner       #{teen.email} (manager)"
puts "[fuime-playground] guardian    #{guardian.email} (reader)"
result[:warnings].each { |warning| puts "[fuime-playground] ! #{warning}" }
puts "[fuime-playground] Become Maya at /admin/playground. Checkout never hits Stripe."
