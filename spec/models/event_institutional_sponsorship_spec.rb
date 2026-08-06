# frozen_string_literal: true

require "rails_helper"

# Fuime: the School plan, and the four walls it removes.
#
# Every one of these was a hard stop for a school before Event::Plan::School
# existed. The fourth is the one that took production down:
# PaymentSetupsController#acting_guardian raised ActionController::BadRequest
# with "(0 candidates)" on every school request to /:slug/payments/setup.
#
# The paired assertions matter as much as the positive ones. This must not become
# a way for a parent-backed venture to skip its guardian, so each context checks
# the ordinary Standard-plan venture still behaves exactly as before.
RSpec.describe "institutional sponsorship", type: :model do
  let(:teen) { create(:user, birthday: 15.years.ago.to_date) }

  def school_tree
    school = create(:event)
    school.plan&.update!(aasm_state: :inactive)
    Event::Plan::School.create!(event: school, aasm_state: :active)
    school.reload
    [school, create(:event, parent: school)]
  end

  describe "Event#institutionally_sponsored?" do
    it "is false for an ordinary venture" do
      expect(create(:event).institutionally_sponsored?).to be false
    end

    it "is true for the school itself" do
      school, _venture = school_tree

      expect(school.institutionally_sponsored?).to be true
    end

    it "is inherited by a student sub org that has its own ordinary plan" do
      _school, venture = school_tree

      # The point of resolving through ancestors: nobody sets the School plan on
      # several hundred student sub orgs, and forgetting one must not silently
      # ask that student's family for a guardian.
      expect(venture.plan).not_to be_a(Event::Plan::School)
      expect(venture.institutionally_sponsored?).to be true
    end
  end

  describe "the plan itself" do
    it "charges no revenue fee" do
      # Schools are billed per student per year for the software. A percentage of
      # each student's revenue on top would charge the same customer twice.
      expect(Event::Plan::School.new.revenue_fee).to eq(0.00)
    end

    it "is offerable in the plan picker" do
      expect(Event::Plan::School.selectable?).to be true
    end
  end

  describe "EventPolicy#setup_payments?" do
    it "lets a manager of the school connect Stripe on a student sub org" do
      school, venture = school_tree
      manager = create(:user)
      OrganizerPositionInvite.create!(event: school, user: manager, sender: manager, role: :manager)
                             .accept(show_onboarding: false)

      expect(EventPolicy.new(manager, venture.reload).setup_payments?).to be true
    end

    it "still refuses a manager on an ordinary venture, where a guardian is required" do
      venture = create(:event)
      manager = create(:user)
      OrganizerPositionInvite.create!(event: venture, user: manager, sender: manager, role: :manager)
                             .accept(show_onboarding: false)

      expect(EventPolicy.new(manager, venture.reload).setup_payments?).to be false
    end
  end

  describe "EventPolicy#permitted_to_operate_business?" do
    it "lets a guardian-less minor act on a school venture" do
      _school, venture = school_tree

      expect(teen.needs_guardian?).to be true
      expect(EventPolicy.new(teen, venture).send(:permitted_to_operate_business?)).to be true
    end

    it "does not let school vouching leak to a student's personal venture" do
      # The filter exemption (User#institutionally_vouched_for?) must not loosen
      # per-record enforcement: a school vouches for a student inside its
      # programme, not for a side business their family never agreed to.
      _school, venture = school_tree
      OrganizerPositionInvite.create!(event: venture, user: teen, sender: teen, role: :member)

      teen.reload
      expect(teen.institutionally_vouched_for?).to be true
      personal = create(:event)
      expect(EventPolicy.new(teen, personal).send(:permitted_to_operate_business?)).to be false
    end

    it "still refuses a guardian-less minor on their own personal venture" do
      # Scoped to the record, not the user: the school vouches for the student
      # inside its programme and nowhere else.
      expect(EventPolicy.new(teen, create(:event)).send(:permitted_to_operate_business?)).to be false
    end
  end
end
