# frozen_string_literal: true

class Event
  class Plan
    # Fuime: a venture run inside a school programme, where the school is the
    # responsible adult rather than a parent.
    #
    # This is the shape Alpha School's Founders School needs: every high schooler
    # runs a venture, the school holds the money and the Stripe account, and a
    # guide oversees spending. There is no per-student guardian anywhere in the
    # picture — the school is in loco parentis and families signed enrolment
    # contracts long before Fuime existed.
    #
    # Inherits from Standard rather than FeeWaived because a school is a paying
    # customer: the pricing is per-student software, billed to the institution,
    # not a percentage skimmed off a teenager's revenue. Whether the platform fee
    # should be zero for these is a commercial decision — set it deliberately here
    # once it is made, rather than inheriting a fee ladder built for fiscal
    # sponsorship.
    #
    # What this plan changes is only WHO the responsible adult is. It does not
    # loosen a single spending control: the category allowlist, the freeze, the
    # receipt requirement and the policy inheritance in
    # CardGrant::InheritablePolicy all behave identically.
    class School < Standard
      def self.selectable?
        true
      end

      def label
        "school"
      end

      def description
        "For ventures run inside a school programme. The school owns the account and the money; " \
          "guides oversee student spending. No parent guardian is required — the school is the " \
          "responsible party."
      end

      def institutionally_sponsored?
        true
      end
    end
  end
end
