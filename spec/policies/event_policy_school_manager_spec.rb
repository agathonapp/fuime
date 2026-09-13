# frozen_string_literal: true

require "rails_helper"

# Fuime: on a school venture, "manager" must mean the school — never the student.
#
# ── The hole this file exists for ──────────────────────────────────────────
#
# Four policy branches carry the same reasoning: a school programme has no
# guardian by design, because the school is in loco parentis, so the responsible
# adult is a manager — the guide or the business office. Each of them called
# `manager?`.
#
# `manager?` resolves through `Event#ancestor_ids`, and that method begins
# `[id]`. A position on the venture ITSELF therefore counts, and every founder
# has exactly that: `Event::Application#activate_event!` invites them with
# `role: :manager`, and the column defaults to manager anyway.
#
# So on a School-plan venture the student satisfied every check written for the
# school. They could point Fuime's payouts at a bank account they control,
# approve that payout, mark it settled, and grant themselves the school's award
# balance — with no adult in the loop at any point. And the guardian requirement
# could not catch it, because `Event#payout_setup_blockers` deliberately skips
# the guardian on an institutionally sponsored venture: the school branch
# REPLACES the L2 gate, so a branch that resolves to the student leaves no gate.
#
# The specs could not see it because `SchoolTree#create_student` made the student
# a `:member`, a shape no real path produces. That fixture is now `:manager`,
# which is why this file can exist at all.
RSpec.describe EventPolicy, "school manager vs student-manager" do
  let(:tree) { build_school_tree }
  let(:school) { tree[0] }
  let(:venture) { tree[2] }

  let(:guide) { create_school_manager(school) }
  let(:student) { create_student(venture) }

  # The student really is a manager of their own venture — this is the shape the
  # product creates, not a contrivance. If this ever stops being true the rest of
  # the file is testing nothing.
  it "confirms the student holds manager on their own venture" do
    expect(OrganizerPosition.role_at_least?(student, venture, :manager)).to be(true)
  end

  describe "the student" do
    subject(:policy) { described_class.new(student, venture) }

    it "cannot choose where their own payouts go" do
      expect(policy.connect_payout_method?).to be(false)
    end

    it "cannot approve their own payout" do
      expect(policy.decide_payout?).to be(false)
    end

    it "cannot declare their own payout settled" do
      expect(policy.settle_payout?).to be(false)
    end

    it "cannot grant themselves the school's award money" do
      expect(policy.grant_school_award?).to be(false)
    end

    # The half that must keep working: it is still their venture and still their
    # money to look at.
    it "can still see the payout destination and the awards" do
      expect(policy.payout_method?).to be(true)
      expect(policy.school_awards?).to be(true)
    end
  end

  describe "the guide, holding manager on the school itself" do
    subject(:policy) { described_class.new(guide, venture) }

    it "can connect the destination, decide, settle and grant" do
      expect(policy.connect_payout_method?).to be(true)
      expect(policy.decide_payout?).to be(true)
      expect(policy.settle_payout?).to be(true)
      expect(policy.grant_school_award?).to be(true)
    end
  end

  # The subtlety, and the thing a first attempt at this fix got wrong: on the
  # school's OWN pages the record IS the institution, and the guide's position is
  # on that very record. A rule phrased as "never the record itself" locks a
  # school out of its own treasury page. Authority is read from the school node
  # and above — never from what hangs below it.
  describe "the guide on the school's own record" do
    subject(:policy) { described_class.new(guide, school) }

    it "keeps the powers there too" do
      expect(policy.connect_payout_method?).to be(true)
      expect(policy.grant_school_award?).to be(true)
    end
  end

  # A manager of somebody else's school must not reach across.
  describe "a guide from a different school" do
    subject(:policy) { described_class.new(create_school_manager(build_school_tree(school_name: "Other School")[0]), venture) }

    it "has none of those powers here" do
      expect(policy.connect_payout_method?).to be(false)
      expect(policy.decide_payout?).to be(false)
      expect(policy.grant_school_award?).to be(false)
    end
  end
end
