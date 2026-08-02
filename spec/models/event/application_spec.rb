# frozen_string_literal: true

require "rails_helper"

RSpec.describe Event::Application, type: :model do
  # FUIME-DIVERGENCE: upstream mirrored every application into a Hack Club Airtable
  # base via Event::ApplicationSyncToAirtableJob on an after_commit hook. Fuime keeps
  # applications entirely in Postgres and reviews them in the HCB admin console, so
  # saving an application must not enqueue any external sync at all.
  describe "saving an application" do
    let!(:application) { create(:event_application) }

    it "does not enqueue any background job" do
      expect {
        application.update!(name: "Updated Name")
      }.not_to have_enqueued_job
    end

    it "does not define the removed Airtable sync constant" do
      expect(defined?(Event::ApplicationSyncToAirtableJob)).to be_nil
    end
  end

  describe "aasm state as the source of truth" do
    let!(:application) { create(:event_application, aasm_state: "submitted") }

    it "exposes a human-readable state for the admin console" do
      expect(application.aasm.human_state).to eq("Submitted")
    end
  end
end
