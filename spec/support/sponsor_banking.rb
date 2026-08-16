# frozen_string_literal: true

# Fuime: run an example in the world where Fuime holds customer funds.
#
# `FEATURE_SPONSOR_BANKING` is off everywhere, including the test environment,
# because the default has to be the safe answer (see Fuime::Features). That is
# correct, and it means the specs for the modules the flag gates — ACH transfers,
# checks, wires, disbursements, balance fronting — run against a world where
# those modules do not exist.
#
# Most of them cope, because the request-level block exempts GETs and the models
# are untouched. Balance FRONTING does not: `Event#can_front_balance?` returns
# false while custody is off, so a spec that funds an event with a `fronted:
# true` pending transaction and then spends it now finds a $0 balance. That is
# the gate working, not a bug — fronted money is money Fuime has advanced, and
# Fuime advances nothing.
#
# Tagging such an example `:sponsor_banking` runs it in the world it is actually
# describing. Prefer this to rewriting an upstream spec's fixtures: the spec is
# testing upstream behaviour that is still correct when the flag is on, and
# keeping it recognisable is what lets upstream ledger fixes still merge
# (CLAUDE.md Rule 6/8).
#
# Do NOT reach for this to make a failure go away. If an example fails because
# the gate changed what Fuime *should* do, the example is telling you something
# and the answer is to change the example. This tag is only for examples whose
# subject is a sponsor-banking module in the first place.
#
#   RSpec.describe AchTransfersController, :sponsor_banking do ... end
#   it "spends fronted money", :sponsor_banking do ... end
RSpec.configure do |config|
  config.around(:each, :sponsor_banking) do |example|
    key = Fuime::Features::SPONSOR_BANKING
    had = ENV.key?(key)
    old = ENV[key]

    ENV[key] = "true"

    begin
      example.run
    ensure
      had ? ENV[key] = old : ENV.delete(key)
    end
  end
end
