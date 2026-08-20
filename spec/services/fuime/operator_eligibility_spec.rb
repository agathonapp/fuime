# frozen_string_literal: true

require "rails_helper"

# Fuime: the launch scope, as a test rather than as a paragraph.
#
# docs/fuime/MOR_MIGRATION_PLAN.md §8.1 narrows Phase 1 to services, operators
# 16–17, and a human approving everyone. Those three constraints are not
# preferences — each one removes a specific liability Fuime would otherwise
# inherit as merchant of record. This file is what stops them being decorative.
#
# The bias throughout: every ambiguous state must block. The venture nobody has
# reviewed, the category nobody chose, the birthday nobody entered — those are
# the populations these gates exist for, so any of them reading as "allowed"
# would exempt precisely the wrong people.
RSpec.describe Fuime::OperatorEligibility do
  subject(:eligibility) { described_class.new(event:) }

  # A venture that passes everything, so each spec below can break exactly one
  # thing and attribute the result to it. The factory already defaults to
  # :approved — see spec/factories/event_factory.rb for why.
  let(:operator) { create(:user, :minor_with_guardian, birthday: 16.years.ago.to_date) }
  let(:event) { create(:event, business_category: "services", organizers: [operator]) }

  it "clears a vetted services venture run by a 16-year-old with a guardian", :merchant_of_record do
    expect(eligibility.blockers).to be_empty
    expect(eligibility).to be_eligible
  end

  # The scope split is the whole design of this object, so it gets its own
  # examples rather than being implied by the tags on everything else.
  describe "what binds in which model" do
    # Vetting is the compensating control for letting minors sell at all. It is
    # worth the same under Connect, where the guardian is the merchant, as under
    # MoR, where Fuime is — so it must not wait for the flag.
    it "enforces vetting even when Fuime is not the seller of record" do
      event.update!(operator_vetting_status: :unvetted)

      expect(Fuime::Features.merchant_of_record?).to be(false)
      expect(described_class.new(event:)).not_to be_eligible
    end

    # The launch scope bounds liability Fuime only carries as seller of record.
    # Under Connect the guardian owns the account and Stripe settles to the
    # family, so product liability and the FLSA question land there — blocking a
    # venture for those reasons would be enforcing a rule that does not apply.
    it "does not enforce the launch scope when Fuime is not the seller of record" do
      event.update!(business_category: "food")
      create(:organizer_position, event:, user: create(:user, :minor, birthday: 14.years.ago.to_date))

      expect(described_class.new(event:)).to be_eligible
    end

    it "enforces the launch scope once Fuime is the seller of record", :merchant_of_record do
      event.update!(business_category: "food")

      expect(described_class.new(event:)).not_to be_eligible
    end
  end

  describe "vetting" do
    it "blocks a venture nobody has reviewed" do
      event.update!(operator_vetting_status: :unvetted)

      expect(eligibility.blockers).to contain_exactly(/not been approved by Fuime yet/)
    end

    # The three refusals are separate messages because they mean different
    # things to the person reading them: rejected is final, suspended is a state
    # they may be able to argue with, unvetted is just a queue.
    it "distinguishes rejected from suspended" do
      event.update!(operator_vetting_status: :rejected)
      expect(described_class.new(event:).blockers).to contain_exactly(/was not approved/)

      event.update!(operator_vetting_status: :suspended)
      expect(described_class.new(event:).blockers).to contain_exactly(/suspended/)
    end

    # The point of a standing status rather than an application outcome: an
    # operator who starts selling something they never applied with has to be
    # stoppable today.
    it "revokes eligibility from a venture that was previously fine" do
      expect(eligibility).to be_eligible

      event.update!(operator_vetting_status: :suspended)

      expect(described_class.new(event:)).not_to be_eligible
    end
  end

  describe "category", :merchant_of_record do
    it "allows services" do
      expect(eligibility.blockers).to be_empty
    end

    # Opened 2026-08-20 on the founder's call. Asserted explicitly rather than left
    # to the derived loop above, because "digital may sell" is now a product
    # decision with a sales-tax consequence and should fail loudly if reverted by
    # accident.
    it "allows digital, opened 2026-08-20" do
      event.update!(business_category: "digital")

      expect(described_class.new(event:).blockers).to be_empty
      expect(described_class.new(event:)).to be_eligible
    end

    # Widening to digital must not have widened anything else. `other` is the one
    # that matters most: it is unknown by definition and this is an allowlist so
    # that unknown fails closed.
    it "still blocks crafts, food and other" do
      %w[crafts food other].each do |category|
        event.update!(business_category: category)

        expect(described_class.new(event:)).not_to be_eligible,
                                                   "expected #{category.inspect} to stay ineligible"
      end
    end

    it "blocks every category outside the Phase 1 slice" do
      (Event::BUSINESS_CATEGORIES - described_class::ELIGIBLE_CATEGORIES).each do |category|
        event.update!(business_category: category)

        expect(described_class.new(event:).blockers)
          .to contain_exactly(/service and digital businesses/),
              "expected #{category.inspect} to be outside the Phase 1 slice"
      end
    end

    # Physical goods are the two this gate exists for: as seller of record Fuime
    # would carry product liability, and physical sales accrue state sales-tax
    # nexus against one entity far faster than against any individual operator.
    it "blocks physical goods specifically" do
      %w[crafts food].each do |category|
        event.update!(business_category: category)
        expect(described_class.new(event:)).not_to be_eligible
      end
    end

    # Fails closed. Every venture created before this control existed has a NULL
    # here, and treating "not answered" as "allowed" would exempt all of them.
    it "blocks a venture that never chose a category" do
      event.update!(business_category: nil)

      expect(described_class.new(event:).blockers).to contain_exactly(/Choose what this venture sells/)
    end
  end

  describe "operator age", :merchant_of_record do
    it "blocks a 15-year-old, naming them and their age" do
      young = create(:user, :minor_with_guardian, birthday: 15.years.ago.to_date)
      create(:organizer_position, event:, user: young)

      expect(described_class.new(event:).blockers)
        .to contain_exactly(/#{Regexp.escape(young.name)} is 15\. Fuime operators must be at least 16/)
    end

    it "allows 16 and 17" do
      [16, 17].each do |age|
        teen = create(:user, :minor_with_guardian, birthday: age.years.ago.to_date)
        venture = create(:event, business_category: "services", organizers: [teen])
        venture.update!(operator_vetting_status: :approved)

        expect(described_class.new(event: venture)).to be_eligible, "expected age #{age} to be eligible"
      end
    end

    # The floor on operators defaults stricter than the platform's floor on
    # users, which stays at 13 per L6. A 14-year-old may hold an account and by
    # default may not sell — so this is a gate on the venture, never on signup.
    it "defaults stricter than the platform's own age floor" do
      expect(described_class::DEFAULT_MINIMUM_OPERATOR_AGE).to be > 13
    end

    # `FUIME_MINIMUM_OPERATOR_AGE` lets the person accountable for the risk widen
    # the bracket without a code change (see the constant's comment). These are
    # the guardrails on that dial — and the third is the one that matters:
    # under-13 is COPPA (L6), not a business decision, so no configured value can
    # reach it.
    describe "the configured floor" do
      around do |example|
        old = ENV["FUIME_MINIMUM_OPERATOR_AGE"]
        example.run
        old.nil? ? ENV.delete("FUIME_MINIMUM_OPERATOR_AGE") : ENV["FUIME_MINIMUM_OPERATOR_AGE"] = old
      end

      it "honours a lowered floor" do
        ENV["FUIME_MINIMUM_OPERATOR_AGE"] = "14"

        expect(described_class.minimum_operator_age).to eq(14)
      end

      it "honours a raised floor, because raising is always safe" do
        ENV["FUIME_MINIMUM_OPERATOR_AGE"] = "18"

        expect(described_class.minimum_operator_age).to eq(18)
      end

      it "clamps to 13 rather than honouring anything lower" do
        ENV["FUIME_MINIMUM_OPERATOR_AGE"] = "8"

        expect(described_class.minimum_operator_age).to eq(13)
      end

      it "clamps a zero, which is the spelling of 'no floor at all'" do
        ENV["FUIME_MINIMUM_OPERATOR_AGE"] = "0"

        expect(described_class.minimum_operator_age).to eq(13)
      end

      # A misconfigured value must read as the default, never as no floor.
      it "falls back to the default on a value it cannot parse" do
        ENV["FUIME_MINIMUM_OPERATOR_AGE"] = "sixteen"

        expect(described_class.minimum_operator_age)
          .to eq(described_class::DEFAULT_MINIMUM_OPERATOR_AGE)
      end

      it "actually blocks a 14-year-old at the default and clears them at 14" do
        young = create(:user, :minor_with_guardian, birthday: 14.years.ago.to_date)
        create(:organizer_position, event:, user: young)

        expect(described_class.new(event:).blockers).to include(/is 14/)

        ENV["FUIME_MINIMUM_OPERATOR_AGE"] = "14"
        expect(described_class.new(event:).blockers).to be_empty
      end
    end

    # The one that matters most. A missing birthday must not be the way past a
    # floor that exists to keep FLSA hour limits out of the picture.
    it "blocks an operator with no date of birth on file" do
      unknown = create(:user, :unknown_age)
      create(:guardianship, :active, minor: unknown)
      create(:organizer_position, event:, user: unknown)

      expect(described_class.new(event:).blockers)
        .to include(/#{Regexp.escape(unknown.name)} has no date of birth on file/)
    end
  end

  # The guardian requirement MOVED on 2026-08-16; it was not removed.
  #
  # It used to block selling from here. Under merchant-of-record a teenager
  # selling holds no account and incurs no obligation, so the adult is not the
  # legal party yet — they become one when money leaves. The gate now lives in
  # Fuime::PayableAssessment#compute_structural_skip_reason, and
  # spec/services/fuime/payable_assessment_spec.rb is where it is proven.
  #
  # These specs stay, inverted, because "a minor with no guardian may sell" is a
  # deliberate decision with a cost attached (MOR_MIGRATION_PLAN §7 Q3: no adult
  # obligor behind a clawback during the selling window). A decision that costs
  # something should fail loudly if somebody reinstates the old gate without
  # reading why it moved.
  describe "guardianship", :merchant_of_record do
    it "does not block a minor with no guardian — that gate is at payout now" do
      alone = create(:user, :minor, birthday: 16.years.ago.to_date)
      create(:organizer_position, event:, user: alone)

      expect(described_class.new(event:).blockers).to be_empty
    end

    it "does not block when the guardianship is still only an invite" do
      pending_teen = create(:user, :minor, birthday: 16.years.ago.to_date)
      create(:guardianship, minor: pending_teen) # status: :pending
      create(:organizer_position, event:, user: pending_teen)

      expect(described_class.new(event:)).to be_eligible
    end

    # The age floor is NOT what moved. A 14-year-old still cannot sell under the
    # umbrella whether or not a parent is attached, because that bracket exists
    # for the FLSA question (§7 Q2) rather than for consent.
    it "still applies the age floor to a minor with no guardian" do
      too_young = create(:user, :minor, birthday: 14.years.ago.to_date)
      create(:organizer_position, event:, user: too_young)

      expect(described_class.new(event:).blockers)
        .to contain_exactly(/#{Regexp.escape(too_young.name)} is 14/)
    end
  end

  describe "adult operators", :merchant_of_record do
    # An adult co-founder needs no guardian and is subject to no age floor. If
    # adults were swept into the minor checks, every venture with a parent or a
    # staff member on it would be permanently blocked on a guardian for someone
    # who cannot have one.
    it "are exempt from both the age floor and the guardian requirement" do
      adult = create(:user, birthday: 30.years.ago.to_date)
      venture = create(:event, business_category: "services", organizers: [adult])
      venture.update!(operator_vetting_status: :approved)

      expect(described_class.new(event: venture)).to be_eligible
    end
  end

  describe "reporting more than one problem", :merchant_of_record do
    it "names each person, because the fix is per-person" do
      young = create(:user, :minor_with_guardian, birthday: 14.years.ago.to_date)
      younger = create(:user, :minor, birthday: 13.years.ago.to_date)
      create(:organizer_position, event:, user: young)
      create(:organizer_position, event:, user: younger)

      blockers = described_class.new(event:).blockers

      expect(blockers).to include(/#{Regexp.escape(young.name)} is 14/)
      expect(blockers).to include(/#{Regexp.escape(younger.name)} is 13/)
    end

    it "reports venture-level and person-level problems together" do
      event.update!(operator_vetting_status: :unvetted, business_category: "crafts")
      too_young = create(:user, :minor, birthday: 14.years.ago.to_date)
      create(:organizer_position, event:, user: too_young)

      # Unvetted, wrong category, and one operator under the floor.
      expect(described_class.new(event:).blockers.size).to eq(3)
    end
  end

  describe "#eligible!" do
    it "passes silently when eligible" do
      expect(eligibility.eligible!).to be(true)
    end

    # Raising rather than returning false, for the call sites where continuing
    # would collect money Fuime is not entitled to collect.
    it "raises with the reasons when not", :merchant_of_record do
      event.update!(business_category: "food")

      expect { described_class.new(event:).eligible! }
        .to raise_error(described_class::Ineligible, /service and digital businesses/)
    end
  end
end
