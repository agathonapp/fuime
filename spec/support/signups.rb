# frozen_string_literal: true

# Fuime: the suite runs with sign-ups OPEN unless an example is tagged
# `:signups_closed`.
#
# Production defaults to closed (Fuime::Signups), and the opposite default here
# is deliberate. Closing touches one door — LoginsController#create and the
# export form minting a User — and that door has its own examples in
# spec/requests/fuime_signups_closed_spec.rb. Every other example that signs a
# fresh address up was written for an open app and is about something else;
# running those closed would test the waitlist page dozens of times and their
# own subject not at all.
#
# Per example rather than once, for the reason spec/support/structural_flags.rb
# gives: dotenv's autorestore puts ENV back after every example. Set either way
# rather than left alone, so a value exported by .env.development (which the
# test container inherits) cannot choose the world for the suite.
#
#   it "offers the waitlist to an unknown address", :signups_closed do ... end
RSpec.configure do |config|
  config.before(:each) do |example|
    if example.metadata[:signups_closed]
      ENV.delete(Fuime::Signups::ENV_KEY)
    else
      ENV[Fuime::Signups::ENV_KEY] = "true"
    end
  end
end
