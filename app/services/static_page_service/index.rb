# frozen_string_literal: true

module StaticPageService
  class Index
    def initialize(current_user:)
      @current_user = current_user
    end

    def redirect_to_first_event?
      !auditor? && events.count == 1 && invites.none?
    end

    def events
      @current_user.events.reorder("organizer_positions.sort_index ASC", "events.id ASC").includes(:stripe_cards, organizer_positions: :user)
    end

    # Fuime: the ventures this user oversees as a guardian.
    #
    # Separate from #events, and deliberately not merged into it. #events reads
    # through organizer_positions, and a guardian has NO position by design —
    # see Guardianship.overseeing_event: a position is org membership that a
    # manager (the minor) can delete, which would make the one guarantee the
    # guardian is asked to rely on revocable by exactly the person it exists to
    # be independent of.
    #
    # The consequence nobody noticed: a parent signed the agreement and their
    # home page said "Your businesses" and listed nothing. The venture existed,
    # they were entitled to see it, and the only route to it was the
    # guardianships page they had no reason to look for.
    #
    # Kept as its own list rather than folded into "Your businesses" because it
    # is not their business — they oversee it. The distinction is the legal
    # framing of the whole product (L2) and the page should not blur it.
    def overseen_events
      @current_user.overseen_events.includes(organizer_positions: :user)
    end

    def organizer_positions
      @current_user.organizer_positions.includes(:event).order(sort_index: :asc, event_id: :asc)
    end

    def invites
      @current_user.organizer_position_invites.pending
    end

    def invite_requests
      @current_user.organizer_position_invite_requests.pending
    end

    def applications
      @current_user.applications.active
    end

    # Counts

    def checks_count
      Check.in_transit.count
    end

    def ach_transfers_count
      AchTransfer.pending.count
    end

    def fee_reimbursements_count
      FeeReimbursement.unprocessed.count
    end

    def g_suites_needs_ops_review_count
      GSuite.needs_ops_review.count
    end

    def organizer_position_deletion_requests_count
      OrganizerPositionDeletionRequest.under_review.count
    end

    def transactions_count
      Transaction.needs_action.count
    end

    def disbursements_count
      Disbursement.pending.count
    end

    private

    def auditor?
      @current_user.auditor?
    end

  end
end
