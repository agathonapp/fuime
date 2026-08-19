# frozen_string_literal: true

require "rails_helper"

# Fuime: the roster board's per-founder reading.
#
# Worth testing directly rather than only through the admin page, because it is
# read fifty times in a row under time pressure to decide who to walk over to,
# and both of its properties are easy to break invisibly: the funnel must not go
# backwards, and `next_action` must name the thing that is ACTUALLY blocking
# rather than the first thing a naive check notices.
RSpec.describe Fuime::FounderProgress, :merchant_of_record do
  let(:founder) { create(:user, :minor, birthday: 16.years.ago.to_date) }
  let(:application) { create(:event_application, user: founder, name: "Lawn Care") }

  subject(:progress) { described_class.new(application: application) }

  def give_them_a_venture!(category: "services", vetted: true)
    event = create(:event, business_category: category)
    event.update!(operator_vetting_status: vetted ? :approved : :unvetted,
                  operator_vetted_at: (Time.current if vetted))
    create(:organizer_position, event:, user: founder)
    application.update!(event:)
    application.reload
    event
  end

  describe "the funnel" do
    it "starts at applied when there is no venture yet" do
      expect(progress.stage).to eq(:applied)
      expect(progress.next_action).to include("Set up the business")
    end

    it "reaches venture_created but not vetted" do
      give_them_a_venture!(vetted: false)

      expect(progress.stage).to eq(:venture_created)
      expect(progress.next_action).to include("Approve them to sell")
    end

    it "reaches can_sell once vetted and eligible" do
      give_them_a_venture!

      expect(progress.stage).to eq(:can_sell)
      expect(progress.next_action).to include("Publish something to sell")
    end

    it "reaches listed once something is published" do
      event = give_them_a_venture!
      Fuime::Offer.create!(event:, name: "Lawn mow", price_cents: 3500).publish!

      expect(progress.stage).to eq(:listed)
      expect(progress.next_action).to include("Make a first sale")
    end

    it "reaches sold once money has actually landed on the ledger" do
      event = give_them_a_venture!
      Fuime::Offer.create!(event:, name: "Lawn mow", price_cents: 3500).publish!
      create(:canonical_transaction, event:, amount_cents: 3500)

      expect(progress.stage).to eq(:sold)
      expect(progress).to be_done
      expect(progress.next_action).to include("Nothing")
    end

    # A refund or a fee line is negative. Counting any transaction as a sale would
    # mark a founder "sold" on the strength of Fuime charging them.
    it "does not count a negative ledger line as a sale" do
      event = give_them_a_venture!
      create(:canonical_transaction, event:, amount_cents: -225)

      expect(progress.stage).not_to eq(:sold)
    end
  end

  # The reason `next_action` exists at all. Naming the state ("not eligible")
  # sends an organiser to ask a question; naming the blocker sends them to the
  # right person with the right sentence.
  describe "naming the real blocker" do
    it "reports the age floor rather than a generic ineligibility" do
      young = create(:user, :minor, birthday: 14.years.ago.to_date)
      application.update!(user: young)
      event = create(:event, business_category: "services")
      event.update!(operator_vetting_status: :approved, operator_vetted_at: Time.current)
      create(:organizer_position, event:, user: young)
      application.update!(event:)

      expect(described_class.new(application: application.reload).next_action)
        .to match(/is 14/)
    end

    it "reports an unchosen business category rather than skipping to publishing" do
      give_them_a_venture!(category: nil)

      expect(progress.next_action).to include("Choose what this venture sells")
    end
  end

  # Tracked apart from the funnel on purpose: under merchant-of-record a missing
  # guardian does not block selling, it blocks being PAID. Merging it in would
  # have organisers chasing parents on the day instead of chasing first sales.
  describe "the guardian, separately" do
    it "flags a minor with no guardian without moving them down the funnel" do
      give_them_a_venture!

      expect(progress).to be_guardian_pending
      expect(progress.stage).to eq(:can_sell)
      expect(progress.next_action).not_to include("guardian")
    end

    it "clears once a guardian accepts" do
      give_them_a_venture!
      create(:guardianship, :active, minor: founder)

      expect(described_class.new(application: application.reload)).not_to be_guardian_pending
    end

    it "never flags an adult, who cannot have one" do
      adult = create(:user, birthday: 30.years.ago.to_date)
      application.update!(user: adult)

      expect(described_class.new(application: application.reload)).not_to be_guardian_pending
    end
  end

end
