# frozen_string_literal: true

# Fuime: count unhandled exceptions so a 500 spike can page somebody.
#
# See Fuime::Oncall::ErrorCounter for what this does and, more importantly, what
# it deliberately does not do. In one line: AppSignal is in the Gemfile and its
# push key has never been set, so today nothing at all connects a 500 to a human
# being. This is the smallest thing that does.
#
# Not registered in test: the suite raises on purpose, constantly, and a counter
# that accumulates across examples would make Checks::Errors order-dependent —
# a spec that passes alone and fails in a full run, which is the worst kind.
Rails.application.config.after_initialize do
  next if Rails.env.test?

  Rails.error.subscribe(Fuime::Oncall::ErrorCounter.new)
end
