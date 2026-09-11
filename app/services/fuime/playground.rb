# frozen_string_literal: true

# Fuime: Playground Mode on the same production app.
#
# Per-venture `Event#demo_mode` (upstream HCB Playground). Does NOT use
# Fuime::DemoSandbox and does NOT talk to Stripe — so it is safe while
# STRIPE_MODE=live. Discover already excludes demo_mode. Checkout mocks.
#
#   rake fuime:playground          seed / refresh the pitch venture
#   open /admin/playground         Become a persona + click the product path
#
# ── The cast ────────────────────────────────────────────────────────────────
#
# Three people, in the order a pitch tells the story:
#
#   Sam    a brand-new founder with nothing yet — Become Sam lands on the very
#          first onboarding screen, so a room can watch a teenager sign up.
#   Maya   a 16-year-old running a lawn business that is already vetted,
#          listing, and being paid — the "this is what it looks like when it
#          works" view.
#   Denise Maya's parent — the guardian who signed and can see everything.
#
# Sam is reset on every seed (name, age, ventures, applications, guardian
# invites), so the signup can be shown again and again. Maya's ledger is
# wiped and rewritten on every seed so the dates stay recent.
#
# ── Money ───────────────────────────────────────────────────────────────────
#
# The ledger is money-in from lawn jobs only. Family MoR has no operator
# spend rail (Issuing off, reimbursements hidden), so invented card-like
# expenses are a lie in a pitch. The pending take-rate line is FeeEngine
# accruing Event::Plan::Free (7% of collections) — the same pending row
# the founder saw labeled "Fiscal sponsorship". Do not add a second fee
# line here; relabel that row (see BankFee / pending fee copy).
#
# A storefront Buy clicked by whoever is driving the demo (an admin, usually
# impersonating Maya) is recorded as one more income line through exactly the
# same CSV → hashed → canonical → mapping path, so "and now it's on her
# ledger" is true on stage. A stranger who finds the public storefront gets
# the mock thank-you screen and writes nothing (Fuime::CheckoutsController).
module Fuime
  class Playground
    SLUG = "fuime-playground"
    TEEN_EMAIL = "playground+maya@fuime.test"
    GUARDIAN_EMAIL = "playground+parent@fuime.test"
    NEW_FOUNDER_EMAIL = "playground+new@fuime.test"
    BANK_IDENTIFIER = "FUIMEPLAYGROUND"

    # How long Maya has "been on Fuime". Backdated once, on first seed, so the
    # storefront's "On Fuime since" and the home page's Insights timeframe menu
    # (which needs a venture older than a week) read like an established
    # business rather than one created during the meeting.
    VENTURE_AGE = 10.weeks

    SAMPLE_OFFERS = [
      {
        name: "Front and back lawn mow",
        description: "I bring my own mower. Gates and pets okay.",
        unit_label: "per visit",
        price_cents: 35_00,
        publish: true
      },
      {
        name: "Weekend hedge trim",
        description: "Up to an hour. Bags of clippings left at the curb.",
        unit_label: "per visit",
        price_cents: 45_00,
        publish: false
      }
    ].freeze

    # Income only. FeeEngine::Create runs on each CanonicalEventMapping and
    # accrues event.revenue_fee (Free = 7%) into fronted_fee_balance — that is
    # the pending "Fuime service fee" on the transactions list. A negative
    # LEDGER_LINE would invent spend Maya cannot make, or a second fee.
    #
    # Spread over nine weeks so the balance chart has a shape and the
    # "Past month" / "All time" timeframes differ.
    LEDGER_LINES = [
      { days_ago: 62, memo: "Lawn — Grand Lake block", cents: 10_500 },
      { days_ago: 55, memo: "Ridge Coffee — weekly mow", cents: 14_000 },
      { days_ago: 47, memo: "Weekly lawn subscriptions", cents: 12_250 },
      { days_ago: 38, memo: "Birthday party yard (front + back)", cents: 9_600 },
      { days_ago: 24, memo: "Lawn — Grand Lake block", cents: 18_600 },
      { days_ago: 17, memo: "Ridge Coffee — weekly mow", cents: 21_000 },
      { days_ago: 10, memo: "Weekly lawn subscriptions", cents: 14_250 },
      { days_ago: 4, memo: "Hedge trim — Piedmont Ave", cents: 9_000 },
    ].freeze

    PUBLIC_MESSAGE = <<~MD.strip
      Weekend lawns, hedges and leaf clean-up in Oakland. I bring my own gear,
      text before I arrive, and leave the clippings bagged at the curb.
    MD

    def self.slug = SLUG

    def self.service_fee_cents
      LEDGER_LINES.sum do |line|
        BigDecimal(line[:cents]) * BigDecimal(Event::Plan::Free::REVENUE_FEE.to_s)
      end
    end

    def self.pitch_venture
      Event.find_by(slug: SLUG)
    end

    def initialize
      @warnings = []
    end

    def seed!
      without_mail do
        guardian = upsert_user!(email: GUARDIAN_EMAIL, name: "Denise Okafor", birthday: 43.years.ago.to_date)
        teen = upsert_user!(email: TEEN_EMAIL, name: "Maya Okafor", birthday: 16.years.ago.to_date)
        ensure_guardianship!(guardian:, teen:)
        event = upsert_venture!(teen:)
        ensure_free_plan!(event)
        upsert_position!(user: teen, event:, role: :manager, welcome: true)
        upsert_position!(user: guardian, event:, role: :reader, welcome: false)
        seed_offers!(event)
        wipe_mock_ledger!(event)
        fund!(event)
        new_founder = reset_new_founder!
        event.reload

        { event:, teen:, guardian:, new_founder:, warnings: @warnings }
      end
    end

    # Put Sam back to "has never used Fuime": no name, no age answer, no
    # application, no venture, no guardian invite. Everything a signup demo
    # created is removed so the next demo starts on the first screen.
    #
    # Ventures are soft-deleted (Event acts_as_paranoid), which is what every
    # other deletion path on an Event does; nothing here reaches into the
    # ledger engine (Rule 3) — a fresh founder's venture has no ledger.
    def reset_new_founder!
      without_mail do
        user = User.find_or_initialize_by(email: NEW_FOUNDER_EMAIL)
        user.verified = true
        save_unvalidated!(user)

        user.events.where.not(slug: SLUG).find_each do |event|
          event.destroy
        rescue => e
          @warnings << "Could not remove #{event.slug}: #{e.message}"
        end

        OrganizerPosition.where(user_id: user.id).find_each(&:destroy)
        OrganizerPositionInvite.where(user_id: user.id).find_each(&:destroy)
        Guardianship.where(minor_id: user.id).delete_all
        Event::Application.where(user_id: user.id).find_each do |application|
          application.destroy
        rescue => e
          @warnings << "Could not remove application #{application.id}: #{e.message}"
        end

        # Straight to the columns: `full_name` is validated present once it has
        # ever been set, and `age_attestation` is write-once by validation —
        # both correct for real users, both in the way of a reset.
        user.update_columns(
          full_name: nil,
          preferred_name: nil,
          birthday: nil,
          age_attestation: nil,
          age_attested_at: nil,
          age_attestation_ip: nil,
          age_attestation_user_agent: nil,
          updated_at: Time.current
        )
        user.reload
      end
    end

    # One more income line on the pitch venture, through the same path the
    # seed uses. Returns the CanonicalTransaction, or nil (with a warning)
    # when the venture is not the pitch venture or the import failed.
    def record_mock_sale!(event:, memo:, amount_cents:)
      return nil unless event&.demo_mode? && event.slug == SLUG
      return nil unless amount_cents.to_i.positive?

      clean_memo = ::Fuime::VentureLedger.sanitize_memo_text(memo).gsub(/[[:cntrl:]]/, "").strip.truncate(80)
      before = event.canonical_event_mappings.count
      fund!(event, [{ days_ago: 0, memo: clean_memo, cents: amount_cents.to_i }])
      return nil unless event.canonical_event_mappings.count > before

      event.canonical_transactions.order(:id).last
    end

    def status
      event = self.class.pitch_venture
      teen = User.find_by(email: TEEN_EMAIL)
      new_founder = User.find_by(email: NEW_FOUNDER_EMAIL)
      {
        slug: SLUG,
        event:,
        teen:,
        guardian: User.find_by(email: GUARDIAN_EMAIL),
        new_founder:,
        new_founder_fresh: new_founder.present? && new_founder.full_name.blank? && new_founder.events.none?,
        offers: event&.fuime_offers&.live&.in_operator_order || [],
        published_offer: event&.fuime_offers&.published&.in_operator_order&.first,
        published: event&.fuime_offers&.published&.count || 0,
        ledger_lines: event ? event.canonical_transactions.count : 0,
        last_seeded_at: event&.updated_at,
        stripe_live: StripeService.live?,
        warnings: @warnings
      }
    end

    def banner
      event = self.class.pitch_venture
      return "No playground venture yet. Run rake fuime:playground." unless event

      <<~BANNER
        Pitch playground  /#{event.slug}  (demo_mode=#{event.demo_mode})
          Open /admin/playground and Become a persona (existing impersonate):
            Sam    #{NEW_FOUNDER_EMAIL}  — brand-new founder, lands on signup step 1
            Maya   #{TEEN_EMAIL}  — running the business: Home → What you sell → storefront Buy
            Denise #{GUARDIAN_EMAIL}  — the parent: /guardian
          Storefront /b/#{event.slug} is public; Buy never hits Stripe. Discover excludes this venture.
      BANNER
    end

    private

    def without_mail
      was_mail = ActionMailer::Base.perform_deliveries
      was_queue = ActiveJob::Base.queue_adapter
      ActionMailer::Base.perform_deliveries = false
      ActiveJob::Base.queue_adapter = :test
      yield
    ensure
      ActionMailer::Base.perform_deliveries = was_mail
      ActiveJob::Base.queue_adapter = was_queue
    end

    def save_unvalidated!(record)
      record.save!(validate: false)
    end

    def upsert_user!(email:, name:, birthday:)
      user = User.find_or_initialize_by(email:)
      user.assign_attributes(full_name: name, birthday:, verified: true)
      save_unvalidated!(user)
      user
    end

    def ensure_guardianship!(guardian:, teen:)
      row = Guardianship.find_or_initialize_by(guardian_id: guardian.id, minor_id: teen.id)
      row.status = :active
      row.agreement_signed_at ||= 3.weeks.ago
      row.agreement_version ||= Guardianship::CURRENT_AGREEMENT_VERSION
      row.invite_token ||= SecureRandom.hex(16)
      row.invite_sent_at ||= 4.weeks.ago
      save_unvalidated!(row)
      row
    end

    def upsert_venture!(teen:)
      event = Event.find_or_initialize_by(slug: SLUG)
      if event.new_record?
        event.created_at = VENTURE_AGE.ago
        # `save!(validate: false)` skips the before_validation hook that builds a
        # plan, and the after_create ledger setup reads `revenue_fee` off one.
        # Free is the pitch take-rate (7%); `ensure_free_plan!` handles rows that
        # already existed with another plan.
        event.build_plan(type: "Event::Plan::Free")
      end
      event.assign_attributes(
        name: "Maya's Lawn Care (Playground)",
        demo_mode: true,
        aasm_state: "approved",
        point_of_contact_id: teen.id,
        is_public: true,
        is_indexable: true,
        business_category: "services",
        storefront_tagline: "Weekend lawns in Oakland. Playground — no real charges.",
        public_message: event.public_message.presence || PUBLIC_MESSAGE,
        operator_vetting_status: :approved,
        operator_vetted_at: event.operator_vetted_at || 1.week.ago,
        sale_terms_acknowledged_at: event.sale_terms_acknowledged_at || Time.current,
        sale_terms_acknowledged_by_id: event.sale_terms_acknowledged_by_id || teen.id,
        sale_terms_version: Event::SALE_TERMS_VERSION,
        country: event.country.presence || "US"
      )
      save_unvalidated!(event)
      event
    end

    # Pitch take-rate is Free/Pro 7%, not Standard's leftover 5%. Prod already
    # had a Standard row; `plan ||=` would leave the 5% FeeEngine accrual
    # ($31.73 on $634.50) looking like a mystery spend.
    def ensure_free_plan!(event)
      current = Event::Plan.find_by(event_id: event.id, aasm_state: "active")
      return if current.is_a?(Event::Plan::Free)

      current&.update_columns(aasm_state: "inactive", inactive_at: Time.current, updated_at: Time.current)
      save_unvalidated!(Event::Plan::Free.new(event:))
      event.association(:plan).reset
    end

    # `welcome: true` puts the position back to its first visit — the
    # "Welcome to Maya's Lawn Care / Show me around" overlay and the guided
    # tour — so every reset gives the room the first-run experience. Any tour
    # already started is retired rather than deleted; `start_tour` makes a new
    # one when the presenter clicks "Show me around".
    def upsert_position!(user:, event:, role:, welcome:)
      position = OrganizerPosition.find_or_initialize_by(user_id: user.id, event_id: event.id)
      position.role = role
      position.deleted_at = nil
      position.first_time = welcome
      save_unvalidated!(position)

      Tour.unscoped.where(tourable: position).update_all(active: false, updated_at: Time.current) if welcome

      unless position.organizer_position_invite
        save_unvalidated!(
          OrganizerPositionInvite.new(
            user_id: user.id, event_id: event.id, sender_id: user.id,
            organizer_position_id: position.id, accepted_at: Time.now, role:
          )
        )
      end
      position
    end

    # The two sample offers, restored to their canonical state. Anything the
    # presenter added during a demo is archived so the list reads the same
    # every time; archived offers stay findable under "Archived".
    def seed_offers!(event)
      names = SAMPLE_OFFERS.map { |attrs| attrs[:name] }
      event.fuime_offers.live.where.not(name: names).find_each do |extra|
        extra.archive! if extra.may_archive?
      rescue => e
        @warnings << "Could not archive #{extra.name}: #{e.message}"
      end

      SAMPLE_OFFERS.each_with_index do |attrs, index|
        offer = event.fuime_offers.find_or_initialize_by(name: attrs[:name])
        offer.assign_attributes(
          description: attrs[:description],
          unit_label: attrs[:unit_label],
          price_cents: attrs[:price_cents],
          listed: true,
          position: index + 1
        )
        offer.save!

        if attrs[:publish]
          next if offer.published?

          offer.publish! || @warnings << "Could not publish #{offer.name}: #{offer.errors.full_messages.to_sentence}"
        elsif offer.published? && offer.may_unpublish?
          offer.unpublish!
        end
      end
    end

    # Replace this venture's mock ledger so a prod pitch is not stuck with
    # invented spend. Deletes mappings + FeeEngine accruals + FUIMEPLAYGROUND
    # raw CSV rows. Does not touch ledger engine internals (Rule 3).
    def wipe_mock_ledger!(event)
      return unless event.persisted?

      mappings = CanonicalEventMapping.where(event_id: event.id)
      cem_ids = mappings.pluck(:id)
      ct_ids = mappings.pluck(:canonical_transaction_id)

      raws = RawCsvTransaction.where(unique_bank_identifier: BANK_IDENTIFIER)
      raw_ids = raws.pluck(:id)
      hashed_ids = HashedTransaction.where(raw_csv_transaction_id: raw_ids).pluck(:id)
      ct_ids |= CanonicalTransaction.where(
        transaction_source_type: "RawCsvTransaction",
        transaction_source_id: raw_ids
      ).pluck(:id)

      ledger_ids = Ledger.where(event_id: event.id).pluck(:id)
      item_ids = ledger_ids.any? ? Ledger::Mapping.where(ledger_id: ledger_ids).pluck(:ledger_item_id) : []
      if item_ids.any?
        ct_ids |= CanonicalTransaction.where(ledger_item_id: item_ids).pluck(:id)
      end

      Fee.where(canonical_event_mapping_id: cem_ids).delete_all if cem_ids.any?
      Fee.where(event_id: event.id).delete_all
      CanonicalHashedMapping.where(canonical_transaction_id: ct_ids).delete_all if ct_ids.any?
      CanonicalHashedMapping.where(hashed_transaction_id: hashed_ids).delete_all if hashed_ids.any?
      CanonicalPendingSettledMapping.where(canonical_transaction_id: ct_ids).delete_all if ct_ids.any?
      mappings.delete_all

      if ct_ids.any?
        CanonicalTransaction.where(id: ct_ids).update_all(ledger_item_id: nil)
        CanonicalTransaction.where(id: ct_ids).delete_all
      end

      if hashed_ids.any?
        HashedTransaction.where(id: hashed_ids).update_all(duplicate_of_hashed_transaction_id: nil)
        HashedTransaction.where(duplicate_of_hashed_transaction_id: hashed_ids).update_all(duplicate_of_hashed_transaction_id: nil)
        HashedTransaction.where(id: hashed_ids).delete_all
      end
      raws.delete_all

      HcbCode.where(ledger_item_id: item_ids).update_all(ledger_item_id: nil) if item_ids.any?
      Ledger::Mapping.where(ledger_id: ledger_ids).delete_all if ledger_ids.any?
      if item_ids.any?
        Ledger::Item.where(id: item_ids).update_all(author_id: nil)
        Ledger::Item.where(id: item_ids).delete_all
      end
    rescue => e
      @warnings << "Ledger wipe skipped: #{e.message}"
    end

    def fund!(event, lines = LEDGER_LINES)
      raws = lines.map do |line|
        ::RawCsvTransactionService::Create.new(
          unique_bank_identifier: BANK_IDENTIFIER,
          date: line[:days_ago].days.ago.iso8601(3),
          memo: line[:memo],
          amount: BigDecimal(line[:cents]) / 100
        ).run
      end

      ::TransactionEngine::HashedTransactionService::RawCsvTransaction::Import.new.run
      ::TransactionEngine::CanonicalTransactionService::Import::All.new.run

      raws.each do |raw|
        canonical = raw.reload.canonical_transaction
        raise "no canonical transaction for raw ##{raw.id}" if canonical.nil?

        CanonicalEventMapping.create!(canonical_transaction: canonical, event:)
      end
    rescue => e
      @warnings << "Ledger seed skipped: #{e.message}"
    end

  end
end
