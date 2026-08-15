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

    it "blocks every category outside the Phase 1 slice" do
      (Event::BUSINESS_CATEGORIES - described_class::ELIGIBLE_CATEGORIES).each do |category|
        event.update!(business_category: category)

        expect(described_class.new(event:).blockers)
          .to contain_exactly(/service businesses only/),
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

    # The floor on operators is stricter than the platform's floor on users,
    # which stays at 13 per L6. A 14-year-old may hold an account and may not
    # sell — so this is a gate on the venture, never on the signup.
    it "is stricter than the platform's own age floor" do
      expect(described_class::MINIMUM_OPERATOR_AGE).to be > 13
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

  describe "guardianship", :merchant_of_record do
    it "blocks a minor with no guardian" do
      alone = create(:user, :minor, birthday: 16.years.ago.to_date)
      create(:organizer_position, event:, user: alone)

      expect(described_class.new(event:).blockers)
        .to contain_exactly(/#{Regexp.escape(alone.name)} needs a parent or guardian/)
    end

    it "blocks when the guardianship is still only an invite" do
      pending_teen = create(:user, :minor, birthday: 16.years.ago.to_date)
      create(:guardianship, minor: pending_teen) # status: :pending
      create(:organizer_position, event:, user: pending_teen)

      expect(described_class.new(event:)).not_to be_eligible
    end

    # Event#has_overseeing_guardian? is satisfied by ONE guardian anywhere on the
    # venture. Eligibility has to be true of every operator individually, or a
    # teen with no parent on file could sell behind a co-founder who has one.
    it "is not satisfied by a co-founder's guardian" do
      unguarded = create(:user, :minor, birthday: 16.years.ago.to_date)
      create(:organizer_position, event:, user: unguarded)

      expect(event.has_overseeing_guardian?).to be(true)
      expect(described_class.new(event:)).not_to be_eligible
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
      alone = create(:user, :minor, birthday: 17.years.ago.to_date)
      create(:organizer_position, event:, user: young)
      create(:organizer_position, event:, user: alone)

      blockers = described_class.new(event:).blockers

      expect(blockers).to include(/#{Regexp.escape(young.name)} is 14/)
      expect(blockers).to include(/#{Regexp.escape(alone.name)} needs a parent or guardian/)
    end

    it "reports venture-level and person-level problems together" do
      event.update!(operator_vetting_status: :unvetted, business_category: "crafts")
      alone = create(:user, :minor, birthday: 16.years.ago.to_date)
      create(:organizer_position, event:, user: alone)

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
        .to raise_error(described_class::Ineligible, /service businesses only/)
    end
  end
end
