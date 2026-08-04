# frozen_string_literal: true

require "rails_helper"

# Fuime: the guardian's read access to a venture they are responsible for.
#
# §3 of the guardian agreement ("You can see everything") tells the signing
# adult they will have visibility into the minor's transactions, balances and
# team, and that it "cannot be turned off by the minor". Before this, accepting
# a guardianship created no OrganizerPosition, so `EventPolicy#reader?` was
# false for every guardian and the promise had no mechanism at all.
#
# These examples are the contract for that promise. The last two are the ones
# that matter most, and are the reason the access derives from the guardianship
# rather than from a membership row the minor could delete.
RSpec.describe EventPolicy, type: :policy do
  let(:event) { create(:event) }
  let(:minor) { create(:user, :minor) }
  let(:guardian) { create(:user) }

  # The minor runs the venture; that is what puts the guardian in scope for it.
  before { create(:organizer_position, event:, user: minor) }

  # EventPolicy treats `reader?`, `member?` and `manager?` as PRIVATE helpers sitting
  # behind its public predicates — that is upstream HCB's structure, not an
  # oversight, and Fuime must not widen them just to make assertions convenient
  # (Rule 6: internals keep upstream shape so fixes can still be merged).
  #
  # These examples are nonetheless unit tests of exactly those helpers, because the
  # guardian promise in agreement §3 is specifically about READ access and about
  # `member?`/`manager?` staying false. So the probe reaches past the visibility in
  # one place, deliberately and visibly, instead of eight examples each doing it or
  # the policy being made public to suit the test.
  PolicyProbe = Struct.new(:policy) do
    def reader? = policy.send(:reader?)
    def member? = policy.send(:member?)
    def manager? = policy.send(:manager?)
  end

  def policy_for(user)
    PolicyProbe.new(described_class.new(user, event))
  end

  context "with an active guardianship over a member of the venture" do
    before { create(:guardianship, :active, guardian:, minor:) }

    it "grants the guardian read access" do
      expect(policy_for(guardian).reader?).to be true
    end

    # The other half of the design: oversight is not participation. A guardian
    # who disagrees with what they see revokes consent; they do not reach into
    # the venture and act on the minor's behalf.
    it "does not let the guardian act on the venture" do
      expect(policy_for(guardian).member?).to be false
      expect(policy_for(guardian).manager?).to be false
    end
  end

  context "with a pending guardianship" do
    before { create(:guardianship, guardian:, minor:) }

    # An invited-but-unsigned adult has accepted nothing and is owed nothing.
    it "grants no read access" do
      expect(policy_for(guardian).reader?).to be false
    end
  end

  context "after the guardian withdraws consent" do
    let!(:guardianship) { create(:guardianship, :active, guardian:, minor:) }

    it "removes read access immediately" do
      expect(policy_for(guardian).reader?).to be true

      guardianship.revoke!(revoked_by: guardian)

      # A fresh policy object, because the point is that the check reads live
      # state — `User#permitted_to_operate_business?` and this both do, so a
      # withdrawal takes effect on the next request rather than at next login.
      expect(policy_for(guardian).reader?).to be false
    end
  end

  context "for an unrelated adult" do
    it "grants no read access" do
      stranger = create(:user)
      create(:guardianship, :active, guardian: stranger, minor: create(:user, :minor))

      expect(policy_for(stranger).reader?).to be false
    end
  end

  # The clause the whole design turns on. If guardian visibility were granted by
  # inserting an OrganizerPosition at acceptance, the minor — who is a manager of
  # their own venture — could delete that row and switch off the one guarantee
  # their parent was asked to rely on. Deriving it from the guardianship makes
  # that structurally impossible, and revocation is restricted to the guardian
  # and admins (GuardianshipPolicy#revoke?).
  describe "the minor cannot turn it off (agreement §3)" do
    let!(:guardianship) { create(:guardianship, :active, guardian:, minor:) }

    it "survives the minor having no way to remove the guardian from the team" do
      # There is no organizer position for the guardian to remove in the first
      # place — the access does not live there.
      expect(event.organizer_positions.where(user: guardian)).to be_empty
      expect(policy_for(guardian).reader?).to be true
    end

    it "does not let the minor revoke the guardianship" do
      expect(GuardianshipPolicy.new(minor, guardianship).revoke?).to be false
    end
  end
end
