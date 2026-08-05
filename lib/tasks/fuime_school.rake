# frozen_string_literal: true

# Stands up a school inside the existing HCB org tree, so the Alpha School flow
# can be clicked through on the real app instead of a mockup.
#
#   School  -> Event (no parent)        the main org. Policy and funding live here.
#   Student -> Event (parent: school)   one sub org each, holding their subledger.
#
# Neither level is a new concept: Event#parent_id, Event#subevents and the
# recursive traversal in app/models/event.rb already do this, and
# OrganizerPosition.role_at_least? already resolves roles through ancestors.
#
# Who sees what, and why:
#
#   business office  manager on the school -> cascades to every student sub org
#   guide            manager on the school -> same cascade: watch, and step in
#   student          member on their own sub org only
#
# Guides sit in the PARENT org and see down the tree. This is oversight, not an
# approval workflow — students already hold cards and transact freely; a guide
# needs to be able to look, and to freeze, just in case. That is exactly what
# OrganizerPosition.role_at_least? already does with a manager position on an
# ancestor, so it needs no new code.
#
# The tradeoff, stated so it is a choice: every guide can see every student in the
# school. Fine for break-glass oversight at one school; if guides should only see
# their own students, pass `cohorts=true` to insert a middle Event layer and the
# same cascade narrows to one cohort.
#
# This task does NOT create CardGrants. CardGrant has after_create
# :transfer_money and after_create_commit :send_email, so seeding them fires
# disbursements and mail. Create one from the UI — clicking it is the test.
#
# Nothing here touches Stripe.

