# frozen_string_literal: true

module Fuime
  # Fuime: everything Fuime holds about one person, as a file their parent can
  # read (COPPA 16 CFR 312.6(a)(1); CLAUDE.md L4).
  #
  # ── The rule that shapes every line below ───────────────────────────────────
  #
  # A parent has a right to their CHILD's data. They have no right to anybody
  # else's, and a teen's account is entangled with other people's: the customers
  # who bought from them, the co-founder on the same venture, the guardian of
  # that co-founder. So the export is built by asking "is this a fact about the
  # subject?" rather than "can I reach it from the subject?" — which is why
  # sales carry an amount, a date, a product and a REGION, and never a buyer's
  # name, email or address.
  #
  # Two other deliberate absences:
  #
  #   * **No ID images, ever.** L4 — Fuime never stored one, keeping only the
  #     consent record. There is nothing here to export and that is the point.
  #   * **No receipt file contents.** Filenames and dates, not blobs. A receipt
  #     photo routinely contains a third party's card details, and a JSON export
  #     is the wrong place to hand them back.
  #
  # Money figures are copied from the ledger rather than recomputed. This is a
  # disclosure document, not a second opinion about what somebody is owed.
  class DataExportService
    def initialize(user:)
      @user = user
    end

    def as_json
      {
        exported_at: Time.current.iso8601,
        about: account,
        age_and_consent: age_and_consent,
        guardianships: guardianships,
        businesses: businesses,
        data_requests: data_requests,
        what_is_not_here: omissions
      }
    end

    def filename
      "fuime-data-#{@user.id}-#{Date.current.iso8601}.json"
    end

    private

    def account
      {
        id: @user.public_id,
        name: @user.name,
        preferred_name: @user.preferred_name,
        email: @user.email,
        phone_number: @user.phone_number,
        # Encrypted at rest (Lockbox). Exported because it is the subject's own
        # date of birth and they are entitled to see what we recorded.
        date_of_birth: safe { @user.birthday&.to_date&.iso8601 },
        account_created_at: @user.created_at.iso8601,
        account_locked_at: @user.locked_at&.iso8601
      }
    end

    def age_and_consent
      {
        age_attestation: @user.age_attestation,
        attested_at: @user.age_attested_at&.iso8601,
        # Recorded at attestation as evidence of who clicked. Theirs, so it goes.
        attested_from_ip: @user.age_attestation_ip,
        attested_user_agent: @user.age_attestation_user_agent
      }
    end

    # Both directions. A 16-year-old with a parent, and a parent with wards, are
    # the same table read two ways, and each row is a fact about this person.
    # The OTHER party is named, because a guardianship is a relationship and a
    # record of it that hides who it was with says nothing at all.
    def guardianships
      as_minor = @user.guardianships_as_minor.map { |g| guardianship_row(g, counterparty: g.guardian, role: "my parent or guardian") }
      as_guardian = @user.guardianships_as_guardian.map { |g| guardianship_row(g, counterparty: g.minor, role: "my ward") }
      as_minor + as_guardian
    end

    def guardianship_row(guardianship, counterparty:, role:)
      {
        role:,
        other_person: counterparty&.name,
        status: guardianship.status,
        invited_at: guardianship.invite_sent_at&.iso8601,
        agreement_signed_at: guardianship.agreement_signed_at&.iso8601,
        agreement_version: guardianship.agreement_version,
        # The consent record L4 says to keep instead of an ID image.
        signed_from_ip: guardianship.agreement_ip,
        signed_user_agent: guardianship.agreement_user_agent,
        revoked_at: guardianship.revoked_at&.iso8601
      }
    end

    def businesses
      @user.organizer_positions.includes(:event).map do |position|
        event = position.event
        next if event.nil?

        {
          name: event.name,
          my_role: position.role,
          joined_at: position.created_at.iso8601,
          category: event.business_category,
          created_at: event.created_at.iso8601,
          what_it_sells: offers_for(event),
          sales: sales_for(event),
          payout_requests: payouts_for(event),
          receipts_uploaded: receipts_for(event)
        }
      end.compact
    end

    def offers_for(event)
      event.fuime_offers.map do |offer|
        { name: offer.name, price_cents: offer.price_cents, published: offer.published?, created_at: offer.created_at.iso8601 }
      end
    end

    # Deliberately not the buyer. `Fuime::Sale` carries country / state / postal
    # code because economic nexus is measured on where buyers were
    # (MOR_RISK_ACCEPTANCE §7) — state and country are coarse enough to describe
    # the sale, and postal code is close enough to a household that it stays out.
    def sales_for(event)
      ::Fuime::Sale.where(event_id: event.id).order(occurred_at: :desc).map do |sale|
        {
          date: sale.occurred_at.iso8601,
          amount_cents: sale.amount_cents,
          product: sale.offer&.name,
          buyer_region: [sale.state, sale.country].compact.join(", ").presence
        }
      end
    end

    def payouts_for(event)
      event.payout_requests.order(created_at: :desc).map do |request|
        { requested_at: request.created_at.iso8601, amount_cents: request.amount_cents, state: request.aasm_state }
      end
    end

    # Metadata only — see the class note on why the files themselves are not
    # here. The parent can still open any of them in the product.
    def receipts_for(event)
      ::Receipt.where(user_id: @user.id).map do |receipt|
        { uploaded_at: receipt.created_at.iso8601, filename: safe { receipt.file&.filename&.to_s } }
      end
    end

    def data_requests
      ::Fuime::DataRequest.where(subject_id: @user.id).recent_first.map do |request|
        { kind: request.kind, status: request.status, requested_at: request.requested_at.iso8601, fulfilled_at: request.fulfilled_at&.iso8601 }
      end
    end

    # Said out loud rather than left as an absence. A parent reading an export
    # that is silent about what it left out cannot tell a gap from a lie.
    def omissions
      [
        "Personal details of customers who bought from these businesses. They are other people, and their data is not the subject's to receive.",
        "Receipt and document files themselves — only that they exist, and when. They often contain a third party's payment details.",
        "Identity documents. Fuime never stores them: an image sent for verification is passed to the verifier and deleted, and only the consent record is kept.",
        "Fuime's own accounting records of sales made through the platform, which Fuime is required to keep as the merchant of record."
      ]
    end

    # Encrypted and optional columns raise rather than return nil when a key is
    # missing or an attachment has gone. An export that 500s tells the parent
    # nothing; an export with one blank field tells them almost everything.
    def safe
      yield
    rescue => e
      Rails.logger.warn("[Fuime] data export: #{e.class} reading a field for user #{@user.id}")
      nil
    end

  end
end
