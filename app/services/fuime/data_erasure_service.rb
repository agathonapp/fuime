# frozen_string_literal: true

module Fuime
  # Fuime: carry out a parent's deletion request (COPPA 16 CFR 312.6(a)(2)).
  #
  # ── What "delete" can honestly mean here ────────────────────────────────────
  #
  # Not "destroy every row". Fuime is the **merchant of record**: when a
  # teenager's customer paid, they paid Fuime, and the record of that sale is
  # Fuime's own accounting record — required for tax, for a chargeback that can
  # arrive up to 120 days later, and for the payable Fuime still owes. Deleting
  # it would not be privacy compliance; it would be destroying the books.
  #
  # So erasure **severs the person from the records**: every identifier that
  # points at a human being is overwritten, the account is locked, and what
  # remains is an anonymous counterparty on a transaction. That is the standard
  # remedy and it is what the guardian page and the confirmation mail promise —
  # in those words, because a parent told "everything is deleted" who later
  # learns a sales ledger still exists has been misled.
  #
  # ── Not reachable from a browser ────────────────────────────────────────────
  #
  # Called by `rake fuime:data_request:fulfil[id]` after a person has read the
  # request, checked there is no open dispute or unpaid payable, and decided.
  # Irreversible work behind an admin button is one misclick from an incident,
  # and this one cannot be undone by restoring a backup without also restoring
  # everybody else's data to that point.
  class DataErasureService
    class Refused < StandardError; end

    # Overwritten rather than nulled where a column is NOT NULL or unique.
    # Deterministic on the id so two erasures cannot collide on the email index.
    def self.placeholder_email(user) = "erased-#{user.id}@deleted.fuime.invalid"

    def initialize(request:, performed_by:)
      @request = request
      @performed_by = performed_by
      @user = request.subject
    end

    # Answers "may this be carried out", separately from carrying it out, so the
    # queue page and the rake task can both ask without doing anything.
    #
    # Money is the only thing that blocks it, and it blocks it TEMPORARILY: an
    # open dispute is a live claim against a sale this account made, and an
    # unpaid payable is money Fuime owes a family it is about to lose the ability
    # to identify. Both resolve in weeks. COPPA's requirement is to honour the
    # request, not to honour it before Fuime has paid what it owes — but the
    # parent has to be told which it is, which is why this returns sentences.
    def blockers
      list = []

      open_disputes = ::Fuime::Dispute.open_cases.where(event_id: event_ids).count
      if open_disputes.positive?
        list << "#{open_disputes} open dispute(s) against sales made by this account. " \
                "Fuime must answer them before the record can be anonymised."
      end

      unpaid = ::PayoutRequest.where(event_id: event_ids).where.not(aasm_state: %w[fulfilled rejected]).count
      if unpaid.positive?
        list << "#{unpaid} payout request(s) not yet settled. Pay or cancel them first — " \
                "afterwards Fuime cannot tell whose money it was."
      end

      list
    end

    def perform!
      raise Refused, blockers.join(" ") if blockers.any?

      ActiveRecord::Base.transaction do
        erase_identity!
        detach_files!
        end_every_session!
        @request.fulfil!(by: @performed_by, notes: fulfilment_note)
      end

      Rails.logger.info("[Fuime] data request #{@request.id}: erased identity of user #{@user.id}")
      @request
    end

    private

    def event_ids
      @event_ids ||= @user.organizer_positions.pluck(:event_id)
    end

    def erase_identity!
      @user.update_columns(
        email: self.class.placeholder_email(@user),
        full_name: "Erased account",
        preferred_name: nil,
        phone_number: nil,
        phone_number_verified: false,
        birthday_ciphertext: nil,
        age_attestation_ip: nil,
        age_attestation_user_agent: nil,
        discord_id: nil,
        webauthn_id: nil,
        slug: "erased-#{@user.id}",
        locked_at: Time.current,
        updated_at: Time.current
      )
    end

    # `update_columns` above skips callbacks and validations on purpose: several
    # of those columns are validated for presence or format, and an erasure that
    # a validation can veto is not an erasure. The attachment has to go through
    # its own API.
    def detach_files!
      @user.profile_picture.purge if @user.profile_picture.attached?
    rescue => e
      Rails.error.report(e, handled: true, context: { fuime_data_request_id: @request.id })
    end

    # Anything that could sign this account back in, or that carries an address
    # and a device. Sessions and login codes are the two places a deleted email
    # survives in plain text.
    def end_every_session!
      @user.user_sessions.destroy_all
      @user.login_codes.delete_all
      @user.logins.delete_all
    end

    def fulfilment_note
      "Identity erased by Fuime::DataErasureService. Kept, with the person severed: " \
      "transaction records for #{event_ids.size} business(es), which are Fuime's own " \
      "accounting records as merchant of record, and the record of this request."
    end

  end
end