namespace :fuime do
  # Deliberately NOT a hand-written list. Fuime::CardSpendPolicy already holds the
  # allowlist, and its own header explains why typing slugs from memory is a trap:
  # several are easy to get subtly wrong, an invalid category makes the whole Stripe
  # Card create call fail, and card_grants.category_lock is free text that validates
  # nothing — so a typo produces a lock matching nothing rather than an error.
  #
  # That list is sourced from app/services/breakdown_engine/categorizer.rb, upstream
  # code already running against Stripe's real category enum, which makes it the only
  # verified source of category slugs in the repo.
  def school_allowed_categories
    Fuime::CardSpendPolicy.allowed_categories
  end

  def school_slug(*parts)
    parts.join("-").downcase.gsub(/[^a-z0-9]+/, "-").gsub(/(\A-|-\z)/, "")
  end

  # Birthdays land students at 14-16. Alpha is 13+, which keeps them above
  # Stripe's Issuing cardholder floor and out of COPPA entirely.
  def find_or_create_school_user!(email:, name:, birthday: nil)
    existing = User.find_by(email:)
    return existing if existing

    # verified: true is required, not cosmetic. OrganizerPosition's
    # user_must_be_verified validation refuses to create a position for an
    # unverified user, and OrganizerPositionInvite#accept refuses too.
    User.create!(email:, full_name: name, birthday:, verified: true)
  rescue ActiveRecord::RecordInvalid => e
    warn "  ! #{email}: #{e.record.errors.full_messages.join("; ")}"
    nil
  end

  # OrganizerPosition cannot be created directly: it declares
  # `has_one :organizer_position_invite, required: true`, so a bare create! fails
  # with "invite must exist". Positions are made by accepting an invite, which is
  # what db/seeds.rb does and what the real UI does. #accept builds the position,
  # carrying the invite's role across.
  def grant_position!(event:, user:, role:, sender: nil)
    return if user.nil?
    return if event.organizer_positions.exists?(user:)

    invite = OrganizerPositionInvite.create!(
      event:,
      user:,
      sender: sender || user,
      role:
    )

    return if invite.accept(show_onboarding: false)

    warn "  ! #{user.email} -> #{event.slug} (#{role}): #{invite.errors.full_messages.join("; ")}"
  rescue ActiveRecord::RecordInvalid => e
    warn "  ! #{user.email} -> #{event.slug} (#{role}): #{e.record.errors.full_messages.join("; ")}"
  end

  def find_or_create_school_event!(name:, slug:, parent: nil, managers: [])
    event = Event.find_by(slug:) || Event.create!(
      name:,
      slug:,
      parent:,
      # Dev-mode convenience, mirroring db/seeds.rb: without it a disbursement
      # down the tree waits on settled funds no test-mode balance has.
      can_front_balance: true,
      is_public: false
    )

    Array(managers).compact.each do |manager|
      grant_position!(event:, user: manager, role: :manager)
    end

    event
  end

  ROSTER = [
    ["Naomi Okafor",     "Resin jewelry",       "Marisol Reyes"],
    ["Dev Raman",        "3D-printed parts",    "Marisol Reyes"],
    ["Marcus Bell",      "Sneaker resale",      "Marisol Reyes"],
    ["Priya Venkatesan", "Tutoring collective", "Marisol Reyes"],
    ["Ethan Cho",        "Screen-printed tees", "Tobias Lund"],
    ["Sofia Delgado",    "Dog walking",         "Tobias Lund"],
    ["Jonah Adeyemi",    "Custom keycaps",      "Tobias Lund"],
    ["Lena Fitzgerald",  "Zine printing",       "Tobias Lund"]
  ].freeze

  desc "Seed a school main org with one sub org per student (args: school_name, student_count, cohorts)"
  task :seed_school, [:school_name, :student_count, :cohorts] => :environment do |_t, args|
    abort "Refusing to run outside development/test." unless Rails.env.development? || Rails.env.test?

    school_name  = args[:school_name].presence || "Alpha School — Austin"
    count        = (args[:student_count].presence || 8).to_i
    use_cohorts  = args[:cohorts].to_s == "true"
    domain       = "#{school_slug(school_name)}.test"

    ActiveRecord::Base.transaction do
      office = find_or_create_school_user!(email: "business-office@#{domain}", name: "Dana Whitfield")
      abort "Could not create the business office user; aborting." unless office

      guides = ROSTER.first((args[:student_count].presence || 8).to_i).map(&:last).uniq.index_with do |guide_name|
        find_or_create_school_user!(
          email: "#{school_slug(guide_name)}@#{domain}",
          name:  guide_name
        )
      end

      # Guides are managers on the main org alongside the business office, so the
      # ancestor cascade gives them read + freeze over every student sub org
      # without a position per student.
      school = find_or_create_school_event!(
        name: school_name,
        slug: school_slug(school_name),
        managers: [office] + guides.values
      )
      puts "\nMain org: #{school.name}  (/#{school.slug})"
      puts "  business office: #{office.email} — manager"
      guides.each_value { |g| puts "  guide: #{g&.email} — manager, watches every sub org" }

      # Policy lives on the main org, once. CardGrant::InheritablePolicy resolves
      # it down the tree: bans union upward so a school ban cannot be undone
      # below, allowlists intersect so a guide can only ever narrow. Without that
      # concern this setting would never reach a single student's grant.
      policy = CardGrantSetting.find_or_initialize_by(event: school)
      policy.category_lock     = school_allowed_categories.join(", ")
      policy.save!
      puts "  policy: #{school_allowed_categories.size} allowed categories (Fuime::CardSpendPolicy)"

      # Optional middle layer, narrowing each guide to their own students.
      cohorts = {}
      if use_cohorts
        guides.each_with_index do |(guide_name, guide), i|
          cohort_name = "Workshop #{i + 1}"
          cohorts[guide_name] = find_or_create_school_event!(
            name: cohort_name,
            slug: school_slug(school_name, cohort_name),
            parent: school,
            managers: [guide]
          )
          puts "  cohort: #{cohort_name} — guide #{guide&.email}"
        end
      end

      puts "\nSub orgs"
      ROSTER.first(count).each_with_index do |(student_name, venture_name, guide_name), i|
        student = find_or_create_school_user!(
          email:    "#{school_slug(student_name)}@#{domain}",
          name:     student_name,
          birthday: (14 + (i % 3)).years.ago.to_date
        )
        next unless student

        guide  = guides[guide_name]
        parent = cohorts[guide_name] || school

        # No positions needed here for guides either way — they hold manager on an
        # ancestor (the school, or their cohort) and the cascade covers this org.
        venture = find_or_create_school_event!(
          name: "#{venture_name} — #{student_name}",
          slug: school_slug(school_name, student_name),
          parent:
        )

        # The student is a member of their own sub org, invited by their guide.
        grant_position!(event: venture, user: student, role: :member, sender: guide)

        puts "  #{venture_name} — #{student_name} (#{14 + (i % 3)})  /#{venture.slug}  guide: #{guide_name}"
      end
    end

    puts <<~NEXT

      ── Verify, in this order ──────────────────────────────────────────
      1. Sign in as marisol-reyes@#{domain} (guide).
         Every student sub org, with freeze available on each — oversight via the
         ancestor cascade, no position per student. #{use_cohorts ? "Cohorts are on, so this\n         guide sees only their own cohort; open another cohort's student to confirm." : "Re-run with cohorts=true if\n         guides should only see their own students."}

      2. Sign in as naomi-okafor@#{domain} (student).
         Her own sub org only. Open another student's slug directly — it must not
         load. This is the property the whole model rests on.

      3. Sign in as business-office@#{domain}.
         Every sub org, same cascade.

         Steps 1-3 are already verified at the model layer:
         role_at_least? gives the guide manager on every sub org, the student
         member on their own and nothing on anyone else's. What you are checking
         here is that the CONTROLLERS and VIEWS honour it too.

      4. As a guide, create a card grant on a student's sub org, then check
         its usage restrictions page. The school's #{school_allowed_categories.size} allowed categories
         should appear WITHOUT having been set on the student's org. If they are
         empty, policy inheritance is broken and the card is unrestricted.

      5. Still on that grant, try adding a category the school never allowed.
         It must not take effect. Union semantics used to let it.

      Steps 1-3 and 5 touch no external service. Step 4's card activation is the
      first thing that reaches Stripe, and it never has.
    NEXT
  end
