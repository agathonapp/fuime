# frozen_string_literal: true

# Fuime playground seed — a funded, sandboxed business to click around in.
#
#   bundle exec rails runner script/seed_playground_org.rb
#
# Playground Mode is upstream HCB's `Event#demo_mode` (the UI has said
# "Playground Mode" since 2022; the column was never renamed — CLAUDE.md Rule 6).
# It is not a global app mode: it is a per-org boolean that keeps an org
# readable while blocking everything that touches real money — account numbers,
# disbursements, invoices, check deposits, reimbursements, card actions. The
# ledger, balances, receipts, and comments all render normally, which is exactly
# what makes it safe to fill one with invented transactions.
#
# That is the split this script assumes, and why it is separate from
# script/seed_demo_business.rb:
#
#   mayas-cookies    real business, real test-mode Stripe money, no fake rows
#   fuime-playground playground org, fabricated ledger, never takes a payment
#
# Fake money belongs in the org that cannot move money. Idempotent: it finds by
# email/slug, and it will not fund an org that already has ledger lines.

PLAYGROUND_SLUG = "fuime-playground"
OWNER_EMAIL     = "maya.demo@fuime.com"     # shared with seed_demo_business.rb
GUARDIAN_EMAIL  = "parent.demo@fuime.com"   # so one login shows both orgs
BANK_IDENTIFIER = "FUIMEPLAYGROUND"         # tags these rows in the admin ledger

# Amounts in cents, teen-business scale. Net: +$634.50 in, -$216.62 out,
# leaving $417.88 on the ledger (less HCB's 7% revenue fee on income, which
# FeeEngine posts automatically — see the note at the bottom of this file).
LEDGER_LINES = [
  { days_ago: 24, memo: "🍪 Farmers market — Grand Lake booth", cents: 18_600 },
  { days_ago: 22, memo: "🛒 Restaurant Depot — flour, butter, chocolate", cents: -8_842 },
  { days_ago: 17, memo: "🎂 Birthday party order (3 dozen)", cents: 9_600 },
  { days_ago: 15, memo: "📦 Packaging boxes & stickers", cents: -6_120 },
  { days_ago: 10, memo: "🍪 Weekly cookie subscriptions", cents: 14_250 },
  { days_ago: 8, memo: "🎪 Farmers market booth fee", cents: -4_500 },
  { days_ago: 4, memo: "☕ Wholesale order — Ridge Coffee", cents: 21_000 },
  { days_ago: 3, memo: "🧾 Business cards", cents: -2_200 },
].freeze

# Several callbacks below send mail (an invite acceptance mails once an event
# has more than one organizer) and these demo mailboxes do not exist. The
# queue adapter has to be swapped too: `deliver_later` is delivered by the
# *worker*, where a `perform_deliveries` flag set in this process does nothing.
ActionMailer::Base.perform_deliveries = false
ActiveJob::Base.queue_adapter = :test

def say(msg) = puts("[fuime-playground] #{msg}")

# These records are assembled out of order (a position before its invite), so
# the models' own validations would reject valid intermediate states.
def save_unvalidated!(record) = record.save!(validate: false)

def upsert_user!(email:, name:, birthday:)
  user = User.find_or_initialize_by(email:)
  fresh = user.new_record?
  user.assign_attributes(full_name: name, birthday:, verified: true)
  save_unvalidated!(user)
  say "user #{email} ##{user.id} #{fresh ? 'CREATED' : 'existed'}"
  user
end

def upsert_position!(user:, event:, role:)
  position = OrganizerPosition.find_or_initialize_by(user_id: user.id, event_id: event.id)
  position.role = role
  position.deleted_at = nil
  save_unvalidated!(position)

  # `has_one :organizer_position_invite, required: true` — a position without
  # one fails validation everywhere it is later loaded.
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

