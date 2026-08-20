# frozen_string_literal: true

require "rails_helper"

# Fuime: signup asks "are you 13 or older?" instead of asking for a date of birth
# (2026-08-20, founder's call). See AddAgeAttestationToUsers.
#
# The examples here are all about the same worry: the platform's central control is
# "a minor needs a guardian", and swapping the age source is swapping the input that
# control runs on. So these assert the three thresholds still resolve, and — the part
# that matters most — that the box a user can tick cannot make them an adult.
RSpec.describe "age attestation" do
  describe "the three thresholds it has to answer" do
    it "reads a 13+ tick as a minor who needs a guardian" do
      teen = create(:user, :attested_teen)

      expect(teen.attested_at_least?(13)).to be true
      expect(teen.known_adult?).to be false
      expect(teen.minor_or_unknown_age?).to be true
      expect(teen.needs_guardian?).to be true
    end

    it "reads an 18+ tick as an adult" do
      adult = create(:user, :attested_adult)

      expect(adult.attested_at_least?(18)).to be true
      expect(adult.known_adult?).to be true
      expect(adult.minor_or_unknown_age?).to be false
    end

    # The fail-closed default the whole control depends on.
    it "reads no answer as a minor" do
      unknown = create(:user, :unknown_age)

      expect(unknown.attested_at_least?(13)).to be false
      expect(unknown.known_adult?).to be false
      expect(unknown.minor_or_unknown_age?).to be true
    end

    # A checkbox cannot tell 14 from 17, and the honest answer to a question you
    # cannot answer is to say so rather than guess.
    it "does not claim to clear a floor above 13" do
      teen = create(:user, :attested_teen)

      expect(teen.attested_at_least?(13)).to be true
      expect(teen.attested_at_least?(16)).to be false
      expect(teen.attested_at_least?(18)).to be false
    end
  end

  describe "a stored date of birth still wins" do
    # Otherwise a teen who supplied a real date for a card could tick their way out
    # of being a minor afterwards.
    it "keeps a 15-year-old a minor even if an adult attestation is on the record" do
      teen = create(:user, birthday: 15.years.ago.to_date)
      teen.update_columns(age_attestation: User.age_attestations[:adult_18_plus])

      expect(teen.reload.known_adult?).to be false
      expect(teen.minor_or_unknown_age?).to be true
    end

    it "keeps a 30-year-old an adult" do
      expect(create(:user, birthday: 30.years.ago.to_date).known_adult?).to be true
    end
  end

  # ── The load-bearing property ─────────────────────────────────────────────
  describe "the box a user can tick cannot make them an adult" do
    let(:teen) { create(:user, :unknown_age, full_name: "Ada Teen") }

    before { teen.reload }

    it "records only the minor claim from the user's own form", :aggregate_failures do
      teen.attest_minor_13_plus!(ip: "203.0.113.4", user_agent: "Firefox")

      expect(teen.reload.age_attestation).to eq("minor_13_plus")
      expect(teen.known_adult?).to be false
      expect(teen.age_attested_at).to be_present
      expect(teen.age_attestation_ip).to eq("203.0.113.4")
    end

    # The parameter allowlist is the first line; this asserts it rather than
    # trusting it, because it is the whole design.
    it "does not permit age_attestation as a mass-assignable attribute" do
      # Reads the source rather than invoking the controller: the claim is that the
      # symbols are absent from the allowlist entirely, which is a fact about the
      # allowlist and not about any one request.
      #
      # Comments are stripped first — the allowlist carries a note explaining why
      # both symbols were removed, and matching that note would make this example
      # pass or fail on prose.
      source = File.read(Rails.root.join("app/controllers/users_controller.rb"))
      params_block = source[/def user_params.*?^    end/m]
      code_only = params_block.lines.reject { |l| l.strip.start_with?("#") }.join

      expect(code_only).not_to include(":age_attestation")
      expect(code_only).not_to include(":birthday")
    end

    it "is write-once for its owner" do
      teen.attest_minor_13_plus!
      session = User::Session.new(user: teen, expiration_at: 1.day.from_now, verified: true)

      Current.set(session: session) do
        expect(teen.update(age_attestation: :adult_18_plus)).to be false
        expect(teen.errors[:age_attestation].join).to include("can't be changed here")
      end

      expect(teen.reload.known_adult?).to be false
    end

    it "lets an admin correct it" do
      teen.attest_minor_13_plus!
      admin = create(:user, :make_admin)
      session = User::Session.new(user: admin, expiration_at: 1.day.from_now, verified: true)

      Current.set(session: session) do
        expect(teen.update(age_attestation: :adult_18_plus)).to be true
      end
    end

    it "refuses a half-authenticated session outright" do
      teen.attest_minor_13_plus!
      unverified = User::Session.new(user: teen, expiration_at: 1.day.from_now, verified: false)

      Current.set(session: unverified) do
        expect(teen.update(age_attestation: :adult_18_plus)).to be false
      end
    end

    # The one legitimate transition, and the only route to it.
    it "is promoted to adult by accepting a guardianship, and nowhere else" do
      parent = create(:user, :unknown_age)
      parent.attest_minor_13_plus!
      expect(parent.reload.known_adult?).to be false

      parent.attest_adult_18_plus!(ip: "198.51.100.9", user_agent: "Safari")

      expect(parent.reload.age_attestation).to eq("adult_18_plus")
      expect(parent.known_adult?).to be true
      expect(parent.age_attestation_ip).to eq("198.51.100.9")
    end
  end

  describe "onboarding" do
    it "cannot be completed without an answer" do
      user = create(:user, :unknown_age)
      user.full_name = "Ada Lovelace"

      expect(user.valid?(:onboarding)).to be false
      expect(user.errors[:age_attestation].join).to match(/confirm you're 13 or older/i)
    end

    it "is satisfied by the tick" do
      user = create(:user, :attested_teen)
      user.full_name = "Ada Lovelace"

      expect(user.valid?(:onboarding)).to be true
    end

    # Users who signed up before the switch already answered, more precisely.
    it "is satisfied by a date of birth that is already on file" do
      user = create(:user, birthday: 15.years.ago.to_date, age_attestation: nil)
      user.full_name = "Ada Lovelace"

      expect(user.valid?(:onboarding)).to be true
    end
  end

  describe "the operator age floor" do
    let(:event) { create(:event, business_category: "services") }

    def blockers_for(user)
      create(:organizer_position, event:, user:)
      Fuime::OperatorEligibility.new(event: event.reload).blockers
    end

    # The production value of FUIME_MINIMUM_OPERATOR_AGE is 13, so a 13+ tick
    # satisfies the floor exactly and nothing is lost by dropping the date.
    it "passes a 13+ tick when the floor is 13", :merchant_of_record do
      ENV["FUIME_MINIMUM_OPERATOR_AGE"] = "13"

      expect(blockers_for(create(:user, :attested_teen))).to be_empty
    ensure
      ENV.delete("FUIME_MINIMUM_OPERATOR_AGE")
    end

    # And raising it says so in words rather than guessing — the failure the
    # checkbox genuinely cannot avoid, made loud.
    it "refuses a 13+ tick when the floor is 16, and says why", :merchant_of_record do
      ENV["FUIME_MINIMUM_OPERATOR_AGE"] = "16"

      blockers = blockers_for(create(:user, :attested_teen, full_name: "Ada Teen"))

      expect(blockers.join).to include("Ada Teen")
      expect(blockers.join).to match(/must be at least 16/)
      expect(blockers.join).to match(/date of birth to tell/)
    ensure
      ENV.delete("FUIME_MINIMUM_OPERATOR_AGE")
    end

    it "refuses somebody who has confirmed nothing", :merchant_of_record do
      blockers = blockers_for(create(:user, :unknown_age, full_name: "Nobody Knows"))

      expect(blockers.join).to match(/hasn't confirmed their age/i)
    end

    it "still reads a stored date of birth where one exists", :merchant_of_record do
      ENV["FUIME_MINIMUM_OPERATOR_AGE"] = "16"

      expect(blockers_for(create(:user, birthday: 17.years.ago.to_date))).to be_empty
    ensure
      ENV.delete("FUIME_MINIMUM_OPERATOR_AGE")
    end
  end

  describe "guardianship" do
    it "lets a guardian who ticked the 18+ box activate, with no date of birth" do
      guardian = create(:user, :unknown_age)
      minor = create(:user, :attested_teen)
      guardianship = Guardianship.create!(guardian:, minor:)

      expect(guardianship.activation_blockers.join).to match(/confirm you're 18 or older/i)

      guardian.attest_adult_18_plus!
      expect(guardianship.reload.activation_blockers).to be_empty
      expect(guardianship.accept!).to be true
    end

    it "refuses to make somebody a ward when they have said they are an adult" do
      adult = create(:user, :attested_adult)
      guardianship = Guardianship.new(guardian: create(:user, :attested_adult), minor: adult)

      expect(guardianship).not_to be_valid
      expect(guardianship.errors[:minor].join).to match(/18 or older/)
    end

    it "still counts a checkbox teen as a teenager for metrics" do
      expect(create(:user, :attested_teen).is_teenager?).to be true
    end
  end
end
