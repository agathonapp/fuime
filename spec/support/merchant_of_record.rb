# frozen_string_literal: true

# Fuime: run an example in the world where Fuime is the legal seller.
#
# Sibling of spec/support/sponsor_banking.rb, and the reasoning is identical:
# `FEATURE_MERCHANT_OF_RECORD` is off everywhere including test, because the
# default has to be the safe answer (see Fuime::Features). So the specs for the
# behaviour it gates run, by default, against a world where Fuime is *not* the
# seller — which is the right default and the wrong world for those examples.
#
# What the flag changes is narrower than it looks. Vetting binds in every model,
# so an example about approval needs no tag. What this tag turns on is the launch
# scope Fuime only carries as merchant of record: services-only, the 16+ operator
# floor, and a guardian per operator (Fuime::OperatorEligibility#blockers
# explains why those three are scoped and vetting is not).
#
# Do NOT reach for this to make a failure go away. If an example fails because
# the gate changed what Fuime *should* do with the flag off, that is the example
# telling you something true. This tag is for examples whose subject is the
# umbrella model in the first place.
#
#   RSpec.describe Fuime::OperatorEligibility, :merchant_of_record do ... end
#   it "refuses a physical-goods venture", :merchant_of_record do ... end
RSpec.configure do |config|
  config.around(:each, :merchant_of_record) do |example|
    key = Fuime::Features::MERCHANT_OF_RECORD
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
