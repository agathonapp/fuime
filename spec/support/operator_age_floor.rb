# frozen_string_literal: true

# Fuime: the suite decides the operator age floor, not the machine.
#
# Same hole as spec/support/structural_flags.rb, and worth its own file because
# `FUIME_MINIMUM_OPERATOR_AGE` is not a structural flag and would not be caught
# by that one.
#
# docker-compose.yml gives the `web` service `env_file: .env.development`, and
# specs run through `docker compose run web` — so every variable in
# .env.development is present in the test container whatever RAILS_ENV says.
# Setting `FUIME_MINIMUM_OPERATOR_AGE=13` there is the obvious thing to do when a
# cohort has younger founders (Founders Weekend, 2026-08-21), and it silently
# re-floors the whole suite: every example asserting the default of 16 fails, and
# — worse — an example asserting that a 14-year-old is BLOCKED would pass or fail
# depending on a file that is not checked in.
#
# It cost 13 failures across five files to find, all of which read as real
# regressions in the age gate rather than as one line in a dotfile.
#
# ⚠️ `before(:each)`, not `before(:suite)` — dotenv 3.1.7's autorestore snapshots
# ENV once and restores it after EVERY example, so a suite-level deletion holds
# for exactly one example and is then undone. See structural_flags.rb.
#
# Examples that want a specific floor set ENV themselves inside the example (see
# spec/services/fuime/operator_eligibility_spec.rb). This hook runs first — an
# RSpec.configure `before` precedes a group's own `before` — so those still work.
#
# Deleting rather than setting "16": absent is what a fresh CI environment looks
# like, and Fuime::OperatorEligibility.minimum_operator_age already falls back to
# DEFAULT_MINIMUM_OPERATOR_AGE. The suite should exercise that fallback.
FUIME_OPERATOR_AGE_ENV = "FUIME_MINIMUM_OPERATOR_AGE"

RSpec.configure do |config|
  config.before(:suite) do
    if ENV.key?(FUIME_OPERATOR_AGE_ENV)
      warn "⚠️  #{FUIME_OPERATOR_AGE_ENV}=#{ENV[FUIME_OPERATOR_AGE_ENV].inspect} set in this " \
           "environment (likely .env.development via docker-compose's env_file). The suite " \
           "clears it per example so the default floor is what gets tested."
    end
  end

  config.before(:each) { ENV.delete(FUIME_OPERATOR_AGE_ENV) }
end
