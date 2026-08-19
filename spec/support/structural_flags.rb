# frozen_string_literal: true

# Fuime: the suite decides what the structural flags are, not the machine.
#
# ── The hole this closes ────────────────────────────────────────────────────
#
# spec/support/merchant_of_record.rb and spec/support/sponsor_banking.rb both
# open by stating that their flag "is off everywhere including test". That was an
# ASSUMPTION about the environment, and it is false in the way this repository
# actually runs its specs:
#
#   docker-compose.yml gives the `web` service `env_file: .env.development`, and
#   specs run through `docker compose run web`. So EVERY variable in
#   .env.development is present in the test container regardless of RAILS_ENV —
#   `Dotenv.load if Rails.env.development?` in config/application.rb never enters
#   into it, because Docker has already exported them.
#
# So adding `FEATURE_MERCHANT_OF_RECORD=true` to .env.development — which is the
# obvious thing to do to see a merchant-of-record page in a browser — silently
# runs the WHOLE suite in the umbrella model. Not as an error: as a green run
# that tested a different application. Untagged examples would exercise the
# gated launch scope, and the `:merchant_of_record` tag would become a no-op that
# still passes, so nothing anywhere would say the world had changed.
#
# ── ⚠️ Why this is `before(:each)` and not `before(:suite)` ─────────────────
#
# It was written as `before(:suite)` first, and that DOES NOT WORK here. dotenv
# 3.1.7 loads `dotenv/autorestore`, which snapshots ENV once and restores that
# snapshot after **every single example**. A suite-level deletion therefore holds
# for exactly one example and is then quietly undone — which presents as one
# inexplicably failing example in a file that passes when run with `-e`, and
# cost an hour to find. Anything that wants ENV to hold a value across this
# suite has to re-assert it per example.
#
# ── Why it is tag-aware rather than unconditional ───────────────────────────
#
# The two tag helpers are `around` hooks, and an `around` wraps `before`, so by
# the time this runs the tag has already set its flag. Deleting unconditionally
# would make both tags no-ops in the other direction — every gated example would
# run with the gate off and pass for the wrong reason. So each flag is left alone
# for exactly the tag that owns it.
#
# Deleting rather than setting "false": Fuime::Features only enables on the exact
# string "true", so absent and "false" are equivalent to it — but absent is also
# what a fresh CI environment looks like, and the suite should run against that.
# Which tag is allowed to turn each flag on. Written out rather than inferred so
# that a new structural flag with no tag yet fails CLOSED: it gets cleared for
# every example until somebody writes its helper, rather than inheriting whatever
# the machine happens to export.
FUIME_FLAG_TAGS = {
  Fuime::Features::MERCHANT_OF_RECORD => :merchant_of_record,
  Fuime::Features::SPONSOR_BANKING    => :sponsor_banking
}.freeze

RSpec.configure do |config|
  config.before(:suite) do
    set = Fuime::Features::ALL.select { |flag| ENV.key?(flag) }
    next if set.empty?

    warn "⚠️  #{set.join(', ')} set in this environment (likely .env.development via " \
         "docker-compose's env_file). The suite clears them per example — tag examples " \
         "with :merchant_of_record / :sponsor_banking to turn one on."
  end

  config.before(:each) do |example|
    Fuime::Features::ALL.each do |flag|
      next if example.metadata[FUIME_FLAG_TAGS[flag]]

      ENV.delete(flag)
    end
  end
end
