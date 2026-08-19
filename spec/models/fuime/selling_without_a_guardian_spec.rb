# frozen_string_literal: true

require "rails_helper"

# Fuime: a teenager can SELL without a parent attached, and cannot be PAID
# without one.
#
# ── Why this file exists rather than more examples in the four it touches ───
#
# The change made on 2026-08-16 is one decision spread across five objects:
# Fuime::OperatorEligibility (stopped asking), Event::Application (stopped asking
# at activation), User (stopped asking for the right to operate), EventPolicy
# (started asking again for payouts) and Fuime::PayableAssessment (started asking
# for payout runs). Each of those has its own spec proving its own half.
#
# None of them proves the PROPERTY, and the property is the entire point: there
# must be no path where money reaches a minor with no adult on the account. A
# per-object spec cannot see that — it is exactly the shape of thing that stays
# green while the fifth object quietly loses its check.
#
# So this asserts both directions end to end, and it is deliberately paranoid
# about the second one. See Fuime::OperatorEligibility#umbrella_scope_blockers
# for the reasoning and for what the decision costs (MOR_MIGRATION_PLAN §7 Q3).
RSpec.describe "selling without a guardian", :merchant_of_record do
  # 16 so the age floor is satisfied and this file is about the guardian only.
  # No guardianship row at all — not pending, not revoked, none.
  let(:teen) { create(:user, :minor, birthday: 16.years.ago.to_date) }

  # PayableAssessment takes an explicit policy and period so a run is
  # reproducible; the values are immaterial here, only the structural refusal is.
  def assess(event)
    Fuime::PayableAssessment.new(
      event:,
      policy: Fuime::PayoutPolicy.new(hold_days: 7, reserve_basis_points: 0,
                                      reserve_window_days: 90, maximum_cents: 250_00,
                                      minimum_cents: 10_00),
      period_end: Date.current
    ).call
  end

  let(:event) do
    create(:event, business_category: "services").tap do |e|
      e.update!(operator_vetting_status: :approved, operator_vetted_at: Time.current)
      create(:organizer_position, event: e, user: teen, role: :manager)
    end
  end

  describe "the half that has to be open" do
    it "lets them sell with no guardian and no connected account" do
      expect(teen.has_active_guardian?).to be(false)
      expect(event.payment_account).to be_nil

      expect(event.reload.accepts_payments?).to be(true)
      expect(event.selling_blockers).to be_empty
    end

    it "lets them act on their own venture" do
      expect(teen.permitted_to_operate_business?).to be(true)
      expect(EventPolicy.new(teen, event).manage_offers?).to be(true)
    end

    it "lets them publish something to sell" do
      offer = Fuime::Offer.new(event:, name: "Lawn mow", price_cents: 35_00)

      expect(offer.save).to be(true)
      expect { offer.publish! }.not_to raise_error
      expect(offer.reload).to be_published
    end

    # The activation gate. Without this a venture never comes into existence for
    # a parentless teen and every example above is unreachable in practice.
    it "activates their application" do
      application = create(:event_application, user: teen)

      expect {
        application.activate_event!(risk_level: :slight,
                                    point_of_contact: create(:user, :make_admin))
      }.not_to raise_error
      expect(application.reload.event).to be_present
    end
  end

  describe "the half that must stay shut" do
    it "refuses to put them in a payout run, naming them" do
      create(:fuime_payout_method, :verified, event:)
      assessment = assess(event)

      expect(assessment).not_to be_payable
      expect(assessment.skip_reason).to include("parent or guardian")
      expect(assessment.skip_reason).to include(teen.name)
    end

    # Not merely "cannot be approved" — cannot be ASKED. See
    # EventPolicy#request_payout?: a request nobody is able to decide wedges the
    # venture behind `one_pending_request_per_venture` forever.
    it "refuses to let them even request a payout" do
      expect(EventPolicy.new(teen, event).request_payout?).to be(false)
    end

    it "has nobody who can approve one either" do
      expect(EventPolicy.new(teen, event).decide_payout?).to be(false)
      expect(event.overseeing_guardians).to be_empty
    end

    # A pending invite is not a guardian. This is the case most likely to be got
    # wrong by a future refactor, because a Guardianship row EXISTS and a check
    # written as `guardianships.any?` would pass.
    it "is not satisfied by a guardianship that is only invited" do
      create(:guardianship, minor: teen) # status: :pending
      create(:fuime_payout_method, :verified, event:)

      expect(EventPolicy.new(teen, event).request_payout?).to be(false)
      expect(assess(event).skip_reason)
        .to include("parent or guardian")
    end
  end

  describe "once the parent arrives" do
    it "opens the payout path that was shut" do
      create(:guardianship, :active, minor: teen)
      create(:fuime_payout_method, :verified, event:)

      expect(teen.reload.has_active_guardian?).to be(true)
      expect(EventPolicy.new(teen.reload, event).request_payout?).to be(true)
      expect(assess(event).skip_reason)
        .not_to include("parent or guardian")
    end
  end

  # The guardian gate is MoR-only. Under Connect the guardian owns the Stripe
  # account, so a venture without one has an owner who genuinely cannot act — and
  # every gate above must still be shut. Untagged deliberately: this example's
  # subject is the OTHER world.
  # `merchant_of_record: false` explicitly, because the tag on the outer
  # `describe` is inherited by every example beneath it — including this one,
  # which would then assert the opposite of what it says while passing.
  describe "under Connect, untouched", merchant_of_record: false do
    it "still refuses to let a parentless minor operate" do
      teen_c = create(:user, :minor, birthday: 16.years.ago.to_date)

      expect(teen_c.permitted_to_operate_business?).to be(false)
    end
  end

end
