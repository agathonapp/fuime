# frozen_string_literal: true

# Fuime: how far one founder has got, and what is stopping them.
#
# ── Why this is an object and not conditionals in the roster view ──────────
#
# It is the thing somebody reads fifty times in a row while an event is running,
# under time pressure, to decide who to walk over to. Two properties matter and
# neither survives being written inline: it must name ONE next action rather than
# a state, and the order it checks things in has to be the order a person would
# fix them. Both are decisions worth testing.
#
# ── It reports; it never decides ──────────────────────────────────────────
#
# Every answer here is read from the objects that actually own it —
# `Event#accepts_payments?`, `Event#selling_blockers`, `User#has_active_guardian?`.
# Nothing is re-derived, because a roster that computed eligibility its own way
# would eventually disagree with the gate that really decides, and the failure
# would be an organiser confidently telling a teenager they can sell when they
# cannot.
module Fuime
  class FounderProgress
    # In funnel order. The first one NOT satisfied is where the founder is.
    STAGES = %i[applied venture_created vetted can_sell listed sold].freeze

    # A decision that has been made must read as a decision, not as a wait.
    # Both of these used to render as "We'll do a quick review before you go
    # live", because `vetted?` only asks whether the status is `approved` and
    # every other state fell through the same branch. A founder whose venture was
    # refused, or frozen after approval, was told to wait for something that had
    # already happened — so they waited, and nobody was coming.
    #
    # Neither names a reason: `operator_vetting_notes` is written for admins and
    # can say things that should not be quoted at a teenager without a human
    # reading it first. The right move is to get them to a person.
    REJECTED_MESSAGE = "We reviewed this venture and can't approve it for selling. " \
                       "Email #{ApplicationMailer::OPERATIONS_EMAIL} and we'll explain."
    SUSPENDED_MESSAGE = "Selling is paused on this venture. " \
                        "Email #{ApplicationMailer::OPERATIONS_EMAIL} and we'll sort it out."

    def initialize(application:)
      @application = application
      @event = application.event
    end

    attr_reader :application, :event

    def founder = application.user

    # Where they are now — the last stage they have reached.
    def stage
      @stage ||= if sold? then :sold
                 elsif listed? then :listed
                 elsif can_sell? then :can_sell
                 elsif vetted? then :vetted
                 elsif venture_created? then :venture_created
                 else
                   :applied
                 end
    end

    def done? = stage == :sold

    # The single sentence an organiser acts on.
    #
    # One thing, not a list, and phrased as something a person can do. A roster
    # cell that reads "not eligible" sends somebody to ask a question; one that
    # reads "needs a parent — invite not accepted yet" sends them to the right
    # teenager with the right sentence already in their mouth.
    #
    # Ordered by what blocks what: no venture is upstream of everything, and
    # there is no point telling somebody to publish an offer when their venture
    # cannot sell.
    #
    # This copy is organiser-facing ("Approve them to sell"). Founders see
    # `#founder_next_action` — same funnel, different person.
    def next_action
      return "Nothing — they've made a sale." if sold?
      return "Set up the business (automatic admission didn't run)." if event.nil?
      return "Approve them to sell — vetting is #{event.operator_vetting_status}." unless vetted?

      if event.demo_mode?
        return "Publish something to sell — nothing is listed yet." unless listed?

        return "Share the pay link — Playground Mode, no real charges."
      end

      blockers = event.selling_blockers
      return blockers.first if blockers.any?

      return "Publish something to sell — nothing is listed yet." unless listed?

      "Make a first sale."
    end

    # Same funnel, said to the founder. Never tells them to approve themselves.
    # Draft first — review is the publish gate, not a waiting room.
    def founder_next_action
      return "You've made a sale." if sold?

      if event.nil?
        blockers = application.activation_blockers
        return blockers.first if blockers.any?

        return "Finish setting up your venture."
      end

      return "Add something to sell." unless has_offer?

      # Four vetting states, not two. `vetted?` is `operator_vetting_approved?`,
      # so rejected and suspended both fell through to "We'll do a quick review
      # before you go live" — telling a founder to wait for a review that has
      # already happened and gone against them. They then wait, and nobody is
      # coming. A decision that has been made has to read as a decision.
      return REJECTED_MESSAGE if event.operator_vetting_rejected?
      return SUSPENDED_MESSAGE if event.operator_vetting_suspended?
      return "We'll do a quick review before you go live." unless vetted?

      if event.demo_mode?
        return "Publish something so people can buy it." unless listed?

        return "Share your pay link — Playground Mode, no real charges."
      end

      blockers = event.selling_blockers
      return blockers.first if blockers.any?

      return "Publish something so people can buy it." unless listed?

      "Share your pay link and make a first sale."
    end

    # :ok / :needed / :pending / :failed — never merged into the sell funnel.
    #
    # Under merchant-of-record a missing parent does not block selling. A
    # bounced invite used to disappear into a log line; `:failed` is how the
    # founder sees it.
    def guardian_status
      return :ok unless guardian_pending?
      return :pending if pending_guardian_invite?
      return :failed if guardian_invite_failed?

      :needed
    end

    def pending_guardian_invite?
      founder.guardianships_as_minor.pending.exists?
    end

    def guardian_invite_failed?
      return true if application.guardian_invite_error.present?
      return false unless application.submitted? || application.under_review? || application.approved?

      application.cosigner_email.present? && !pending_guardian_invite? && guardian_pending?
    end

    def guardian_status_sentence
      case guardian_status
      when :ok then nil
      when :pending then "Waiting on #{application.cosigner_email.presence || "your parent"} to accept the invite."
      when :failed
        reason = application.guardian_invite_error
        if reason.present?
          "We couldn't invite your parent: #{reason}"
        else
          "The parent invite didn't go through. Invite them again from your account."
        end
      when :needed then "Invite a parent or guardian — they approve payouts, not selling."
      end
    end

    # Separate from the funnel, deliberately, because it does not block selling.
    #
    # Under merchant-of-record a founder sells without a parent and cannot be PAID
    # without one (Fuime::PayableAssessment). So this is not a blocker on the day —
    # it is the thing to chase before anybody expects money, and a roster that
    # merged it into the funnel would have organisers chasing parents instead of
    # first sales.
    def guardian_pending?
      founder.minor_or_unknown_age? && !founder.has_active_guardian? &&
        !founder.institutionally_vouched_for?
    end

    def venture_created? = event.present?
    def vetted?          = event.present? && event.operator_vetting_approved?
    def can_sell?        = event.present? && event.accepts_payments?

    def has_offer?
      return false if event.nil?

      event.fuime_offers.live.exists?
    end

    def listed?
      return false if event.nil?

      event.fuime_offers.published.exists?
    end

    # A sale, meaning money actually arrived — read from the ledger rather than
    # from Stripe, because the ledger is what the founder sees and what everything
    # downstream is computed from.
    def sold?
      return false if event.nil?

      @sold ||= event.canonical_transactions.where("amount_cents > 0").exists?
    end

  end
end
