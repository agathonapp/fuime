# frozen_string_literal: true

require "rails_helper"

RSpec.describe Fuime::FounderAdmission do
  def complete_application_for(user, **attrs)
    create(
      :event_application,
      user:,
      teen_led: true,
      name: "Maya's Art Prints",
      business_category: "services",
      description: "I sell prints.",
      address_country: "US",
      **attrs
    )
  end

  describe "under merchant-of-record", :merchant_of_record do
    let(:teen) { create(:user, :minor, birthday: 16.years.ago.to_date) }
    let(:application) { complete_application_for(teen, cosigner_email: "parent@example.com") }

    it "approves and activates without vetting" do
      application.mark_submitted!

      event = application.reload.event
      expect(event).to be_present
      expect(application).to be_approved
      expect(event).to be_operator_vetting_unvetted
      expect(event.accepts_payments?).to be(false)
    end

    it "is idempotent when the venture already exists" do
      application.mark_submitted!
      event = application.reload.event

      result = described_class.new(application:).call

      expect(result.status).to eq(:already_has_venture)
      expect(result.event).to eq(event)
      expect(Event.where(id: event.id).count).to eq(1)
    end
  end

  describe "under Connect (default)" do
    let(:teen) { create(:user, :minor, birthday: 16.years.ago.to_date) }
    let(:application) { complete_application_for(teen, cosigner_email: "parent@example.com") }

    it "does not weaken the guardian gate" do
      application.mark_submitted!

      expect(application.reload.event).to be_nil
      expect(application.activation_blockers.join).to match(/no active guardian/)
    end
  end
end