# Feeds the ledger through its front door: a raw row, then the two importers
# that turn raw rows into canonical ones, then a mapping onto the org. This is
# the same path db/seeds.rb uses and touches no pipeline internals (Rule 3).
def fund!(event, lines)
  raws = lines.map do |line|
    ::RawCsvTransactionService::Create.new(
      unique_bank_identifier: BANK_IDENTIFIER,
      date: line[:days_ago].days.ago.iso8601(3),
      memo: line[:memo],
      # `amount` is monetized — it is dollars, not cents. Passing cents here
      # inflates every figure a hundredfold (db/seeds.rb's $8.9M "donation").
      # BigDecimal rather than Float so the division is exact.
      amount: BigDecimal(line[:cents]) / 100
    ).run
  end

  ::TransactionEngine::HashedTransactionService::RawCsvTransaction::Import.new.run
  ::TransactionEngine::CanonicalTransactionService::Import::All.new.run

  raws.each do |raw|
    # Resolved per-row rather than by `CanonicalTransaction.last` (the seeds'
    # trick), which only holds if nothing else imported in between.
    canonical = raw.reload.canonical_transaction
    raise "no canonical transaction for raw ##{raw.id}" if canonical.nil?

    CanonicalEventMapping.create!(canonical_transaction: canonical, event:)
  end
end

guardian = upsert_user!(email: GUARDIAN_EMAIL, name: "Denise Okafor", birthday: 43.years.ago.to_date)
owner    = upsert_user!(email: OWNER_EMAIL,    name: "Maya Okafor",   birthday: 16.years.ago.to_date)

# An ACTIVE signed guardianship, or the teen is barred from operating a
# business — the control working as intended, but it would leave the playground
# unusable. `find_or_initialize_by` so this shares one record with the demo seed.
guardianship = Guardianship.find_or_initialize_by(guardian_id: guardian.id, minor_id: owner.id)
guardianship.status = :active
guardianship.agreement_signed_at ||= 3.weeks.ago
guardianship.agreement_version   ||= Guardianship::CURRENT_AGREEMENT_VERSION
guardianship.invite_token        ||= SecureRandom.hex(16)
guardianship.invite_sent_at      ||= 4.weeks.ago
save_unvalidated!(guardianship)
say "guardianship ##{guardianship.id} status=#{guardianship.status}"

event = Event.find_by(slug: PLAYGROUND_SLUG)
if event
  say "org ##{event.id} existed"
else
  event = Event.new(slug: PLAYGROUND_SLUG, name: PLAYGROUND_SLUG, plan: Event::Plan::Standard.new, country: "US")
  save_unvalidated!(event)
  say "org ##{event.id} CREATED"
end

# The same teen's sandbox copy of her real business, so the invented ledger
# below reads as one story rather than a second unrelated company.
event.name = "Maya's Cookies (Playground)"
event.demo_mode = true

# `approved` is the aasm initial state; activation is `activated_at`, and a
# playground org is deliberately *not* activated — flipping demo_mode off is
# what stamps it (see the before_update in Event).
event.aasm_state = "approved"

# The storefront reads the owner and the "Guardian on account" badge off
# point_of_contact, not off the organizer positions.
event.point_of_contact_id = owner.id

# Not public: a playground org is a sandbox, and `indexable` excludes demo orgs
# anyway. Nothing here should surface on the marketing site.
event.is_public = false
event.business_category = "food"
event.storefront_tagline = "Sandbox org — every number below is invented."
save_unvalidated!(event)

upsert_position!(user: owner,    event:, role: :manager)
upsert_position!(user: guardian, event:, role: :reader)

if event.canonical_event_mappings.any?
  say "ledger already has #{event.canonical_event_mappings.count} lines — not funding again"
else
  fund!(event, LEDGER_LINES)
  say "funded with #{LEDGER_LINES.count} ledger lines"
end

event.reload

puts
say "=== SEEDOK ==="
say "org         /#{event.slug}   (##{event.id}, demo_mode=#{event.demo_mode})"
say "ledger      #{event.canonical_transactions.count} transactions"
say "balance     #{ActionController::Base.helpers.number_to_currency(event.balance_v2_cents / 100.0)}"
say "available   #{ActionController::Base.helpers.number_to_currency(event.balance_available_v2_cents / 100.0)}"
say "owner       #{owner.email} (manager)"
say "guardian    #{guardian.email} (reader)"
say "Those mailboxes do not receive mail. To sign in as them, use an admin"
say "account and impersonate, rather than requesting a login code."
say ""
say "The gap between balance and available is HCB's plan revenue fee (7% on"
say "income, posted by FeeEngine). Fuime's own 4% platform fee is a separate"
say "line the Stripe webhook posts, so a real sale is charged both today."
