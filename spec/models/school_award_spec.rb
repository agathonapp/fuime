# frozen_string_literal: true

require "rails_helper"

# Fuime: Alpha School's "$100 per A", as a record.
#
# The most important example in this file is the last one, and it does not test
# behaviour at all — it fails the suite if a grade-shaped column is ever added to this
# table. Same shape as the PII guard on guardian_verifications, for the same reason:
# the safest way to hold sensitive data is to have nowhere to put it.
RSpec.describe SchoolAward, type: :model do
  let(:school_tree) { build_school_tree }
  let(:school)  { school_tree[0] }
  let(:venture) { school_tree[2] }

  let!(:school_account) { create(:stripe_connected_account, :ready, event: school) }
  let!(:guide)   { create_school_manager(school) }
  let!(:student) { create_student(venture) }

  def build_award(**attrs)
    described_class.new(
      {
        event: venture,
        school_event: school,
        awarded_to: student,
        awarded_by: guide,
        amount_cents: 10_000,
        awarded_on: Date.current
      }.merge(attrs)
    )
  end

  it "is valid for a student on a venture the school funds" do
    expect(build_award).to be_valid
  end

  describe "who may fund it" do
    # Conservation only holds inside one Stripe account. An award naming an event that
    # does not hold this venture's money would debit a subledger in one account and
    # credit one in another — inventing money on the credit side.
    it "refuses a school that doesn't hold the venture's money" do
      other_school, _cohort, _v = build_school_tree(school_name: "Beta School")
      create(:stripe_connected_account, :ready, event: other_school)

      award = build_award(school_event: other_school)

      expect(award).not_to be_valid
      expect(award.errors[:school_event].join).to match(/doesn't hold this venture's money/)
    end

    it "refuses when the venture has no payment account at all" do
      school_account.destroy!

      award = build_award(event: venture.reload)

      expect(award).not_to be_valid
      expect(award.errors[:event].join).to match(/isn't set up to hold money/)
    end
  end

  describe "who it names" do
    # The 1099 total accrues against the named person, so naming someone unconnected
    # to the business would make that total meaningless.
    it "refuses a student with no position on the venture" do
      award = build_award(awarded_to: create(:user, birthday: 15.years.ago.to_date))

      expect(award).not_to be_valid
      expect(award.errors[:awarded_to].join).to match(/isn't a member of this venture/)
    end
  end

  describe "the amount" do
    it "refuses zero" do
      expect(build_award(amount_cents: 0)).not_to be_valid
    end

    # Reversals go through `voided_at`, which posts opposing ledger lines. A negative
    # award would be a second, silent way to do the same thing.
    it "refuses a negative amount" do
      expect(build_award(amount_cents: -10_000)).not_to be_valid
    end
  end

  describe "the reporting threshold" do
    def grant(cents, on: Date.current, to: student)
      described_class.create!(
        event: venture, school_event: school, awarded_to: to, awarded_by: guide,
        amount_cents: cents, awarded_on: on
      )
    end

    it "totals a student's awards for the year" do
      grant(10_000)
      grant(10_000)

      expect(described_class.reportable_total_cents(awarded_to: student, school_event: school))
        .to eq(20_000)
    end

    # Six A's at $100. The number the school needs to see coming.
    it "reports at $600" do
      6.times { grant(10_000) }

      expect(described_class.reportable?(awarded_to: student, school_event: school)).to be true
    end

    it "does not report at five A's" do
      5.times { grant(10_000) }

      expect(described_class.reportable?(awarded_to: student, school_event: school)).to be false
    end

    it "ignores voided awards" do
      6.times { grant(10_000) }
      described_class.last.update!(voided_at: Time.current, voided_by: guide)

      expect(described_class.reportable_total_cents(awarded_to: student, school_event: school))
        .to eq(50_000)
      expect(described_class.reportable?(awarded_to: student, school_event: school)).to be false
    end

    # Per person, not per venture: the threshold is the school's obligation toward one
    # human being.
    it "does not mix two students on the same venture together" do
      cofounder = create_student(venture)
      6.times { grant(10_000) }
      grant(10_000, to: cofounder)

      expect(described_class.reportable?(awarded_to: cofounder, school_event: school)).to be false
      expect(described_class.reportable?(awarded_to: student, school_event: school)).to be true
    end

    it "does not count a previous year" do
      6.times { grant(10_000, on: Date.new(Date.current.year - 1, 6, 1)) }

      expect(described_class.reportable?(awarded_to: student, school_event: school)).to be false
    end
  end

  # ── The guard ─────────────────────────────────────────────────────────────
  #
  # "$100 per A" is grade data, and grades are education records under FERPA
  # (20 U.S.C. § 1232g). Alpha School is the covered entity; Fuime holding them would
  # make it a "school official" under 34 CFR 99.31(a)(1)(i)(B), which needs a written
  # agreement, direct institutional control, and the exception named in the school's
  # annual notification — for data Fuime has no use for.
  #
  # Fuime needs "$100, this student, this date, school reference ABC-123". It does not
  # need to know it was an A in Algebra II. This fails the suite the moment someone
  # adds a column that would change that, which is cheaper than discovering it during
  # a district security review.
  describe "stores no academic records" do
    let(:forbidden_column_fragments) do
      %w[
        grade gpa score subject course class_name term semester quarter
        transcript assignment exam test_ mark_ percentile rank
      ].freeze
    end

    it "has no column that could hold an education record" do
      offending = described_class.column_names.select do |column|
        forbidden_column_fragments.any? { |fragment| column.downcase.include?(fragment) }
      end

      expect(offending).to be_empty,
                           "SchoolAward must not store academic records (FERPA — see " \
                           "CreateSchoolAwards). Offending columns: #{offending.join(', ')}. " \
                           "The school keeps the grades; Fuime keeps the money and an " \
                           "opaque `reference` back to them."
    end

    it "keeps `reference` opaque rather than structured" do
      # A single free-text pointer is the whole interface. If this ever becomes a
      # jsonb blob or gains siblings, the reasoning above needs revisiting first.
      expect(described_class.columns_hash["reference"].type).to eq(:string)
    end
  end
end
