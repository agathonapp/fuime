# Crash-test demo seed. Builds a realistic teen-business scenario so the
# crawler exercises pages with actual data rather than empty states.
require "securerandom"

def log(msg) = puts("[seed] #{msg}")

# --- Users -----------------------------------------------------------------
teen = User.find_or_initialize_by(email: "teen@fuime.test")
teen.assign_attributes(full_name: "Maya Okafor", birthday: 16.years.ago.to_date)
teen.save!(validate: false)
log "teen ##{teen.id}"

guardian = User.find_or_initialize_by(email: "guardian@fuime.test")
guardian.assign_attributes(full_name: "Ada Okafor", birthday: 44.years.ago.to_date)
guardian.save!(validate: false)
log "guardian ##{guardian.id}"

adult = User.find_or_initialize_by(email: "adult@fuime.test")
adult.assign_attributes(full_name: "Jordan Reyes", birthday: 22.years.ago.to_date)
adult.save!(validate: false)
log "adult ##{adult.id}"

# A minor with NO guardian — the gate case.
orphan = User.find_or_initialize_by(email: "noguardian@fuime.test")
orphan.assign_attributes(full_name: "Sam Nowak", birthday: 15.years.ago.to_date)
orphan.save!(validate: false)
log "unguarded minor ##{orphan.id}"

# --- Guardianship ----------------------------------------------------------
g = Guardianship.find_or_initialize_by(guardian_id: guardian.id, minor_id: teen.id)
g.status = :active if g.respond_to?(:status=)
g.agreement_signed_at ||= 1.month.ago
g.agreement_version ||= Guardianship::CURRENT_AGREEMENT_VERSION
g.invite_token ||= SecureRandom.hex(16)
g.save!(validate: false)
log "guardianship ##{g.id} status=#{g.status}"

# A pending invite, so the accept page has something to render.
pending_minor = User.find_or_initialize_by(email: "pendingteen@fuime.test")
pending_minor.assign_attributes(full_name: "Riley Chen", birthday: 14.years.ago.to_date)
pending_minor.save!(validate: false)
pg = Guardianship.find_or_initialize_by(guardian_id: adult.id, minor_id: pending_minor.id)
pg.status = :pending if pg.respond_to?(:status=)
pg.invite_token ||= SecureRandom.hex(16)
pg.invite_sent_at ||= 2.days.ago
pg.agreement_signed_at = nil
pg.save!(validate: false)
log "pending guardianship ##{pg.id} token=#{pg.invite_token}"

# --- Business (Event) ------------------------------------------------------
biz = Event.find_by(slug: "mayas-cookies")
unless biz
  biz = Event.new(
    name: "Maya's Cookies",
    slug: "mayas-cookies",
    plan: Event::Plan::Standard.new,
    country: "US",
    is_public: true
  )
  biz.point_of_contact_id = User.find_by(access_level: :admin)&.id
  biz.save!(validate: false)
end
biz.update_columns(approved_at: 2.months.ago) if biz.respond_to?(:approved_at) && biz.approved_at.nil?
log "business ##{biz.id} #{biz.slug}"

def position!(user, event, role)
  op = OrganizerPosition.find_or_initialize_by(user_id: user.id, event_id: event.id)
  op.role = role if op.respond_to?(:role=)
  op.deleted_at = nil
  op.save!(validate: false)
  unless op.organizer_position_invite
    inv = OrganizerPositionInvite.new(
      user_id: user.id, event_id: event.id, sender_id: user.id,
      organizer_position_id: op.id, accepted_at: Time.now, role: role
    )
    inv.save!(validate: false)
  end
  op
end

position!(teen, biz, :manager)
position!(guardian, biz, :reader)
log "positions wired"

# --- Money: a settled ledger line so transaction pages render ---------------
if defined?(CanonicalTransaction)
  ct = CanonicalTransaction.find_by(memo: "FUIME DEMO COOKIE SALE")
  unless ct
    ct = CanonicalTransaction.new(
      amount_cents: 4_500,
      date: 1.week.ago.to_date,
      memo: "FUIME DEMO COOKIE SALE",
      transaction_source_type: nil,
      hcb_code: "HCB-#{::TransactionGroupingEngine::Calculate::HcbCode::INVOICE_CODE rescue 400}-#{SecureRandom.hex(4)}"
    )
    ct.save!(validate: false)
  end
  begin
    CanonicalEventMapping.find_or_create_by!(canonical_transaction_id: ct.id, event_id: biz.id)
  rescue => e
    log "mapping skipped: #{e.class}: #{e.message}"
  end
  log "canonical txn ##{ct.id}"
end

puts "\n=== LOGIN TARGETS ==="
{ admin: User.find_by(access_level: :admin), teen:, guardian:, adult:, orphan: }.each do |k, u|
  puts "#{k}: #{u.email} (id=#{u.id})" if u
end
puts "business slug: #{biz.slug} (id=#{biz.id})"
puts "pending guardian invite token: #{pg.invite_token}"
