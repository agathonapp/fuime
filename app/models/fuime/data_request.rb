# frozen_string_literal: true

module Fuime
  # Fuime: a parent's COPPA request over their child's account — review it, or
  # have it deleted.
  #
  # Two kinds, two shapes:
  #
  #   export   — served immediately, in the request that asked for it. The row is
  #              the receipt, written after the file is handed over.
  #   deletion — a REQUEST, not a switch. It goes to a queue, a person reads it,
  #              and Fuime::DataErasureService carries it out. Deleting a selling
  #              business's account is not reversible and touches money records
  #              Fuime is required to keep, so no web button performs it.
  #
  # ── Why deletion is not instant, written down so nobody "fixes" it ──────────
  #
  # COPPA requires honouring a parental deletion request, not honouring it in
  # the same HTTP request. What it cannot mean is destroying the transaction
  # record of sales a real customer paid for: Fuime is merchant of record, those
  # are Fuime's own books, and tax and dispute obligations outlive the account.
  # So erasure severs the person from the records rather than destroying the
  # records — see Fuime::DataErasureService for exactly what goes and what stays,
  # and say so to the parent rather than promising more than is delivered.
  class DataRequest < ApplicationRecord
    self.table_name = "fuime_data_requests"

    belongs_to :requested_by, class_name: "User"
    belongs_to :subject, class_name: "User"
    belongs_to :fulfilled_by, class_name: "User", optional: true

    enum :kind, { export: 0, deletion: 1 }, prefix: :kind
    # `refused` is a real outcome and is not a failure: a request from somebody
    # whose guardianship was revoked, or over an account with an open dispute,
    # is answered and recorded rather than quietly dropped.
    enum :status, { open: 0, fulfilled: 1, refused: 2 }, prefix: :status

    validates :requested_at, presence: true

    scope :needs_action, -> { status_open.kind_deletion }
    scope :recent_first, -> { order(requested_at: :desc) }

    def fulfil!(by:, notes: nil)
      update!(status: :fulfilled, fulfilled_at: Time.current, fulfilled_by: by, resolution_notes: notes)
    end

    def refuse!(by:, notes:)
      update!(status: :refused, fulfilled_at: Time.current, fulfilled_by: by, resolution_notes: notes)
    end

    # What Fuime told the parent it would do. Stated once, here, so the guardian
    # page, the confirmation mail and the admin queue cannot drift apart on the
    # only number in this feature that is a promise.
    RESPONSE_WINDOW_DAYS = 30

    def due_at
      requested_at + RESPONSE_WINDOW_DAYS.days
    end

    def overdue?
      status_open? && kind_deletion? && due_at.past?
    end

  end
end