end

namespace :fuime do
  # Fabricates VIRTUAL StripeCard rows so the parent org's roster — the freeze
  # control and the card count — can be looked at without Stripe.
  #
  # This exists because create_stripe_card has never run against Stripe in any
  # mode, so there is no other way to see the oversight UI in a browser. Virtual
  # is not an arbitrary choice: stripe_card_personalization_design_id and the
  # stripe_shipping_* fields are both required `unless virtual?`, so a virtual
  # card is the only shape that can be built without inventing a personalization
  # design and a mailing address too.
  #
  # The stripe_ids are deliberately prefixed "ic_FAKE_" so no one, and nothing,
  # mistakes these for cards that exist at Stripe. They will not authorize, they
  # will not appear in any Stripe dashboard, and freezing one updates only this
  # database — the point is to verify our own UI and policy wiring.
  desc "Fabricate fake virtual cards on a school's student sub orgs (dev only)"
  task :seed_school_cards, [:school_slug] => :environment do |_t, args|
    abort "Refusing to run outside development." unless Rails.env.development?

    school = Event.find_by(slug: args[:school_slug].presence || "founders-school")
    abort "School not found. Run fuime:seed_school first." if school.nil?

    created = 0

    school.subevents.each_with_index do |venture, i|
      if venture.stripe_cards.any?
        puts "  = #{venture.name} already has a card"
        next
      end

      student = venture.organizer_positions.first&.user
      if student.nil?
        warn "  ! #{venture.name} has no organizer to hold a card"
        next
      end

      cardholder = StripeCardholder.find_or_initialize_by(user: student)
      cardholder.stripe_id ||= "ich_FAKE_#{venture.id}"
      unless cardholder.save
        warn "  ! cardholder for #{student.email}: #{cardholder.errors.full_messages.join("; ")}"
        next
      end

      card = StripeCard.new(
        event: venture,
        stripe_cardholder: cardholder,
        card_type: "virtual",
        stripe_id: "ic_FAKE_#{venture.id}",
        stripe_brand: "Visa",
        stripe_exp_month: 12,
        stripe_exp_year: Date.current.year + 3,
        last4: format("%04d", 1000 + venture.id),
        # One frozen on purpose, so the roster shows both states side by side and
        # the Frozen/Freeze branch of the control partial is actually exercised.
        stripe_status: i.zero? ? "inactive" : "active",
        # StripeCard's `frozen` scope is stripe_status "inactive" AND
        # initially_activated, so without this the frozen one reads as
        # never-activated rather than as frozen.
        initially_activated: true
      )

      if card.save
        created += 1
        puts "  + #{venture.name} — •••• #{card.last4} (#{card.stripe_status})"
      else
        warn "  ! #{venture.name}: #{card.errors.full_messages.join("; ")}"
      end
    end

    puts "\n#{created} fake card(s) created. Open #{school.slug} -> Sub-organizations."
    puts "These are NOT real Stripe cards. Freezing one writes only to this database."
  end
end
