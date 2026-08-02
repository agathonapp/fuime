# frozen_string_literal: true

require "rails_helper"

RSpec.describe OrganizerPositionInvite, type: :model do
  it "is valid" do
    organizer_position_invite = create(:organizer_position_invite)
    expect(organizer_position_invite).to be_valid
    expect(organizer_position_invite).to_not be_accepted
    expect(organizer_position_invite).to_not be_rejected
    expect(organizer_position_invite).to_not be_cancelled
  end

  context "missing sender" do
    it "is not valid" do
      organizer_position_invite = create(:organizer_position_invite)
      organizer_position_invite.sender = nil

      expect(organizer_position_invite).to_not be_valid
    end
  end

  context "missing event" do
    it "is not valid" do
      organizer_position_invite = create(:organizer_position_invite)
      organizer_position_invite.event = nil

      expect(organizer_position_invite).to_not be_valid
    end
  end

  context "has user" do
    it "returns user" do
      user = create(:user)
      organizer_position_invite = create(:organizer_position_invite, user:)

      expect(organizer_position_invite.user).to eq(user)
    end
  end

  context "sent to self" do
    it "auto-accepts invite" do
      invite = create(:organizer_position_invite, :sent_to_self)
      expect(invite).to be_accepted
    end
  end

  describe "#accept" do
    it "can be accepted" do
      invite = create(:organizer_position_invite)
      expect(OrganizerPosition).to receive(:new)
      expect(invite.accept).to eq(true)
      expect(invite).to be_accepted
    end

    it "can't be accepted when canceled" do
      invite = create(:organizer_position_invite, :canceled)
      expect(OrganizerPosition).not_to receive(:new)
      expect(invite.accept).to eq(false)
      expect(invite).not_to be_accepted
    end

    it "can't be accepted when already accepted" do
      invite = create(:organizer_position_invite, :accepted)
      expect(invite).to be_accepted
      expect(OrganizerPosition).not_to receive(:new)
      expect(invite.accept).to eq(false)
    end
  end

  describe "#reject" do
    it "can be rejected" do
      invite = create(:organizer_position_invite)
      expect(invite.reject).to eq(true)
      expect(invite).to be_rejected
    end

    it "can't be rejected when canceled" do
      invite = create(:organizer_position_invite, :canceled)
      expect(invite.reject).to eq(false)
      expect(invite).not_to be_rejected
    end

    it "can't be rejected twice" do
      invite = create(:organizer_position_invite, :rejected)
      expect(invite).to be_rejected
      expect(invite.reject).to eq(false)
    end
  end

  describe "#cancel" do
    it "can be canceled" do
      invite = create(:organizer_position_invite)
      expect(invite.cancel).to eq(true)
      expect(invite).to be_cancelled
    end

    it "can't be canceled when already accepted" do
      invite = create(:organizer_position_invite, :accepted)
      expect(invite.cancel).to eq(false)
    end

    it "can't be canceled when already rejected" do
      invite = create(:organizer_position_invite, :rejected)
      expect(invite.cancel).to eq(false)
    end
  end

  describe "#pending_signature?" do
    # FUIME: with no agreement configured a signee invite used to wait on a
    # contract that never arrives, so accept() returned false and the applicant
    # could never join the org their application had just created.
    context "when no agreement is configured" do
      before do
        allow_any_instance_of(Event::Plan::Standard)
          .to receive(:contract_available?).and_return(false)
      end

      it "is not pending, and a signee invite can be accepted" do
        invite = create(:organizer_position_invite, is_signee: true)

        expect(invite).to_not be_pending_signature
        expect(invite.accept).to eq(true)
        expect(invite.reload).to be_accepted
        expect(invite.organizer_position).to be_present
      end
    end

    context "when an agreement is configured" do
      before do
        allow_any_instance_of(Event::Plan::Standard)
          .to receive(:contract_available?).and_return(true)
      end

      it "still holds a signee invite until something is signed" do
        invite = create(:organizer_position_invite, is_signee: true)

        expect(invite).to be_pending_signature
        expect(invite.accept).to eq(false)
      end

      it "does not hold a non-signee invite" do
        invite = create(:organizer_position_invite, is_signee: false)

        expect(invite).to_not be_pending_signature
      end
    end
  end

  context "when sending another invite to an existing user" do
    it "fails validation" do
      invite = create(:organizer_position_invite)
      expect(invite.accept).to eq(true)

      expect(build(:organizer_position_invite, event: invite.event, user: invite.user)).to_not be_valid
    end

    it "fails validation when pending invite" do
      invite = create(:organizer_position_invite)

      expect(build(:organizer_position_invite, event: invite.event, user: invite.user)).to_not be_valid
    end
  end
end
