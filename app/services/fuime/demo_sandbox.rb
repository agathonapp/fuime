# frozen_string_literal: true

# Fuime: a known demo world so the founder can click every major flow
# without real teens or parents.
#
#   rake fuime:demo              reset + seed + print the 15-minute path
#   open /admin/demo             same cast, Become via existing impersonate
#
# Does NOT invent Stripe money and does NOT run when Stripe is live.
# Become is UsersController#impersonate (admin-only). No extra login door.
#
# Emails are `demo+<role>@fuime.test`. Users carry `creation_method: :demo`.
# Reset touches only that cast (plus the three `demo-*` venture slugs and
# the DEMOFOUNDERS cohort).
module Fuime
  class DemoSandbox
    class Error < StandardError; end

    EMAIL_DOMAIN = "fuime.test"
    EMAIL_PREFIX = "demo+"
    WAITLIST_SOURCE = "demo-sandbox"
    COHORT_CODE = "DEMOFOUNDERS"
    STAGING_FLAG = "FUIME_DEMO_SANDBOX"
    WRITE_CONFIRM = "FUIME_DEMO_CONFIRM"
    WRITE_CONFIRM_VALUE = "yes-seed-demo-cast"

    SLUGS = {
      storefront: "demo-lawn-care",
      unvetted: "demo-window-wash",
      cohort: "demo-cohort-studio"
    }.freeze

    # The 15-minute click-through. Specs lock this list. The admin page and
    # `rake fuime:demo` banner render it. Add a step here, not in a second doc.
    CHECKLIST_IDS = %w[
      waitlist
      accept
      waive
      solo
      cohort
      vet
      checkout
      billing
      remind
    ].freeze

    CAST_PEOPLE = [
      { key: "admin", role: "Operator", purpose: "Work every queue; Become anyone else" },
      { key: "waitlist.fresh", role: "Waitlist", purpose: "Invite this one first" },
      { key: "waitlist.older", role: "Waitlist", purpose: "Older uninvited signup" },
      { key: "waitlist.invited", role: "Waitlist", purpose: "Already invited — Willa can sign in" },
      { key: "parent.pending", role: "Parent", purpose: "Tick the accept checkbox (Become required)" },
      { key: "teen.pending", role: "Teen", purpose: "Waiting on Pat to accept" },
      { key: "parent.remind", role: "Parent", purpose: "Due a day-3 reminder" },
      { key: "teen.remind", role: "Teen", purpose: "Paired with Robin Reminder" },
      { key: "parent.stale", role: "Parent", purpose: "Stale queue (invite expired)" },
      { key: "teen.stale", role: "Teen", purpose: "Paired with Sky Stale" },
      { key: "teen.unguarded", role: "Teen", purpose: "No parent — waive this one" },
      { key: "teen.solo", role: "Teen", purpose: "Demo Solo Lawn is under review" },
      { key: "parent.solo", role: "Parent", purpose: "Already accepted for Sonia" },
      { key: "teen.cohort", role: "Teen", purpose: "Auto-admitted via DEMOFOUNDERS" },
      { key: "parent.cohort", role: "Parent", purpose: "Already accepted for Cora" },
      { key: "teen.unvetted", role: "Teen", purpose: "Demo Window Wash waits on vetting" },
      { key: "parent.unvetted", role: "Parent", purpose: "Already accepted for Vince" },
      { key: "teen.store", role: "Teen", purpose: "Runs Demo Lawn Care" },
      { key: "parent.store", role: "Parent", purpose: "Upgrade to Pro on /my/billing" }
    ].freeze

    # Every mailbox the cast owns. Reset keys off this prefix + domain, not
    # off this list, so a forgotten row cannot orphan a user.
    def self.email(key)
      "#{EMAIL_PREFIX}#{key}@#{EMAIL_DOMAIN}"
    end

    def self.demo_email?(email)
      email.to_s.strip.downcase.match?(/\A#{Regexp.escape(EMAIL_PREFIX)}.+@#{Regexp.escape(EMAIL_DOMAIN)}\z/)
    end

    # Safe to show the roster / mint codes. Never true when Stripe is live,
    # including a production deploy that still has test keys unset-wrongly
    # flipped to live.
    def self.enabled?
      return false if StripeService.live?
      return true if Rails.env.development? || Rails.env.test?

      ENV[STAGING_FLAG].to_s == "1"
    end

    def self.guard_enabled!
      raise Error, "refusing: Stripe is in live mode" if StripeService.live?
      raise Error, "refusing: demo sandbox is off (local, or #{STAGING_FLAG}=1 with test-mode Stripe)" unless enabled?
    end

    def self.guard_write!
      guard_enabled!
      return if Rails.env.development? || Rails.env.test?

      unless ENV[WRITE_CONFIRM] == WRITE_CONFIRM_VALUE
        raise Error, "refusing a write outside development without #{WRITE_CONFIRM}=#{WRITE_CONFIRM_VALUE}"
      end
    end

    def initialize
      @warnings = []
    end

    # The one command: wipe this cast, put it back, ready to click.
    def setup!
      reset!
      seed!
    end

    def seed!
      self.class.guard_write!

      without_mail do
        admin = upsert_admin!
        seed_waitlist!(admin)
        seed_pending_family!
        seed_reminder_family!
        seed_stale_family!
        seed_unguarded_teen!
        seed_solo_application!
        cohort = seed_live_cohort!(admin)
        seed_cohort_venture!(cohort)
        seed_unvetted_venture!
        seed_storefront!
      end

      { users: demo_users.count, events: demo_events.count, warnings: @warnings }
    end

    def reset!
      self.class.guard_write!

      user_ids = demo_users.pluck(:id)
      event_ids = demo_events.pluck(:id)
      cohort_ids = Fuime::Cohort.where(code: COHORT_CODE).pluck(:id)

      ActiveRecord::Base.transaction do
        delete_demo_graph!(user_ids:, event_ids:, cohort_ids:)
      end

      clear_demo_waitlist!
      { users_removed: user_ids.size, events_removed: event_ids.size }
    end

    def status
      {
        enabled: self.class.enabled?,
        stripe_mode: StripeService.mode,
        merchant_of_record: Fuime::Features.merchant_of_record?,
        waitlist_configured: Fuime::WaitlistRoster.configured?,
        warnings: storefront_warnings,
        admin: present_user(:admin),
        waitlist: waitlist_rows,
        people: people_rows,
        queues: queue_counts,
        ventures: venture_rows,
        cohort: cohort_row,
        checklist: checklist
      }
    end

    # Living 15-minute path. Each item has a URL and a string the page must
    # contain, so the smoke spec fails if a step rots.
    def checklist
      routes = Rails.application.routes.url_helpers
      pending = pending_for("teen.pending")
      unguarded = User.find_by(email: email("teen.unguarded"))
      solo = Event::Application.find_by(name: "Demo Solo Lawn")

      [
        {
          id: "waitlist", n: 1, title: "Waitlist → invite → login",
          persona_key: "admin", href: routes.admin_waitlist_index_path,
          expect: email("waitlist.fresh"),
          do: "Invite demo+waitlist.fresh@fuime.test. Optional cohort DEMOFOUNDERS. Then Become Willa or open the mailed link."
        },
        {
          id: "accept", n: 2, title: "Parent accept (checkbox)",
          persona_key: "parent.pending",
          href: pending&.invite_token ? routes.guardianship_path(pending.invite_token) : routes.guardianships_admin_index_path,
          expect: "I confirm I am the parent",
          do: "Become Pat Pending (Ada gets a 403 — only the invited parent can open this). Tick the 18+ box. Agree. Pia can operate."
        },
        {
          id: "waive", n: 3, title: "Admin waive guardian",
          persona_key: "admin",
          href: unguarded ? routes.admin_user_path(unguarded) : routes.users_admin_index_path,
          expect: "Waive guardian requirement",
          do: "On Uma Unguarded's admin page, waive (optional reason). Restore puts the gate back."
        },
        {
          id: "solo", n: 4, title: "Solo apply → admit",
          persona_key: "admin",
          href: solo ? routes.submission_application_path(solo) : routes.applications_admin_index_path,
          expect: "Demo Solo Lawn",
          do: "Approve, then activate Demo Solo Lawn. Sonia is already guardian-backed."
        },
        {
          id: "cohort", n: 5, title: "Cohort auto-admit",
          persona_key: "admin", href: routes.cohorts_admin_index_path,
          expect: COHORT_CODE,
          do: "DEMOFOUNDERS is live; Cora is already on the roster. A new 16-year-old who types the code is approved + vetted."
        },
        {
          id: "vet", n: 6, title: "Operator vetting",
          persona_key: "admin", href: routes.operator_vetting_admin_index_path,
          expect: "Demo Window Wash",
          do: "Approve Demo Window Wash with a note. Do not turn vetting off."
        },
        {
          id: "checkout", n: 7, title: "MoR guest checkout → ledger",
          persona_key: nil,
          href: routes.fuime_storefront_path(SLUGS[:storefront]),
          expect: "Demo Lawn Care",
          do: "Guest Buy (or /pay/demo-lawn-care/front-and-back) with 4242. stripe listen → /fuime/webhooks/stripe. Two pending lines. SLUG=demo-lawn-care rake fuime:mor_webhook_pass:settle"
        },
        {
          id: "billing", n: 8, title: "Billing / Pro upgrade",
          persona_key: "parent.store", href: routes.my_billing_path,
          expect: "$19.99",
          do: "Become Denise Store. Upgrade — $19.99/mo, take-rate stays 7%. Teen sees who to ask, no button."
        },
        {
          id: "remind", n: 9, title: "Guardian reminder / stale queue",
          persona_key: "admin", href: routes.guardianships_admin_index_path,
          expect: email("parent.stale"),
          do: "Run reminder job (Robin is due day-3). Stale tab shows Sky. Resend mints a new token."
        }
      ].map { |step| step.merge(persona: step[:persona_key] && present_user(step[:persona_key])) }
    end

    def banner
      status = self.status
      lines = []
      lines << "Fuime demo sandbox"
      lines << "  rake fuime:demo          reset + seed + this banner"
      lines << "  open /admin/demo         checklist + Become (existing impersonate)"
      lines << "  stripe=#{status[:stripe_mode]}  MoR=#{status[:merchant_of_record]}  waitlist=#{status[:waitlist_configured]}"
      status[:warnings].each { |w| lines << "  ! #{w}" }
      lines << ""
      lines << "Cast  (demo+…@fuime.test — Become them from /admin/demo; existing impersonate, no backdoor)"
      status[:people].each do |row|
        mark = row[:present] ? "✓" : "·"
        lines << "  #{mark} #{row[:email].to_s.ljust(36)}  #{row[:role]}  #{row[:purpose]}"
      end
      lines << ""
      lines << "15-minute checklist"
      status[:checklist].each do |step|
        who = step[:persona] ? step[:persona][:email] : "guest"
        lines << "  #{step[:n]}. #{step[:title]}"
        lines << "     as #{who}"
        lines << "     #{step[:href]}"
        lines << "     #{step[:do]}"
      end
      lines << ""
      lines << "Test card  4242 4242 4242 4242  ·  never live Stripe"
      lines << "Reset only this cast:  rake fuime:demo:reset"
      lines.join("\n")
    end

    def mint_login_code!(email)
      self.class.guard_enabled!
      normalized = email.to_s.strip.downcase
      raise Error, "not a demo mailbox (must be #{EMAIL_PREFIX}…@#{EMAIL_DOMAIN})" unless self.class.demo_email?(normalized)

      user = User.find_by(email: normalized)
      raise Error, "no demo user #{normalized} — run rake fuime:demo:seed" if user.nil?

      LoginCode.create!(user:)
    end

    def remind_now!
      self.class.guard_enabled!
      Fuime::GuardianInviteReminderJob.perform_now
    end

    def smoke_checks
      checks = []
      checks << ["admin is superadmin", User.find_by(email: self.class.email("admin"))&.superadmin? == true]
      checks << ["fresh pending invite", pending_for("teen.pending")&.pending? == true]
      checks << ["stale invite is stale", Guardianship.stale_pending.exists?(minor: User.find_by(email: self.class.email("teen.stale")))]
      checks << ["day-3 invite is due", Guardianship.due_for_invite_reminder.exists?(minor: User.find_by(email: self.class.email("teen.remind")))]
      checks << ["unguarded teen needs guardian", User.find_by(email: self.class.email("teen.unguarded"))&.needs_guardian? == true]
      checks << ["solo application under review", Event::Application.under_review.exists?(name: "Demo Solo Lawn")]
      checks << ["live cohort", Fuime::Cohort.live.exists?(code: COHORT_CODE)]
      checks << ["unvetted venture", Event.unscoped.exists?(slug: SLUGS[:unvetted], operator_vetting_status: :unvetted)]
      checks << ["storefront venture", Event.unscoped.exists?(slug: SLUGS[:storefront])]
      checks << ["storefront offer", Fuime::Offer.exists?(event: Event.unscoped.find_by(slug: SLUGS[:storefront]))]
      checks << ["checklist ids locked", checklist.map { |step| step[:id] } == CHECKLIST_IDS]
      checklist.each do |step|
        checks << ["checklist #{step[:id]} has a path", step[:href].to_s.start_with?("/")]
        checks << ["checklist #{step[:id]} names an expect", step[:expect].present?]
      end
      checks
    end

    private

    def email(key) = self.class.email(key)

    def demo_users
      User.where("email LIKE ?", "#{EMAIL_PREFIX}%@#{EMAIL_DOMAIN}")
    end

    def demo_events
      Event.unscoped.where(slug: SLUGS.values)
    end

    def upsert_admin!
      admin = upsert_user!(
        key: "admin",
        name: "Ada Demo Admin",
        birthday: 40.years.ago.to_date,
        access_level: :superadmin
      )

      limit = Governance::Admin::Transfer::Limit.find_or_initialize_by(user: admin)
      limit.amount_cents = 10_000_00 unless limit.persisted?
      limit.save!
      admin
    end

    def seed_waitlist!(admin)
      unless Fuime::WaitlistRoster.configured?
        @warnings << "WAITLIST_REDIS_URL is unset — skip waitlist rows. Set it and re-seed to fill /admin/waitlist."
        return
      end

      conn = Redis.new(**Fuime::WaitlistRoster.connection_options(Fuime::WaitlistRoster.url))

      [
        { key: "waitlist.older", days_ago: 12, invited: false },
        { key: "waitlist.fresh", days_ago: 2, invited: false },
        { key: "waitlist.invited", days_ago: 5, invited: true }
      ].each do |row|
        address = email(row[:key])
        conn.sadd(Fuime::WaitlistRoster::LIST_KEY, address)
        meta = {
          "source" => WAITLIST_SOURCE,
          "at" => row[:days_ago].days.ago.utc.iso8601
        }
        if row[:invited]
          meta["invited_at"] = 1.day.ago.utc.iso8601
          meta["invited_by"] = admin.email
          meta["cohort_code"] = COHORT_CODE
        end
        conn.hset("#{Fuime::WaitlistRoster::META_PREFIX}#{address}", meta)
      end

      upsert_user!(
        key: "waitlist.invited",
        name: "Willa Waitlist",
        birthday: 16.years.ago.to_date,
        creation_method: :waitlist
      )

      Rails.cache.delete(Fuime::WaitlistRoster::NAV_CACHE_KEY)
    rescue Redis::BaseError, SocketError, IOError => e
      @warnings << "waitlist seed failed: #{e.message}"
    end

    def seed_pending_family!
      teen = upsert_user!(key: "teen.pending", name: "Pia Pending", birthday: 15.years.ago.to_date)
      parent = upsert_stub_parent!("parent.pending", "Pat Pending")
      upsert_guardianship!(guardian: parent, minor: teen, sent_at: 2.hours.ago)
    end

    def seed_reminder_family!
      teen = upsert_user!(key: "teen.remind", name: "Remy Reminder", birthday: 15.years.ago.to_date)
      parent = upsert_stub_parent!("parent.remind", "Robin Reminder")
      upsert_guardianship!(
        guardian: parent,
        minor: teen,
        sent_at: (Guardianship::REMINDER_DAY_3 + 2.hours).ago
      )
    end

    def seed_stale_family!
      teen = upsert_user!(key: "teen.stale", name: "Sam Stale", birthday: 15.years.ago.to_date)
      parent = upsert_stub_parent!("parent.stale", "Sky Stale")
      upsert_guardianship!(
        guardian: parent,
        minor: teen,
        sent_at: (Guardianship::STALE_AFTER + 1.day).ago
      )
    end

    def seed_unguarded_teen!
      upsert_user!(key: "teen.unguarded", name: "Uma Unguarded", birthday: 16.years.ago.to_date)
    end

    def seed_solo_application!
      teen = upsert_user!(key: "teen.solo", name: "Sonia Solo", birthday: 16.years.ago.to_date)
      parent = upsert_user!(key: "parent.solo", name: "Saul Solo", birthday: 42.years.ago.to_date)
      upsert_guardianship!(guardian: parent, minor: teen, status: :active)

      application = Event::Application.find_or_initialize_by(user: teen, name: "Demo Solo Lawn")
      application.assign_attributes(
        description: "I mow lawns after school. Demo sandbox — not a real applicant.",
        teen_led: true,
        starting_point: "have_idea",
        service_type: "lawn_and_garden",
        address_country: "US",
        cosigner_email: parent.email
      )
      save_unvalidated!(application)
      application.update_columns(
        aasm_state: "under_review",
        submitted_at: 1.day.ago,
        under_review_at: 1.day.ago,
        archived_at: nil,
        event_id: nil
      )
    end

    def seed_live_cohort!(admin)
      cohort = Fuime::Cohort.find_or_initialize_by(code: COHORT_CODE)
      cohort.assign_attributes(
        name: "Demo Founders Weekend",
        rationale: "Demo sandbox cohort so /admin/cohorts has a live code. Not a real voucher.",
        expires_at: 14.days.from_now,
        max_members: 25,
        risk_level: "slight",
        auto_approve: true,
        created_by: admin,
        archived_at: nil
      )
      cohort.save!
      cohort
    end

    def seed_cohort_venture!(cohort)
      teen = upsert_user!(key: "teen.cohort", name: "Cora Cohort", birthday: 16.years.ago.to_date)
      parent = upsert_user!(key: "parent.cohort", name: "Carl Cohort", birthday: 44.years.ago.to_date)
      upsert_guardianship!(guardian: parent, minor: teen, status: :active)

      event = upsert_event!(
        slug: SLUGS[:cohort],
        name: "Demo Cohort Studio",
        teen:,
        category: "digital",
        vetted: true,
        public: true,
        cohort:
      )

      application = Event::Application.find_or_initialize_by(user: teen, name: event.name)
      application.assign_attributes(
        description: "Already auto-admitted under DEMOFOUNDERS. Demo sandbox.",
        teen_led: true,
        starting_point: "have_idea",
        service_type: "design_and_art",
        address_country: "US",
        cosigner_email: parent.email,
        fuime_cohort: cohort,
        event:
      )
      save_unvalidated!(application)
      application.update_columns(
        aasm_state: "approved",
        submitted_at: 3.days.ago,
        under_review_at: 3.days.ago,
        approved_at: 3.days.ago,
        archived_at: nil,
        event_id: event.id,
        fuime_cohort_id: cohort.id
      )
    end

    def seed_unvetted_venture!
      teen = upsert_user!(key: "teen.unvetted", name: "Vince Unvetted", birthday: 16.years.ago.to_date)
      parent = upsert_user!(key: "parent.unvetted", name: "Vera Unvetted", birthday: 45.years.ago.to_date)
      upsert_guardianship!(guardian: parent, minor: teen, status: :active)

      upsert_event!(
        slug: SLUGS[:unvetted],
        name: "Demo Window Wash",
        teen:,
        category: "services",
        vetted: false,
        public: false
      )
    end

    def seed_storefront!
      teen = upsert_user!(key: "teen.store", name: "Maya Store", birthday: 16.years.ago.to_date)
      parent = upsert_user!(key: "parent.store", name: "Denise Store", birthday: 43.years.ago.to_date)
      upsert_guardianship!(guardian: parent, minor: teen, status: :active)

      event = upsert_event!(
        slug: SLUGS[:storefront],
        name: "Demo Lawn Care",
        teen:,
        category: "services",
        vetted: true,
        public: true,
        tagline: "Front and back lawn, after school. Demo sandbox — not a real business.",
        sale_terms: true
      )

      offer = Fuime::Offer.find_or_initialize_by(event:, slug: "front-and-back")
      offer.assign_attributes(
        name: "Front and back lawn mow",
        description: "Includes edging. Demo offer — do not treat as a real listing.",
        unit_label: "per visit",
        price_cents: 35_00,
        listed: true,
        created_via: "operator"
      )
      offer.save!

      if event.reload.accepts_payments?
        offer.publish! if offer.may_publish?
      else
        @warnings << "storefront cannot accept payments yet " \
                     "(FEATURE_MERCHANT_OF_RECORD=#{ENV['FEATURE_MERCHANT_OF_RECORD'].inspect}). " \
                     "Offer stays draft. Turn the flag on and re-seed, or publish from the UI."
      end
    end

    def upsert_user!(key:, name:, birthday:, access_level: :user, creation_method: :demo)
      user = User.find_or_initialize_by(email: email(key))
      user.assign_attributes(
        full_name: name,
        birthday:,
        verified: true,
        access_level:,
        creation_method:
      )
      save_unvalidated!(user)
      user
    end

    # Parent stub — no birthday — so the accept checkbox is the 18+ assertion
    # (Guardianship#activation_blockers), matching GuardianInviteService.
    def upsert_stub_parent!(key, name)
      user = User.find_or_initialize_by(email: email(key))
      user.assign_attributes(
        full_name: name,
        birthday: nil,
        age_attestation: nil,
        verified: true,
        creation_method: :demo
      )
      save_unvalidated!(user)
      user
    end

    def upsert_guardianship!(guardian:, minor:, status: :pending, sent_at: Time.current)
      record = Guardianship.find_or_initialize_by(guardian:, minor:)
      record.status = status
      record.invite_token ||= SecureRandom.hex(16)
      record.invite_sent_at = sent_at
      record.invite_day3_reminded_at = nil
      record.invite_day6_reminded_at = nil

      if status.to_s == "active"
        record.agreement_signed_at ||= sent_at
        record.agreement_version ||= Guardianship::CURRENT_AGREEMENT_VERSION
      else
        record.agreement_signed_at = nil
        record.agreement_version = nil
        record.revoked_at = nil
      end

      save_unvalidated!(record)
      record
    end

    def upsert_event!(slug:, name:, teen:, category:, vetted:, public:, cohort: nil, tagline: nil, sale_terms: false)
      event = Event.unscoped.find_or_initialize_by(slug:)
      event.assign_attributes(
        name:,
        country: "US",
        point_of_contact: teen,
        business_category: category,
        is_public: public,
        is_indexable: public,
        demo_mode: false,
        hidden_at: nil,
        activated_at: event.activated_at || 1.week.ago,
        aasm_state: "approved",
        storefront_tagline: tagline,
        fuime_cohort: cohort
      )
      save_unvalidated!(event)

      if vetted
        event.update_columns(
          operator_vetting_status: Event.operator_vetting_statuses.fetch("approved"),
          operator_vetted_at: event.operator_vetted_at || Time.current,
          operator_vetting_notes: event.operator_vetting_notes.presence ||
            "Demo sandbox — pre-approved so the storefront can be clicked."
        )
      else
        event.update_columns(
          operator_vetting_status: Event.operator_vetting_statuses.fetch("unvetted"),
          operator_vetted_at: nil,
          operator_vetted_by_id: nil
        )
      end

      if sale_terms
        event.update_columns(
          sale_terms_acknowledged_at: Time.current,
          sale_terms_acknowledged_by_id: teen.id,
          sale_terms_version: Event::SALE_TERMS_VERSION
        )
      end

      grant_position!(event:, user: teen, role: :manager)
      event
    end

    def grant_position!(event:, user:, role:)
      return if event.organizer_positions.exists?(user:)

      invite = OrganizerPositionInvite.create!(event:, user:, sender: user, role:)
      return if invite.accept(show_onboarding: false)

      raise Error, "could not seat #{user.email} on #{event.slug}: #{invite.errors.full_messages.to_sentence}"
    end

    def save_unvalidated!(record)
      record.save!(validate: false)
    end

    def without_mail
      old_mail = ActionMailer::Base.perform_deliveries
      old_queue = ActiveJob::Base.queue_adapter
      ActionMailer::Base.perform_deliveries = false
      ActiveJob::Base.queue_adapter = :test
      yield
    ensure
      ActionMailer::Base.perform_deliveries = old_mail
      ActiveJob::Base.queue_adapter = old_queue
    end

    def delete_demo_graph!(user_ids:, event_ids:, cohort_ids:)
      return if user_ids.empty? && event_ids.empty? && cohort_ids.empty?

      Fuime::Offer.where(event_id: event_ids).delete_all if event_ids.any?
      Event::Application.where(user_id: user_ids).or(Event::Application.where(event_id: event_ids)).delete_all
      if event_ids.any?
        OrganizerPositionInvite.unscoped.where(event_id: event_ids).delete_all
        OrganizerPosition.unscoped.where(event_id: event_ids).delete_all
        Event::Configuration.where(event_id: event_ids).delete_all
        if defined?(PublicActivity::Activity)
          PublicActivity::Activity.where(trackable_type: "Event", trackable_id: event_ids).delete_all
        end
        conn = ActiveRecord::Base.connection
        if conn.table_exists?("event_tags_events")
          conn.delete("DELETE FROM event_tags_events WHERE event_id IN (#{event_ids.join(',')})")
        end
      end
      if user_ids.any?
        OrganizerPositionInvite.unscoped.where(user_id: user_ids).or(
          OrganizerPositionInvite.unscoped.where(sender_id: user_ids)
        ).delete_all
        OrganizerPosition.unscoped.where(user_id: user_ids).delete_all
        Guardianship.where(guardian_id: user_ids).or(Guardianship.where(minor_id: user_ids)).delete_all
        LoginCode.where(user_id: user_ids).delete_all
        User::Session.where(user_id: user_ids).delete_all
        Login.where(user_id: user_ids).delete_all
        Governance::Admin::Transfer::Limit.where(user_id: user_ids).delete_all
      end
      if event_ids.any?
        Ledger.where(event_id: event_ids).delete_all
        Event::Plan.where(event_id: event_ids).delete_all
        FriendlyId::Slug.where(sluggable_type: "Event", sluggable_id: event_ids).delete_all
        Event.unscoped.where(id: event_ids).update_all(fuime_cohort_id: nil, point_of_contact_id: nil)
        Event.unscoped.where(id: event_ids).delete_all
      end
      Fuime::Cohort.where(id: cohort_ids).delete_all if cohort_ids.any?
      if user_ids.any?
        entity_ids = LegalEntityUser.where(user_id: user_ids).pluck(:legal_entity_id)
        LegalEntityUser.where(user_id: user_ids).delete_all
        LegalEntity.where(id: entity_ids).delete_all if entity_ids.any?
        if defined?(PaperTrail::Version)
          PaperTrail::Version.where(item_type: "User", item_id: user_ids).delete_all
        end
      end
      User.where(id: user_ids).delete_all
    end

    def clear_demo_waitlist!
      return unless Fuime::WaitlistRoster.configured?

      conn = Redis.new(**Fuime::WaitlistRoster.connection_options(Fuime::WaitlistRoster.url))
      emails = conn.smembers(Fuime::WaitlistRoster::LIST_KEY).select { |e| self.class.demo_email?(e) }
      emails.each do |address|
        conn.srem(Fuime::WaitlistRoster::LIST_KEY, address)
        conn.del("#{Fuime::WaitlistRoster::META_PREFIX}#{address}")
      end
      Rails.cache.delete(Fuime::WaitlistRoster::NAV_CACHE_KEY)
    rescue Redis::BaseError, SocketError, IOError
      nil
    end

    def pending_for(teen_key)
      teen = User.find_by(email: email(teen_key))
      return nil unless teen

      Guardianship.find_by(minor: teen)
    end

    def present_user(key)
      return nil if key.blank?

      user = User.find_by(email: email(key))
      return nil unless user

      { id: user.id, email: user.email, name: user.full_name, admin: user.admin? }
    end

    def people_rows
      listed = waitlist_rows.map(&:email)
      CAST_PEOPLE.map do |row|
        address = email(row[:key])
        user = User.find_by(email: address)
        {
          key: row[:key],
          role: row[:role],
          purpose: row[:purpose],
          email: address,
          present: user.present? || listed.include?(address),
          id: user&.id,
          name: user&.full_name,
          admin: user&.admin? || false
        }
      end
    end

    def waitlist_rows
      return [] unless Fuime::WaitlistRoster.configured?

      Fuime::WaitlistRoster.new.fetch[:signups].select { |s| self.class.demo_email?(s.email) }
    rescue Fuime::WaitlistRoster::ReadFailed
      []
    end

    def queue_counts
      {
        waitlist: (Fuime::WaitlistRoster.configured? ? waitlist_rows.size : nil),
        applications_under_review: Event::Application.under_review.where(name: "Demo Solo Lawn").count,
        live_cohorts: Fuime::Cohort.live.where(code: COHORT_CODE).count,
        unvetted: Event.not_hidden.operator_vetting_unvetted.where(slug: SLUGS[:unvetted]).count,
        stale_invites: Guardianship.stale_pending.joins(:minor).where(users: { email: email("teen.stale") }).count
      }
    end

    def venture_rows
      SLUGS.map do |key, slug|
        event = Event.unscoped.find_by(slug:)
        next { key:, slug:, present: false } unless event

        {
          key:,
          slug:,
          present: true,
          name: event.name,
          vetted: event.operator_vetting_approved?,
          accepts_payments: event.accepts_payments?,
          offer: event.fuime_offers.order(:id).last&.then { |o| "#{o.name} (#{o.aasm_state})" }
        }
      end
    end

    def cohort_row
      cohort = Fuime::Cohort.find_by(code: COHORT_CODE)
      return nil unless cohort

      { code: cohort.code, name: cohort.name, live: cohort.admitting?, members: cohort.member_count }
    end

    def storefront_warnings
      warnings = @warnings.dup
      event = Event.unscoped.find_by(slug: SLUGS[:storefront])
      if event && !event.accepts_payments?
        warnings << "Demo Lawn Care cannot take a card: #{event.selling_blockers.join('; ').presence || 'FEATURE_MERCHANT_OF_RECORD is off (Connect needs a ready connected account)'}"
      end
      warnings
    end
  end
end
