# frozen_string_literal: true

require "rails_helper"

# Fuime: the category has to survive the trip from application to venture.
#
# This is the bug the business-type step exists to fix, asserted at the seam where
# it actually bit. Nothing used to carry `business_category` onto the Event, so
# every venture the funnel produced started blank — and under merchant-of-record
# `Fuime::OperatorEligibility::ELIGIBLE_CATEGORIES` is `%w[services]`, which a
# blank does not satisfy. Ventures were created already unable to sell and the
# vetting queue was where anybody found out.
RSpec.describe Event::Application, "business category", type: :model do
  let(:admin) { create(:user, :make_admin, birthday: 35.years.ago.to_date) }
  let(:teen) { create(:user, birthday: 16.years.ago.to_date, verified: true) }
  let(:guardian) { create(:user, birthday: 40.years.ago.to_date, verified: true) }

  before { Guardianship.create!(guardian:, minor: teen, status: :active) }

  def approved_application(**attrs)
    application = create(:event_application, user: teen, teen_led: true, **attrs)
    application.update!(aasm_state: :approved)
    application
  end

  it "derives itself from the chosen service" do
    application = approved_application(service_type: "tutoring")

    expect(application.business_category).to eq("services")
  end

  it "reaches the venture, so the operator is not born blocked" do
    application = approved_application(service_type: "lawn_and_garden")

    application.activate_event!(risk_level: 0, point_of_contact: admin)
    venture = application.reload.event

    expect(venture.business_category).to eq("services")
    expect(Fuime::OperatorEligibility::ELIGIBLE_CATEGORIES).to include(venture.business_category)
  end

  # Applications that predate the step have nothing to carry, and inventing
  # "services" for them would be inventing the answer that unblocks selling.
  it "leaves the venture blank when the application never answered" do
    application = approved_application

    application.activate_event!(risk_level: 0, point_of_contact: admin)

    expect(application.reload.event.business_category).to be_blank
  end

  # Retiring or renaming a service key later must not silently re-categorise a
  # venture that was already reviewed and approved under the old one.
  it "does not clear a category when its service key leaves the catalog" do
    application = approved_application(service_type: "tutoring")
    stub_const("Fuime::ServiceCatalog::SERVICES", [])

    application.update!(name: "Renamed")

    expect(application.reload.business_category).to eq("services")
  end
end
