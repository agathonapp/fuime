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
    # Inherits FeeWaived — 0% — rather than Standard's 4%, and that is a
    # commercial decision rather than a technical one.
    #
    # A school is billed per student per year for the software. Taking a
    # percentage of each student's revenue on top would charge the same customer
    # twice for the same product, and it would be a genuinely awkward line to
    # defend to a head of school who has already signed a per-seat agreement.
    # FeeWaived keeps every Standard capability and only removes the fee.
    #
    # If a school programme is ever sold on a revenue share instead, that is a
    # different plan, not a change here.
    #
    # What this plan changes otherwise is only WHO the responsible adult is. It
    # does not loosen a single spending control: the category allowlist, the
    # freeze, the receipt requirement and the policy inheritance in
    # CardGrant::InheritablePolicy all behave identically.
    class School < FeeWaived
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

      # Schools pay a per-student subscription negotiated in the pilot
      # agreement and billed by invoice — not by a card-on-file Stripe
      # subscription, which no school business office would put through
      # procurement. Zero here means "not billed through
      # Fuime::SubscriptionService", not "free".
      def monthly_fee_cents
        0
      end
    end
  end
end
