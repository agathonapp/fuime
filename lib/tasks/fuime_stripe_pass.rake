# frozen_string_literal: true

# The first end-to-end exercise of Fuime's Connect code against Stripe, in any mode.
#
# Everything in app/services/fuime was documentation-derived until this file ran —
# CLAUDE.md and docs/fuime/README.md both carry the warning. Each task below drives
# the REAL service (never a raw re-implementation), prints Stripe's actual response,
# and stops at the first failure in its own step so the parameter-shape bug is
# visible instead of buried.
#
#   rake fuime:stripe_pass:all          # the whole pass, in order
#   rake fuime:stripe_pass:status       # where things stand, resumable any time
#
# Order: setup -> onboard -> kyc -> charge -> card -> authorize -> freeze -> payout
#
# Test mode is enforced twice: the task refuses outside development, and it
# retrieves Stripe::Balance and aborts if livemode is ever true, regardless of env.
#
# The venture is guardian-backed (not a school) on purpose: it exercises the
# cards_enabled profile, where requirement_collection=application means the
# platform supplies KYC by API — the only profile that can be completed headlessly
# AND the only one that can issue cards. The school (institutional) path shares
# every call below except KYC, which Stripe collects itself in that profile.

namespace :fuime do
  namespace :stripe_pass do
    SLUG = "stripe-pass-venture"

    def sp_abort_unless_test!
      abort "development only" unless Rails.env.development?
      bal = Stripe::Balance.retrieve({}, { api_key: StripeService.secret_key })
      abort "!! livemode=true — refusing to continue" if bal.livemode
    end

    def sp_venture  = Event.find_by!(slug: SLUG)
    def sp_teen     = User.find_by!(email: "pass-teen@fuime.test")
    def sp_guardian = User.find_by!(email: "pass-guardian@fuime.test")
    def sp_opts     = { api_key: StripeService.secret_key }
    def sp_acct_id  = sp_venture.stripe_connected_account&.stripe_id

    def sp_step(name)
      puts "\n── #{name} " + "─" * (60 - name.length)
      yield
    rescue Stripe::StripeError => e
      puts "  ✗ Stripe rejected it: #{e.class}"
      puts "    #{e.message}"
      puts "    param: #{e.param}" if e.respond_to?(:param) && e.param
      abort "  Fix the parameter shape, then re-run this task."
    end

    desc "1. Local records: guardian, teen, guardianship, venture"
    task setup: :environment do
      sp_abort_unless_test!
      sp_step("setup") do
        guardian = User.find_by(email: "pass-guardian@fuime.test") ||
                   User.create!(email: "pass-guardian@fuime.test", full_name: "Pat Guardian",
                                birthday: 40.years.ago.to_date, verified: true)
        teen = User.find_by(email: "pass-teen@fuime.test") ||
               User.create!(email: "pass-teen@fuime.test", full_name: "Terry Teen",
                            birthday: 15.years.ago.to_date, verified: true)

        unless Guardianship.exists?(guardian:, minor: teen)
          Guardianship.create!(guardian:, minor: teen, status: :active)
        end

        venture = Event.find_by(slug: SLUG) ||
                  Event.create!(name: "Stripe Pass Venture", slug: SLUG,
                                can_front_balance: true, is_public: false)

        unless venture.organizer_positions.exists?(user: teen)
          OrganizerPositionInvite.create!(event: venture, user: teen, sender: teen, role: :manager)
                                 .accept(show_onboarding: false)
        end

        puts "  ✓ #{venture.name} — teen #{teen.email} (#{teen.age}), guardian #{guardian.email}"
      end
    end

    # Default is payments_only because the cards_enabled profile requests the
    # card_issuing capability, and Stripe refuses that until the PLATFORM is
    # onboarded onto Issuing — which for "businesses on your platform" is gated
    # behind a Stripe sales conversation, even in test mode (verified 2026-08-05;
    # the first-ever run of this task died there). Re-run with PROFILE=cards_enabled
    # once Stripe activates platform Issuing.
    desc "2. Create the connected account — first ever Stripe write (PROFILE=payments_only|cards_enabled)"
    task onboard: :environment do
      sp_abort_unless_test!
      profile = ENV.fetch("PROFILE", "payments_only").to_sym
      sp_step("onboard (#{profile})") do
        # A previous run that died at Stripe::Account.create leaves a local row
        # with a nil stripe_id. Retrying under a different profile would then trip
        # verify_existing_profile! over a record that corresponds to nothing at
        # Stripe — safe to discard, since no Stripe object was ever created.
        stale = sp_venture.stripe_connected_account
        if stale && stale.stripe_id.blank? && stale.controller_profile != profile.to_s
          puts "  · discarding stale local row (nil stripe_id, profile=#{stale.controller_profile})"
          stale.destroy!
          sp_venture.reload
        end

        service = Fuime::ConnectOnboardingService.new(
          event: sp_venture, guardian: sp_guardian, profile:
        )
        record = service.find_or_create_account!
        puts "  ✓ connected account #{record.stripe_id}"
        puts "    profile: #{record.controller_profile}"
        puts "    currently due: #{record.requirements_currently_due.inspect}"
      end
    end

    desc "3a. payments_only: prefill identity + bank by API; ToS stays with the guardian"
    task prefill: :environment do
      sp_abort_unless_test!
      sp_step("prefill (Stripe-collected profile)") do
        # Empirical boundary, established the first time this ran (2026-08-05):
        # on requirement_collection=stripe accounts the platform MAY prefill
        # individual.* and business_profile.* and attach an external account, but
        # Stripe refuses tos_acceptance — only the account holder can agree, in
        # the embedded component. So after this task exactly one requirement
        # remains, and it is the guardian's, at /:slug/payments/setup.
        Stripe::Account.update(
          sp_acct_id,
          {
            business_profile: { mcc: "5945", url: "https://fuime.com/b/#{SLUG}",
                                product_description: "Teen-run venture (Fuime stripe pass)",
                                support_phone: "0000000000" },
            individual: { first_name: "Pat", last_name: "Guardian", email: sp_guardian.email,
                          phone: "0000000000", ssn_last_4: "0000",
                          dob: { year: 1901, month: 1, day: 1 },
                          address: { line1: "address_full_match", city: "South San Francisco",
                                     state: "CA", postal_code: "94080", country: "US" } }
          },
          sp_opts
        )
        Stripe::Account.create_external_account(
          sp_acct_id,
          { external_account: { object: "bank_account", country: "US", currency: "usd",
                                routing_number: "110000000", account_number: "000123456789" } },
          sp_opts
        )
        acct = Stripe::Account.retrieve(sp_acct_id, sp_opts)
        sp_venture.stripe_connected_account.sync_from_stripe!(acct)
        puts "  ✓ prefilled; still due: #{acct.requirements.currently_due.inspect}"
        puts "    → the guardian finishes ToS in the embedded flow: /#{SLUG}/payments/setup"
      end
    end

    desc "3b. cards_enabled only: KYC through RequirementCollectionService"
    task kyc: :environment do
      sp_abort_unless_test!
      sp_step("kyc via RequirementCollectionService") do
        service = Fuime::RequirementCollectionService.new(event: sp_venture, guardian: sp_guardian)
        puts "  due before: #{service.outstanding_requirements.inspect}"

        # Stripe's published test-mode identity values: dob 1901-01-01 and
        # id_number 000000000 verify successfully.
        service.submit!(
          details: {
            first_name: "Pat", last_name: "Guardian",
            email: sp_guardian.email, phone: "0000000000",
            id_number: "000000000",
            dob: { year: 1901, month: 1, day: 1 },
            address: { line1: "address_full_match", city: "South San Francisco",
                       state: "CA", postal_code: "94080", country: "US" }
          },
          verification_method: GuardianVerification::ID_AND_DATABASE,
          consent_ip: "127.0.0.1", consent_user_agent: "fuime:stripe_pass"
        )
        puts "  ✓ submit! accepted"
      end

      sp_step("supplement (fields the service does not yet send)") do
        # FINDING, not a workaround to hide: RequirementCollectionService sends only
        # `individual.*`. An application-collected account also owes tos_acceptance,
        # business_profile.{mcc,url}, and an external account before payouts. If this
        # step is what makes the account active, these belong in the service.
        Stripe::Account.update(
          sp_acct_id,
          {
            business_profile: { mcc: "5945", url: "https://fuime.com/b/#{SLUG}",
                                product_description: "Teen-run venture (Fuime stripe pass)" },
            tos_acceptance: { date: Time.current.to_i, ip: "127.0.0.1" }
          },
          sp_opts
        )
        Stripe::Account.create_external_account(
          sp_acct_id,
          { external_account: { object: "bank_account", country: "US", currency: "usd",
                                routing_number: "110000000", account_number: "000123456789" } },
          sp_opts
        )
        acct = Stripe::Account.retrieve(sp_acct_id, sp_opts)
        sp_venture.stripe_connected_account.sync_from_stripe!(acct)
        puts "  ✓ supplemented; still due: #{acct.requirements.currently_due.inspect}"
        puts "    charges_enabled=#{acct.charges_enabled} payouts_enabled=#{acct.payouts_enabled}"
      end
    end

    desc "4. Money IN: direct charge on the connected account -> Fuime ledger"
    task charge: :environment do
      sp_abort_unless_test!
      intent = nil
      sp_step("direct charge (test card)") do
        intent = Stripe::PaymentIntent.create(
          {
            amount: 25_00, currency: "usd",
            payment_method: "pm_card_visa", confirm: true,
            automatic_payment_methods: { enabled: true, allow_redirects: "never" },
            description: "Stripe pass — first real money-in",
            metadata: { fuime_event_id: sp_venture.id }
          },
          sp_opts.merge(stripe_account: sp_acct_id)
        )
        puts "  ✓ #{intent.id} #{intent.status} — $#{intent.amount / 100.0} on #{sp_acct_id}"
        abort "  payment did not succeed" unless intent.status == "succeeded"
      end

      sp_step("record into the ledger (ConnectPaymentRecorder)") do
        Fuime::ConnectPaymentRecorder.new(event: sp_venture)
                                     .record_payment(object: intent, amount_cents: intent.amount)
        ct = CanonicalTransaction.where("memo ILIKE ?", "%stripe pass%").order(:id).last ||
             CanonicalTransaction.order(:id).last
        puts "  ✓ ledger line: ct##{ct.id} \"#{ct.memo}\" $#{ct.amount_cents / 100.0}"
        puts "    venture balance now: $#{sp_venture.reload.balance_v2_cents / 100.0}"
      end
    end

    desc "5. Cards: cardholder + virtual card through CardIssuingService"
    task card: :environment do
      sp_abort_unless_test!
      sp_step("cardholder + card (create_stripe_card path, first ever run)") do
        issuing = Fuime::CardIssuingService.new(event: sp_venture)
        holder = issuing.find_or_create_cardholder!(
          user: sp_teen, role: "teen",
          billing_address: { line1: "1 Founder Way", city: "Austin",
                             state: "TX", postal_code: "78701", country: "US" },
          phone_number: "+15555550100",
          terms_ip: "127.0.0.1", terms_user_agent: "fuime:stripe_pass"
        )
        puts "  ✓ cardholder #{holder.stripe_id} (#{sp_teen.age}yo — floor is 13)"

        card = issuing.issue_card!(cardholder: holder, spending_limit_cents: 100_00)
        puts "  ✓ card #{card.stripe_id} — ****#{card.last4}, limit $#{card.spending_limit}"
        puts "    allowlist on card: #{card.allowed_categories_present? rescue 'see model'}"
      end
    end

    desc "6. Authorizations: allowed category approves, banned category declines"
    task authorize: :environment do
      sp_abort_unless_test!
      card = VentureCard.joins(:venture_cardholder).where(venture_cardholders: { event_id: sp_venture.id }).last ||
             VentureCard.last
      abort "no card — run fuime:stripe_pass:card first" if card&.stripe_id.blank?

      sp_step("authorization in an ALLOWED category (hardware_stores)") do
        auth = Stripe::TestHelpers::Issuing::Authorization.create(
          { card: card.stripe_id, amount: 12_00,
            merchant_data: { category: "hardware_stores", name: "Test Hardware" } },
          sp_opts.merge(stripe_account: sp_acct_id)
        )
        puts "  #{auth.approved ? '✓ APPROVED' : '✗ declined'} — #{auth.id}"
      end

      sp_step("authorization in a BANNED category (fast_food_restaurants)") do
        auth = Stripe::TestHelpers::Issuing::Authorization.create(
          { card: card.stripe_id, amount: 8_00,
            merchant_data: { category: "fast_food_restaurants", name: "Test Burgers" } },
          sp_opts.merge(stripe_account: sp_acct_id)
        )
        puts "  #{auth.approved ? '✗✗ APPROVED — THE ALLOWLIST IS NOT ON THE CARD' : '✓ declined, as the policy requires'}"
      end
    end

    desc "7. Freeze/unfreeze through CardIssuingService, verified at Stripe"
    task freeze: :environment do
      sp_abort_unless_test!
      card = VentureCard.joins(:venture_cardholder).where(venture_cardholders: { event_id: sp_venture.id }).last
      abort "no card" if card&.stripe_id.blank?
      issuing = Fuime::CardIssuingService.new(event: sp_venture)

      sp_step("freeze") do
        issuing.freeze_card!(card)
        remote = Stripe::Issuing::Card.retrieve(card.stripe_id, sp_opts.merge(stripe_account: sp_acct_id))
        puts "  ✓ Stripe says status=#{remote.status} (want inactive)"
      end
      sp_step("unfreeze") do
        issuing.unfreeze_card!(card)
        remote = Stripe::Issuing::Card.retrieve(card.stripe_id, sp_opts.merge(stripe_account: sp_acct_id))
        puts "  ✓ Stripe says status=#{remote.status} (want active)"
      end
    end

    desc "8. Money OUT: teen requests, guardian approves, Stripe payout created"
    task payout: :environment do
      sp_abort_unless_test!
      sp_step("payout request + guardian approval (PayoutService)") do
        service = Fuime::PayoutService.new(event: sp_venture)
        request = service.request!(amount_cents: 10_00, requested_by: sp_teen)
        puts "  ✓ requested $#{request.amount_cents / 100.0} by #{sp_teen.email}"
        service.approve!(request: request, approver: sp_guardian)
        request.reload
        puts "  ✓ approved by guardian — stripe payout: #{request.try(:stripe_payout_id) || request.inspect[0, 120]}"
      end
    end

    desc "Where things stand"
    task status: :environment do
      sp_abort_unless_test!
      acct = sp_venture.stripe_connected_account
      if acct&.stripe_id.blank?
        puts "no connected account yet — start at fuime:stripe_pass:setup"
      else
        remote = Stripe::Account.retrieve(acct.stripe_id, sp_opts)
        puts "account:  #{acct.stripe_id} (#{acct.controller_profile})"
        puts "charges:  #{remote.charges_enabled}  payouts: #{remote.payouts_enabled}"
        puts "due:      #{remote.requirements.currently_due.inspect}"
        puts "balance:  $#{sp_venture.balance_v2_cents / 100.0} (Fuime ledger)"
        puts "cards:    #{VentureCard.joins(:venture_cardholder).where(venture_cardholders: { event_id: sp_venture.id }).count}"
      end
    end

    desc "The whole pass"
    task all: [:setup, :onboard, :kyc, :charge, :card, :authorize, :freeze, :payout, :status]
  end
end
