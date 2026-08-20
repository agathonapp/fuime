# frozen_string_literal: true

# Fuime: clear the inherited HCB demo data so the platform starts from one
# Fuime HQ organisation and an empty ledger.
#
# ── What this does NOT touch ────────────────────────────────────────────────
#
# Users, sessions, logins, guardianships, legal entities and their KYC, Flipper
# flags, PaperTrail versions, and Ahoy analytics all survive. People keep their
# accounts and their verification; what goes is the money and the orgs.
#
# ── The twelve organisations that cannot be deleted ─────────────────────────
#
# EventMappingEngine::EventIds names twelve events by hardcoded integer id —
# INCOMING_FEES routes every fee, NOEVENT is where unmapped money lands, and the
# grant funds and sweeps are referenced the same way. Deleting those rows means
# rewriting the ledger engine's constants, which Phase 0 forbids (CLAUDE.md
# Rule 3). So they stay at their ids, get Fuime names, and are hidden from the
# organisation lists. `Event.approved` counts already exclude them.
#
# ── Order matters ───────────────────────────────────────────────────────────
#
# Nothing here relies on ActiveRecord callbacks: Event is `acts_as_paranoid`, so
# `destroy` would only set deleted_at, and the model has twenty `dependent:`
# declarations against a hundred-odd associations that do not have one. Rows go
# out with SQL, children before parents, inside one transaction — a foreign-key
# violation rolls the whole thing back rather than leaving a half-erased ledger.
namespace :fuime do
  # Every table that holds a transaction, a ledger line, or a fee. Cleared in
  # full for every organisation, including the twelve that stay.
  # rubocop:disable Lint/ConstantDefinitionInBlock
  LEDGER_TABLES = %w[
    admin_ledger_audit_tasks
    admin_ledger_audits
    canonical_event_mappings
    canonical_hashed_mappings
    canonical_pending_declined_mappings
    canonical_pending_event_mappings
    canonical_pending_settled_mappings
    canonical_pending_transactions
    canonical_transactions
    card_charge_raw_stripe_transactions
    card_charges
    card_grant_pre_authorizations
    card_grants
    donations
    fee_reimbursements
    fee_relationships
    fee_revenues
    fees
    hashed_transactions
    hcb_code_personal_transactions
    hcb_code_pins
    hcb_code_tag_suggestions
    hcb_codes
    hcb_codes_tags
    invoices
    ledger_items
    ledgers
    ledger_mappings
    raw_column_transactions
    raw_csv_transactions
    raw_emburse_transactions
    raw_increase_transactions
    raw_intrafi_transactions
    raw_pending_bank_fee_transactions
    raw_pending_column_transactions
    raw_pending_donation_transactions
    raw_pending_fee_reimbursement_transactions
    raw_pending_fee_revenue_transactions
    raw_pending_incoming_disbursement_transactions
    raw_pending_invoice_transactions
    raw_pending_outgoing_ach_transactions
    raw_pending_outgoing_check_transactions
    raw_pending_outgoing_disbursement_transactions
    raw_pending_stripe_service_fee_transactions
    raw_pending_stripe_transactions
    raw_plaid_transactions
    raw_stripe_transactions
    receipts
    stripe_service_fees
    stripe_topups
    subledgers
    transaction_category_mappings
    transaction_csvs
    transactions
  ].freeze

  # Tables that reference events directly are DERIVED, not listed.
  #
  # There are 57 of them across 59 foreign-key columns (disbursements and
  # school_awards each point at events twice), and the first three attempts at
  # writing that list by hand each shipped missing a table — announcements,
  # guardian_verifications, payout_requests — which surfaced only as a
  # foreign-key violation mid-run. information_schema already knows the answer
  # and stays right when the schema moves.
  #
  # Anything in the truncate closure is excluded: those tables are emptied for
  # every organisation, including the twelve that stay.
  def event_foreign_keys(excluding:)
    ActiveRecord::Base.connection.select_all(<<~SQL).to_a
      SELECT tc.table_name AS child, kcu.column_name AS col
      FROM information_schema.table_constraints tc
      JOIN information_schema.key_column_usage kcu
        ON kcu.constraint_name = tc.constraint_name
      JOIN information_schema.constraint_column_usage ccu
        ON ccu.constraint_name = tc.constraint_name
      WHERE tc.constraint_type = 'FOREIGN KEY'
        AND tc.table_schema = 'public'
        AND ccu.table_name = 'events'
        AND tc.table_name <> 'events'
      ORDER BY 1, 2
    SQL
                      .reject { |r| excluding.include?(r["child"]) }
                      .map { |r| [r["child"], r["col"]] }
  end

  # Rows that hang off a child of events rather than off events directly, so
  # information_schema's events lookup does not see them. If one is missing,
  # delete_until_settled stalls and names the table it could not clear.
  DEPENDENT_TABLES = [
    ["organizer_position_deletion_requests", "organizer_position_id", "organizer_positions", "event_id"],
    ["organizer_position_spending_controls", "organizer_position_id", "organizer_positions", "event_id"],
    ["organizer_position_invites", "event_id", nil, nil],
    ["organizer_position_invite_requests", "organizer_position_invite_link_id", "organizer_position_invite_links", "event_id"],
    ["stripe_authorizations", "stripe_card_id", "stripe_cards", "event_id"],
    ["payments", "payee_id", "payees", "event_id"],
    ["payroll_positions", "payee_id", "payees", "event_id"],
    ["g_suite_accounts", "g_suite_id", "g_suites", "event_id"],
    ["reimbursement_expenses", "reimbursement_report_id", "reimbursement_reports", "event_id"],
    ["checks", "lob_address_id", "lob_addresses", "event_id"],
    ["venture_cards", "venture_cardholder_id", "venture_cardholders", "event_id"],
    ["venture_cardholders", "event_id", nil, nil],
  ].freeze

  # Fuime names for the twelve inherited system organisations. Keyed by the
  # EventMappingEngine constant so the mapping is readable next to the engine
  # that depends on it.
  SYSTEM_EVENT_NAMES = {
    INCOMING_FEES: "Fuime Incoming Fees",
    HACK_CLUB_BANK: "Fuime Operations",
    NOEVENT: "Fuime Unassigned",
    HACKATHON_GRANT_FUND: "Fuime Grant Fund (legacy)",
    WINTER_HARDWARE_WONDERLAND_GRANT_FUND: "Fuime Grant Fund (legacy 2)",
    GENE_HAAS_GRANT_FUND: "Fuime Grant Fund (legacy 3)",
    ARGOSY_GRANT_FUND: "Fuime Grant Fund (legacy 4)",
    ARGOSY_GRANT_FUND_2025: "Fuime Grant Fund (legacy 5)",
    FIRST_TRANSPARENCY_GRANT_FUND: "Fuime Grant Fund (legacy 6)",
    HACK_FOUNDATION_INTEREST: "Fuime Interest Earnings",
    REIMBURSEMENT_CLEARING: "Fuime Reimbursement Clearing",
    SVB_SWEEPS: "Fuime Sweeps",
  }.freeze
  # rubocop:enable Lint/ConstantDefinitionInBlock

  def system_event_ids
    SYSTEM_EVENT_NAMES.keys.map { |c| EventMappingEngine::EventIds.const_get(c) }
  end

  # Delete in whatever order the constraints allow, rather than in whatever
  # order the list happens to be written.
  #
  # These tables reference each other (fuime_offers -> fuime_api_keys,
  # organizer_position_invite_requests -> links, checks -> lob_addresses), and
  # keeping a hand-sorted list correct as the schema moves is a losing game —
  # the previous version was alphabetical and broke on the first pair that
  # cared. Each statement runs in its own savepoint so a foreign-key violation
  # costs one retry instead of the whole transaction; a pass that deletes
  # nothing and still has work left is a genuine cycle, and says so.
  def delete_until_settled(statements)
    conn = ActiveRecord::Base.connection
    remaining = statements

    while remaining.any?
      blocked = []
      progressed = false

      remaining.each do |label, sql|
        conn.transaction(requires_new: true) do
          deleted = conn.delete(sql)
          puts "  cleared #{label} (#{deleted})" if deleted.positive?
        end
        progressed = true
      rescue ActiveRecord::InvalidForeignKey
        blocked << [label, sql]
      end

      unless progressed
        raise "Cannot delete #{blocked.map(&:first).join(', ')} in any order — foreign-key cycle"
      end

      remaining = blocked
    end
  end

  def sql_count(table)
    ActiveRecord::Base.connection.select_value("SELECT COUNT(*) FROM #{table}").to_i
  rescue ActiveRecord::StatementInvalid
    0
  end

  desc "Report what fuime:reset would delete, without deleting anything"
  task reset_preview: :environment do
    keep = system_event_ids
    doomed = Event.unscoped.where.not(id: keep)

    puts "Database: #{ActiveRecord::Base.connection.current_database} (#{Rails.env})"
    puts
    puts "Ledger rows to clear:"
    LEDGER_TABLES.each do |t|
      count = sql_count(t)
      puts "  #{t.ljust(52)} #{count}" if count.positive?
    end
    puts
    puts "Organisations to delete (#{doomed.count}):"
    doomed.order(:id).each { |e| puts "  #{e.id.to_s.ljust(6)} #{e.name}" }
    puts
    puts "Organisations to keep and rename (#{keep.size}):"
    SYSTEM_EVENT_NAMES.each do |const, name|
      id = EventMappingEngine::EventIds.const_get(const)
      current = Event.unscoped.find_by(id:)
      puts "  #{id.to_s.ljust(6)} #{(current&.name || "(missing)").ljust(34)} -> #{name}"
    end
    puts
    puts "Preserved: users (#{sql_count('users')}), guardianships (#{sql_count('guardianships')}), " \
         "legal entities (#{sql_count('legal_entities')}), versions (#{sql_count('versions')})"
  end

  desc "Clear the inherited HCB demo data and leave one Fuime HQ organisation"
  task :reset, [:admin_email] => :environment do |_t, args|
    unless ENV["FUIME_RESET_CONFIRM"] == "yes-wipe-this-database"
      abort "Refusing to run without FUIME_RESET_CONFIRM=yes-wipe-this-database"
    end

    admin_email = args[:admin_email].presence
    keep = system_event_ids
    conn = ActiveRecord::Base.connection

    ActiveRecord::Base.transaction do
      # Fuime HQ survives a second run: the delete pass runs before HQ is
      # created, so without this the task deletes the org it made last time and
      # creates a new one at a new id every invocation.
      doomed_ids = conn.select_values(
        "SELECT id FROM events WHERE id NOT IN (#{keep.join(',')}) AND slug <> 'fuime-hq'"
      ).map(&:to_i)
      puts "Deleting #{doomed_ids.size} organisations, keeping #{keep.size} system organisations."

      # One TRUNCATE, not a DELETE per table: these tables reference each other
      # (fees -> canonical_event_mappings -> canonical_transactions, and back),
      # so no delete order satisfies every constraint. Truncating them together
      # in a single statement does, and deliberately WITHOUT CASCADE — if a
      # table outside this list references one inside it, Postgres names that
      # table in the error instead of quietly emptying it too.
      truncated = present = LEDGER_TABLES.select { |t| conn.table_exists?(t) }
      before = present.index_with { |t| sql_count(t) }
      conn.execute("TRUNCATE TABLE #{present.join(', ')} RESTART IDENTITY")
      before.each { |t, n| puts "  cleared #{t} (#{n})" if n.positive? }


      if doomed_ids.any?
        list = doomed_ids.join(",")

        statements = DEPENDENT_TABLES.filter_map do |table, fk, parent_table, parent_fk|
          next unless conn.table_exists?(table)

          sql = if parent_table
                  "DELETE FROM #{table} WHERE #{fk} IN (SELECT id FROM #{parent_table} WHERE #{parent_fk} IN (#{list}))"
                else
                  "DELETE FROM #{table} WHERE #{fk} IN (#{list})"
                end
          [table, sql]
        end

        statements += event_foreign_keys(excluding: truncated).map do |table, col|
          ["#{table}.#{col}", "DELETE FROM #{table} WHERE #{col} IN (#{list})"]
        end

        delete_until_settled(statements)

        conn.delete("DELETE FROM event_scoped_tags_events WHERE event_id IN (#{list}) OR event_scoped_tag_id IN (SELECT id FROM event_scoped_tags WHERE parent_event_id IN (#{list}))")
        conn.delete("DELETE FROM event_scoped_tags WHERE parent_event_id IN (#{list})")
        conn.delete("DELETE FROM event_affiliations WHERE affiliable_type = 'Event' AND affiliable_id IN (#{list})")
        conn.delete("DELETE FROM event_tags_events WHERE event_id IN (#{list})")
        conn.delete("DELETE FROM activities WHERE trackable_type = 'Event' AND trackable_id IN (#{list})")
        conn.delete("DELETE FROM activities WHERE recipient_type = 'Event' AND recipient_id IN (#{list})")
        conn.delete("DELETE FROM friendly_id_slugs WHERE sluggable_type = 'Event' AND sluggable_id IN (#{list})")
        conn.delete("DELETE FROM comments WHERE commentable_type = 'Event' AND commentable_id IN (#{list})")
        conn.execute("UPDATE events SET parent_id = NULL WHERE parent_id IN (#{list})")

        deleted = conn.delete("DELETE FROM events WHERE id IN (#{list})")
        puts "  deleted events (#{deleted})"
      end

      SYSTEM_EVENT_NAMES.each do |const, name|
        id = EventMappingEngine::EventIds.const_get(const)
        next unless conn.select_value("SELECT 1 FROM events WHERE id = #{id}")

        conn.execute(<<~SQL.squish)
          UPDATE events
             SET name = #{conn.quote(name)},
                 is_public = false,
                 hidden_at = COALESCE(hidden_at, NOW())
           WHERE id = #{id}
        SQL
      end
      # Applications that never became an organisation are not reachable through
      # any events foreign key, so the pass above leaves them behind — a draft
      # from testing, a rejection, something still under review. They are the
      # queue the admin console badges, and a fresh start means a clear queue.
      orphans = conn.delete("DELETE FROM event_applications WHERE event_id IS NULL")
      puts "  cleared unattached applications (#{orphans})" if orphans.positive?

      puts "  renamed and hid #{keep.size} system organisations"

      # `ledgers` is inside the truncate closure (Ledger belongs_to card_grant),
      # and Event has `after_create :create_ledger` — an organisation without a
      # primary ledger is a broken organisation. Restored after the deletes so
      # a fresh ledger row cannot block the event it belongs to from going.
      restored = conn.execute(<<~SQL.squish).cmd_tuples
        INSERT INTO ledgers (event_id, "primary", created_at, updated_at)
        SELECT e.id, TRUE, NOW(), NOW()
          FROM events e
         WHERE NOT EXISTS (SELECT 1 FROM ledgers l WHERE l.event_id = e.id)
      SQL
      puts "  restored #{restored} primary ledgers"
    end

    # Outside the transaction: Event creation runs callbacks (plan, config,
    # ledger, slug) that are easier to let the model do than to reproduce here.
    hq = Event.unscoped.find_by(slug: "fuime-hq")

    if hq
      puts "Fuime HQ already exists (##{hq.id})."
    else
      hq = Event.new(
        name: "Fuime HQ",
        slug: "fuime-hq",
        is_public: false,
        country: "US",
        point_of_contact: User.where.not(access_level: :user).order(:id).first
      )
      hq.save!
      puts "Created Fuime HQ (##{hq.id})."
    end

    if admin_email
      admin = User.find_by(email: admin_email)

      if admin.nil?
        puts "No user with email #{admin_email}; skipped the organizer position."
      elsif OrganizerPosition.exists?(event: hq, user: admin)
        puts "#{admin_email} is already on Fuime HQ."
      else
        # An OrganizerPosition validates that its invite exists, so the position
        # is created by accepting one rather than built directly — the same path
        # fuime_school.rake and db/seeds.rb take.
        invite = OrganizerPositionInvite.create!(event: hq, user: admin, sender: admin, role: :manager)

        invite.accept(show_onboarding: false)

        if OrganizerPosition.exists?(event: hq, user: admin)
          puts "Added #{admin_email} to Fuime HQ as a manager."
        else
          puts "Could not add #{admin_email}: #{invite.errors.full_messages.join('; ')}"
        end
      end
    end

    puts
    puts "Done. Organisations now: #{Event.unscoped.count} " \
         "(#{Event.unscoped.where.not(id: keep).count} real, #{keep.size} system)."
  end
end
