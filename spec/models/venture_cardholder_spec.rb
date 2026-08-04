# frozen_string_literal: true

require "rails_helper"

# Fuime: who may hold a card, and in which role.
#
# The role split is the thing that makes cards for minors legitimate rather than
# something being hidden from Stripe: the guardian is the ACCOUNTHOLDER who carries
# the liability, the minor is an AUTHORIZED USER who holds an access device. Stripe's
# cardholder floor is 13 and Celtic's Authorized User Terms carry no minimum age, so
# the age is not what is being policed here — the roles and the acceptances are.
RSpec.describe VentureCardholder, type: :model do
  let(:venture) { create(:event) }
  let(:minor) { create(:user, :minor, birthday: 15.years.ago.to_date) }
  let(:guardian) { create(:user, birthday: 40.years.ago.to_date) }

  before do
    create(:organizer_position, event: venture, user: minor)
    create(:guardianship, :active, guardian:, minor:)
  end

  describe "the accountholder role" do
    it "accepts an overseeing guardian" do
      holder = build(:venture_cardholder, event: venture, user: guardian, role: described_class::ACCOUNTHOLDER)

      expect(holder).to be_valid
    end

    # The assertion the arrangement rests on. A minor recorded as accountholder would
    # misstate who is liable for the card to anyone reading the record later.
    it "refuses a minor" do
      holder = build(:venture_cardholder, event: venture, user: minor, role: described_class::ACCOUNTHOLDER)

      expect(holder).not_to be_valid
      expect(holder.errors[:user].join).to match(/adult/i)
    end

    it "refuses an adult who is not a guardian of this venture" do
      stranger = create(:user, birthday: 35.years.ago.to_date)
      holder = build(:venture_cardholder, event: venture, user: stranger, role: described_class::ACCOUNTHOLDER)

      expect(holder).not_to be_valid
      expect(holder.errors[:user].join).to match(/guardian overseeing/i)
    end

    # Fail closed on unknown age, matching Guardianship#activation_blockers: a stub
    # user with no birthday must not be able to hold the liable role.
    it "refuses an adult whose age is unknown" do
      unknown = create(:user, birthday: nil)
      create(:guardianship, :active, guardian: unknown, minor: create(:user, :minor))
      holder = build(:venture_cardholder, event: venture, user: unknown, role: described_class::ACCOUNTHOLDER)

      expect(holder).not_to be_valid
    end
  end

  describe "the authorized user role" do
    it "accepts a teen who holds a position on the venture" do
      holder = build(:venture_cardholder, event: venture, user: minor)

      expect(holder).to be_valid
    end

    # `build_context: false` stops the factory creating the position this example is
    # trying to prove is required.
    it "refuses someone with no position on the venture" do
      outsider = create(:user, :minor)
      holder = build(:venture_cardholder, event: venture, user: outsider,
                                          role: described_class::AUTHORIZED_USER,
                                          build_context: false)

      expect(holder).not_to be_valid
      expect(holder.errors[:user].join).to match(/position on this venture/i)
    end

    # Oversight is not participation. A guardian holding an operating card would put
    # them in the role the guardianship design deliberately keeps them out of.
    it "refuses the guardian, who oversees rather than operates" do
      holder = build(:venture_cardholder, event: venture, user: guardian,
                                          role: described_class::AUTHORIZED_USER,
                                          build_context: false)

      expect(holder).not_to be_valid
    end
  end

  describe "uniqueness" do
    # A second Stripe Cardholder for the same person would split their card history.
    it "allows only one cardholder per person per venture" do
      create(:venture_cardholder, event: venture, user: minor)
      second = build(:venture_cardholder, event: venture, user: minor)

      expect(second).not_to be_valid
      expect(second.errors[:user_id].join).to match(/already has a cardholder/i)
    end

    it "allows the same person on a different venture" do
      create(:venture_cardholder, event: venture, user: minor)

      other = create(:event)
      create(:organizer_position, event: other, user: minor)

      expect(build(:venture_cardholder, event: other, user: minor)).to be_valid
    end
  end

  describe "terms acceptance" do
    it "records the version, time and provenance" do
      holder = create(:venture_cardholder, :terms_pending, event: venture, user: minor)

      holder.accept_terms!(ip: "203.0.113.9", user_agent: "Mobile Safari")

      expect(holder).to be_terms_accepted
      expect(holder.terms_version).to eq(described_class::CURRENT_TERMS_VERSION)
      expect(holder.terms_accepted_ip).to eq("203.0.113.9")
    end

    # An acceptance of a superseded version does not carry forward — the whole reason
    # the version is stored rather than a boolean.
    it "does not count an acceptance of an older version" do
      holder = create(:venture_cardholder, :stale_terms, event: venture, user: minor)

      expect(holder).not_to be_terms_accepted
    end

    it "does not count a missing acceptance" do
      expect(create(:venture_cardholder, :terms_pending, event: venture, user: minor)).not_to be_terms_accepted
    end
  end

  describe "#issuable? and #issuance_blockers" do
    let(:holder) { create(:venture_cardholder, event: venture, user: minor) }

    it "is issuable when the account supports cards, Stripe is happy, and terms are accepted" do
      create(:stripe_connected_account, :cards_active, event: venture, owner: guardian)

      expect(holder.reload).to be_issuable
      expect(holder.issuance_blockers).to be_empty
    end

    # `controller` is create-only at Stripe, so this is permanent. The blocker says so
    # rather than implying the family should wait.
    it "explains that a payments-only venture cannot gain cards later" do
      create(:stripe_connected_account, :ready, event: venture, owner: guardian)

      expect(holder.reload).not_to be_issuable
      expect(holder.issuance_blockers.join).to match(/set up again/i)
    end

    it "explains when Stripe has not switched issuing on yet" do
      account = create(:stripe_connected_account, :cards_enabled, :ready, event: venture, owner: guardian)
      account.update!(capabilities: account.capabilities.merge("card_issuing" => "pending"))

      expect(holder.reload.issuance_blockers.join).to match(/hasn't enabled card issuing/i)
    end

    it "reports unaccepted terms as a blocker" do
      create(:stripe_connected_account, :cards_active, event: venture, owner: guardian)
      pending_holder = create(:venture_cardholder, :terms_pending, event: venture, user: create(:user, :minor).tap { |u|
        create(:organizer_position, event: venture, user: u)
      })

      expect(pending_holder.issuance_blockers.join).to match(/terms haven't been accepted/i)
    end
  end
end
