# frozen_string_literal: true

# Fuime: build a school programme the way the product actually shapes one.
#
# The tree is School (owns the plan and, once onboarded, the Stripe account) ->
# cohort -> student venture. Three levels rather than two on purpose: the resolution
# in Event#payment_account and Event#billing_plan both walk to the NEAREST matching
# ancestor, and a two-level fixture cannot tell "walks up" apart from "reads its
# parent".
#
# Student ventures are built on `Event::Plan::Standard` explicitly, because that is
# what `EventService::Create` gives a real sub org and it is the plan whose 4% fee the
# school inheritance has to override. The event factory's own default is FeeWaived,
# which would make the fee assertions pass for the wrong reason.
module SchoolTree
  # Returns [school, cohort, venture]. No Stripe account anywhere — callers attach
  # one to the level they are testing.
  def build_school_tree(school_name: "Alpha School Founders")
    school = create(:event, name: school_name, plan_type: Event::Plan::School)
    cohort = create(:event, name: "#{school_name} — Class of 2027",
                            parent: school, plan_type: Event::Plan::Standard)
    venture = create(:event, name: "#{school_name} — Angus's Mowing",
                             parent: cohort, plan_type: Event::Plan::Standard)

    [school, cohort, venture]
  end

  # A guide or business-office user holding manager on the school ITSELF. This is the
  # shape that matters: nobody gives a guide a position on each of several hundred
  # student sub orgs, so every predicate has to resolve their authority through the
  # tree rather than by direct membership.
  def create_school_manager(school, birthday: 40.years.ago.to_date)
    user = create(:user, birthday:)
    create(:organizer_position, event: school, user:, role: :manager)
    user
  end

  # The student, holding member on their own venture and nothing else.
  def create_student(venture, birthday: 15.years.ago.to_date)
    user = create(:user, birthday:)
    create(:organizer_position, event: venture, user:, role: :member)
    user
  end
end

RSpec.configure do |config|
  config.include SchoolTree
end
