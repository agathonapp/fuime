# frozen_string_literal: true

# Fuime demo seed — a complete teen-business scenario for showing the platform.
#
#   bundle exec rails runner script/seed_demo_business.rb
#
# Creates a teen owner, their guardian, an ACTIVE signed guardianship between
# them, and an approved public business with storefront copy. Idempotent: it
# finds by email/slug, so re-running updates rather than duplicating.
#
# Deliberately does NOT:
#
#   * touch any pre-existing user or event — only the two demo accounts and the
#     one demo business below;
#   * fabricate ledger transactions. The storefront takes a real test-mode
#     Stripe payment, and a payment that actually flowed through the webhook is
#     a far better demo than invented rows (and CLAUDE.md Rule 3 keeps us out of
#     the ledger's internals).
#
# Mail is disabled for the run: several callbacks here send real mail
# (OrganizerPositionInvite#accept mails once an event has >1 organizer), and
# these demo mailboxes do not exist. `deliver_later` would otherwise be
# delivered by the *worker*, where a `perform_deliveries` flag set in this
# process does not apply — hence swapping the queue adapter too.

TEEN_EMAIL     = "maya.demo@fuime.com"
GUARDIAN_EMAIL = "parent.demo@fuime.com"
BUSINESS_SLUG  = "mayas-cookies"

ActionMailer::Base.perform_deliveries = false
ActiveJob::Base.queue_adapter = :test

def say(msg) = puts("[fuime-seed] #{msg}")

# `save!(validate: false)`: these records are assembled out of order (a
# guardianship before its agreement, a position before its invite), so the
# model's own validations would reject valid intermediate states.
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

guardian = upsert_user!(email: GUARDIAN_EMAIL, name: "Denise Okafor", birthday: 43.years.ago.to_date)
teen     = upsert_user!(email: TEEN_EMAIL,     name: "Maya Okafor",   birthday: 16.years.ago.to_date)

# The guardianship must be ACTIVE and signed, or the teen is barred from
# operating a business — which is the control working as intended, and would
# make the demo business unusable.
guardianship = Guardianship.find_or_initialize_by(guardian_id: guardian.id, minor_id: teen.id)
guardianship.status = :active
guardianship.agreement_signed_at ||= 3.weeks.ago
guardianship.agreement_version   ||= Guardianship::CURRENT_AGREEMENT_VERSION
guardianship.invite_token        ||= SecureRandom.hex(16)
guardianship.invite_sent_at      ||= 4.weeks.ago
save_unvalidated!(guardianship)
say "guardianship ##{guardianship.id} status=#{guardianship.status}"

business = Event.find_by(slug: BUSINESS_SLUG)
if business
  say "business ##{business.id} existed"
else
  business = Event.new(
    name: "Maya's Cookies",
    slug: BUSINESS_SLUG,
    plan: Event::Plan::Standard.new,
    country: "US"
  )
  save_unvalidated!(business)
  say "business ##{business.id} CREATED"
end

# The storefront reads the owner — and the "Guardian on account" badge — off
# `point_of_contact`, not off the organizer positions. Pointing it at an admin
# hides the badge and misstates who runs the business.
business.point_of_contact_id = teen.id

# `approved` is the aasm initial state; there is no `approved_at` column on
# events (that belongs to other models) — activation is `activated_at`.
business.aasm_state        = "approved"
business.activated_at    ||= 3.weeks.ago
business.is_public         = true
business.business_category = "food"
business.storefront_tagline = "Small-batch cookies, baked after school in Oakland."
business.public_message = <<~MD
  Hi! I'm Maya, I'm 16, and I've been baking since I was 11.

  Everything is made to order the same week you buy it. Brown butter chocolate
  chip is the one people keep coming back for. My mum co-signs this account
  with me.
MD
save_unvalidated!(business)

upsert_position!(user: teen,     event: business, role: :manager)
upsert_position!(user: guardian, event: business, role: :reader)

puts
say "=== SEEDOK ==="
say "business    /#{business.slug}   (##{business.id}, state=#{business.aasm_state})"
say "storefront  /b/#{business.slug}"
say "owner       #{teen.email} — may operate a business: #{teen.reload.permitted_to_operate_business?}"
say "guardian    #{guardian.email} (reader on the business)"
say "Those mailboxes do not receive mail. To sign in as them, use an admin"
say "account and impersonate, rather than requesting a login code."
