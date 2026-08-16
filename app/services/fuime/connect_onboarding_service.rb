# frozen_string_literal: true

# Fuime: create and drive the guardian-owned Stripe account for a venture.
#
# This is the service that replaces the pooled-account model. Instead of every
# payment landing in Fuime's own Stripe balance (money transmission in
# production — CLAUDE.md L1), each venture gets a connected account that the
# guardian legally owns. Stripe holds the funds and settles them to the family;
# Fuime takes a platform fee on each charge and is never in the flow of funds.
#
# ── Why this exact account configuration ──────────────────────────────────────
#
# `controller.losses.payments = stripe` is the whole point: Stripe, not Fuime,
# is liable when a connected account cannot cover a negative balance. Fuime is a
# pre-launch company whose users are minors; it cannot absorb chargeback losses.
#
# That choice then forces the rest, because Stripe documents these as
# incompatible: `requirement_collection = application` cannot be combined with
# `losses.payments = stripe`. So requirement collection is Stripe's, which is
# also a privacy win — the guardian's SSN and identity documents go to Stripe and
# never touch Fuime's database.
#
# `stripe_dashboard.type = none` keeps the guardian inside Fuime rather than
# handing them off to a Stripe dashboard. This combination (Stripe-liable, Stripe-
# collected, no dashboard) is permitted and is Stripe's own recommended default
# for platforms new to embedding payments.
#
# ── The consequence to be aware of ───────────────────────────────────────────
#
# Because requirement collection is Stripe's, onboarding MUST use Connect
# embedded components (Account Links cannot serve this configuration for
# updates), and the guardian will hit one Stripe-owned authentication popup
# inside the otherwise-embedded flow. That popup cannot be disabled — the flag
# that would (`disable_stripe_user_authentication`) requires
# `requirement_collection = application`, which would mean owning every loss.
# The trade is correct; the flow's copy warns the guardian in advance so it reads
# as a security step rather than a glitch.
#
# ── API key handling, deliberately explicit ──────────────────────────────────
#
# Every call passes `api_key:` rather than relying on the global `Stripe.api_key`.
# That global is set in config/initializers/stripe.rb from
# `Rails.env.production? ? :live : :test`, which does NOT consult
# `StripeService.mode`. In production with STRIPE_MODE=test — the current and
# intended posture — the global key is the LIVE one. Creating a connected account
# under it would produce a real, live Stripe account for a minor's business while
# every screen in the app says "test mode". Passing the key explicitly is the
# difference between those two outcomes.
module Fuime
  class ConnectOnboardingService
    class UnknownProfile < StandardError; end
    class OnboardingPathNotImplemented < StandardError; end
    class AccountNotProvisioned < StandardError; end

    # ── Embedded component sets ─────────────────────────────────────────────
    #
    # Fuime's product promise is that a family never opens stripe.com. That is
    # only true if every routine thing a Stripe Dashboard would be needed for has
    # an embedded equivalent inside Fuime, so these two constants are effectively
    # the list of Dashboard trips the product has eliminated.
    #
    # Split into two sets because the two surfaces have different jobs and
    # different risks. Onboarding is a one-shot form; management is a long-lived
    # page a guardian returns to, where enabling the wrong feature would hand
    # them a control that silently defeats a Fuime rule.

    ONBOARDING_COMPONENTS = {
      account_onboarding: {
        enabled: true,
        features: {
          # The guardian connects their own bank here, in the same sitting.
          # Without it Stripe collects identity but not a payout destination, and
          # the family finishes "setup" with money that can never reach them.
          external_account_collection: true
        }
      },
      # Required alongside onboarding for this configuration: the notification
      # banner is how Stripe reaches the guardian when re-verification is needed.
      # Without it a venture can go dead with no in-product explanation.
      notification_banner: {
        enabled: true,
        features: { external_account_collection: true }
      },
      account_management: {
        enabled: true,
        features: { external_account_collection: true }
      }
    }.freeze

    MANAGEMENT_COMPONENTS = {
      # "Something needs your attention", surfaced by Stripe itself. The single
      # most important component on the page: it is the only thing that knows a
      # document expired or a review opened before the account goes dark.
      notification_banner: {
        enabled: true,
        features: { external_account_collection: true }
      },
      # Business details, representative details, and the connected bank account.
      # This is the component that replaces the Stripe Dashboard's settings pages.
      account_management: {
        enabled: true,
        features: { external_account_collection: true }
      },
      # Balance, payout history, and the bank account money lands in.
      #
      # ⚠️ The two `false` flags below are load-bearing Fuime rules, not defaults:
      #
      #   standard_payouts / instant_payouts: false
      #     Turning these on would put a "Pay out now" button in front of the
      #     guardian. They own the account, so Stripe would allow it — but it
      #     would route money out AROUND Fuime's PayoutRequest flow, which is the
      #     one control that makes "the teen asks, the adult decides" an audited
      #     record rather than a story. Read-only here means Fuime's approval gate
      #     is the only door, and every payout has a request behind it.
      #
      #   edit_payout_schedule: false
      #     ConnectOnboardingService creates every account on a MANUAL payout
      #     schedule precisely so nothing leaves until an adult decides it should.
      #     A guardian who flipped this to "automatic daily" would drain the
      #     balance on a timer and make the approval gate decorative — while every
      #     screen in Fuime continued to describe a gate that no longer existed.
      payouts: {
        enabled: true,
        features: {
          instant_payouts: false,
          standard_payouts: false,
          edit_payout_schedule: false,
          external_account_collection: true
        }
      },
      # Stripe's own 1099/tax documents for the account holder. A guardian who
      # cannot reach these has to open a Dashboard in January, which is exactly
      # the trip this whole file exists to remove.
      documents: { enabled: true }
    }.freeze

    # ── Account configuration profiles ──────────────────────────────────────
    #
    # `controller` is CREATE-ONLY: Stripe's Account update endpoint accepts no
    # controller parameters, and Stripe says a platform needing different ones
    # "must create new accounts to use Issuing or Treasury for platforms." So this
    # is the one decision about a venture's Stripe account that can never be
    # revised. A venture cannot be upgraded into card support; it re-onboards.
    #
    # Two profiles exist because supporting cards costs three architectural
    # reversals, and making every family pay them so that some families can have a
    # card is the wrong trade. `controller` being per-account is what makes a mixed
    # fleet conceivable at all.
    #
    # ⚠️ THE MIXED FLEET IS AN INFERENCE, NOT A DOCUMENTED STRIPE PATTERN.
    # Whether "platforms under Stripe-liability cannot use Issuing" is a
    # platform-wide or per-connected-account restriction is ambiguous in Stripe's
    # docs. See docs/fuime/LEGAL_RESEARCH.md, "Three questions for Stripe, before
    # any card code is written" — question 2 is exactly this. If the answer is
    # "platform-wide", `:cards_enabled` cannot work alongside `:payments_only` and
    # this whole approach collapses back to an all-or-nothing choice.
    PROFILES = {
      # Today's posture, and the default for every venture. Stripe carries the
      # loss risk, Stripe collects the identity documents (so the guardian's SSN
      # never touches Fuime), and the venture pays Stripe's processing fees.
      payments_only: {
        controller: {
          losses: { payments: "stripe" },
          fees: { payer: "account" },
          requirement_collection: "stripe",
          stripe_dashboard: { type: "none" }
        },
        capabilities: {
          card_payments: { requested: true },
          transfers: { requested: true }
        }
      }.freeze,

      # The card cohort. Every one of these three changes is a real cost, not a
      # config detail, and they travel together because Stripe documents them as
      # mutually required with Issuing:
      #
      #   losses.payments = application
      #     FUIME ABSORBS EVERY NEGATIVE BALANCE on this venture. A chargeback a
      #     teenager cannot cover is Fuime's loss.
      #   requirement_collection = application
      #     THE GUARDIAN'S SSN AND ID DOCUMENTS LAND IN FUIME'S SYSTEMS, reversing
      #     the privacy position that made `stripe` collection worth its downsides.
      #     Note L4: never store ID images; keep only the consent record.
      #   fees.payer = application
      #     FUIME PAYS ALL STRIPE PROCESSING (~2.9% + 30¢), which is a pricing
      #     model change. A 4% platform fee does not cover a 2.9% + 30¢ cost.
      cards_enabled: {
        controller: {
          losses: { payments: "application" },
          fees: { payer: "application" },
          requirement_collection: "application",
          stripe_dashboard: { type: "none" }
        },
        capabilities: {
          card_payments: { requested: true },
          transfers: { requested: true },
          # Connect Issuing is GA and does NOT require Stripe Treasury (a much
          # higher, sales-gated bar). It does require this capability plus
          # `transfers`.
          card_issuing: { requested: true }
        }
      }.freeze
    }.freeze

    DEFAULT_PROFILE = :payments_only

    # Retained for callers and copy that reference the baseline capability set.
    REQUESTED_CAPABILITIES = PROFILES[:payments_only][:capabilities]

    def initialize(event:, guardian:, profile: DEFAULT_PROFILE)
      @event = event
      @guardian = guardian
      @profile = profile.to_sym

      unless PROFILES.key?(@profile)
        raise UnknownProfile, "Unknown account profile #{profile.inspect}; expected one of #{PROFILES.keys.inspect}"
      end
    end

    # Idempotent: returns the existing record if the venture already has one.
    #
    # The local row is written BEFORE the Stripe call and updated after, so a
    # crash between the two leaves a row with a null stripe_id (visibly
    # incomplete, safe to retry) rather than a Stripe account Fuime has no record
    # of and can never reconcile. This mirrors StripeCardholderService::Create.
    # Note the profile is recorded on the row BEFORE the Stripe call, for the same
    # reason `stripe_id` is nullable: a crash between the two must leave a row a
    # retry can finish, and that retry has to request the SAME profile. Without the
    # stored intent, a retry would fall back to the default and silently create a
    # payments-only account for a family who asked for a card — an account that can
    # never be upgraded, because `controller` is create-only.
    #
    # An existing row whose profile disagrees with the one requested is a hard
    # error rather than a silent re-use, since the two are not interchangeable.
    def find_or_create_account!
      existing = @event.stripe_connected_account
      if existing&.stripe_id.present?
        verify_existing_profile!(existing)
        return existing
      end

      record = existing || StripeConnectedAccount.create!(
        event: @event, owner: @guardian, controller_profile: @profile.to_s
      )
      record.update!(controller_profile: @profile.to_s) if record.controller_profile != @profile.to_s

      # Idempotency-keyed because this is now reachable from two directions at
      # once: Fuime::ProvisionConnectAccountJob provisions eagerly when a
      # guardianship activates, and the guardian may click "Set up payments" in
      # the same breath. Both would read a blank `stripe_connected_account` and
      # both would call Stripe. The unique index on event_id stops the second ROW,
      # but nothing would stop the second ACCOUNT — leaving a real, orphaned Stripe
      # account for a minor's business that Fuime has no record of and can never
      # reconcile. Stripe dedupes on this key for 24 hours, which closes the window.
      #
      # Keyed on the profile as well as the venture because the two profiles are
      # different accounts, not different settings on one.
      account = Stripe::Account.create(
        account_params,
        request_options.merge(idempotency_key: "fuime-connect-account-#{@event.id}-#{@profile}")
      )
      record.sync_from_stripe!(account)

      # Stripe is the authority on what it actually built. If the returned account
      # is not configured the way it was asked to be, the mixed-fleet inference is
      # wrong and this venture must not be told it can have a card.
      unless record.controller_matches_requested_profile?
        Rails.logger.error(
          "[Fuime] connected account #{record.stripe_id} was requested as " \
          "#{@profile} but Stripe returned controller=#{record.controller.inspect}"
        )
      end

      record
    end

    # Mint a short-lived client secret for the embedded onboarding component.
    #
    # Account Sessions are ephemeral (Stripe returns an `expires_at`), so nothing
    # is persisted — the controller calls this on each page load.
    #
    # ── Why this refuses the cards profile ──────────────────────────────────
    #
    # This flow is built for `requirement_collection = stripe`: Stripe owns the
    # question of what identity information is outstanding, and the embedded
    # `account_onboarding` component is how the guardian supplies it. The whole
    # privacy argument for that configuration is that the SSN goes to Stripe and
    # never to Fuime.
    #
    # `:cards_enabled` inverts that — `requirement_collection = application` makes
    # FUIME responsible for collecting the guardian's identity details and passing
    # them to Stripe. That is a different onboarding surface with different
    # obligations (L4: verify, then delete the image, keep only the consent record),
    # and pointing a family at this component instead would produce a flow that
    # either does nothing or collects nothing.
    #
    # Refusing loudly is the honest failure. Silently serving the wrong flow to a
    # real guardian is not.
    def account_session_client_secret
      if @profile == :cards_enabled
        raise OnboardingPathNotImplemented,
              "The :cards_enabled profile uses requirement_collection=application, which needs a " \
              "Fuime-collected onboarding flow that does not exist yet. See " \
              "docs/fuime/LEGAL_RESEARCH.md and CLAUDE.md L4 before building it."
      end

      record = find_or_create_account!

      create_account_session(record, ONBOARDING_COMPONENTS)
    end

    # Mint a client secret for the guardian's ongoing MANAGEMENT surface — the
    # embedded replacement for the Stripe Dashboard.
    #
    # Deliberately does NOT call #find_or_create_account!, unlike the onboarding
    # secret above. Management is by definition an operation on an account that
    # already exists; creating one here would mean a stray GET on a management
    # URL could bring a real Stripe account into being for a venture nobody ever
    # onboarded. Raising instead keeps account creation to the one explicit path.
    def management_session_client_secret
      record = @event.payment_account

      if record.blank? || record.stripe_id.blank?
        raise AccountNotProvisioned,
              "Venture #{@event.id} has no Stripe account to manage yet; it must complete " \
              "payment setup first."
      end

      create_account_session(record, MANAGEMENT_COMPONENTS)
    end

    # Re-fetch from Stripe and update the mirror.
    #
    # Called when the guardian returns from onboarding, because finishing the
    # flow does NOT mean the account is usable — Stripe is explicit that exiting
    # the flow only means it was entered and exited properly. Treating the return
    # trip as success is the classic Connect bug, so the return path always asks
    # Stripe rather than assuming.
    def refresh!
      record = @event.stripe_connected_account
      return nil if record.blank? || record.stripe_id.blank?

      account = Stripe::Account.retrieve(record.stripe_id, request_options)
      record.sync_from_stripe!(account)
      record
    end

    def mark_onboarding_started!
      record = find_or_create_account!
      record.update!(onboarding_started_at: Time.current) if record.onboarding_started_at.blank?
      record
    end

    private

    # Account Sessions are ephemeral (Stripe returns an `expires_at`), so nothing
    # is persisted — callers mint one per page load or per fetchClientSecret call.
    def create_account_session(record, components)
      session = Stripe::AccountSession.create(
        { account: record.stripe_id, components: },
        request_options
      )

      session.client_secret
    end

    def profile_config
      PROFILES.fetch(@profile)
    end

    # An account already exists. Re-using it under a different profile than the
    # caller asked for would be wrong in both directions: serving a card-cohort
    # request from a payments-only account produces a venture that can never issue
    # a card, and serving a payments-only request from a card-cohort account
    # silently puts Fuime on the hook for that venture's losses.
    #
    # Since `controller` cannot be changed, the only correct answers are "you
    # already have the right kind of account" or "this needs a new account, which
    # means re-onboarding". This raises so a caller cannot proceed on the third,
    # non-existent answer.
    def verify_existing_profile!(record)
      return if record.controller_profile == @profile.to_s

      raise UnknownProfile,
            "Venture #{@event.id} already has a #{record.controller_profile} Stripe account, but " \
            "#{@profile} was requested. Stripe's `controller` property is create-only, so this " \
            "account cannot be converted — the venture must be re-onboarded onto a new account."
    end

    # Fuime: a school is a company, not an individual.
    #
    # Getting this wrong is not cosmetic. With business_type "individual", Stripe
    # asks the person completing onboarding for THEIR personal identity — SSN
    # last-4, home address, date of birth — and makes them the account's legal
    # owner. For a school that means a business-office employee personally backing
    # the institution's payment account, which is both wrong and something no
    # sensible administrator would agree to. "company" asks for the school's EIN
    # and business address instead, with the administrator merely as the
    # representative completing the form.
    def institutional?
      @event.institutionally_sponsored?
    end

    def account_params
      {
        country: "US",
        email: @guardian.email,
        # The guardian is the individual whose identity backs the account. Stripe
        # has no field expressing "this adult is the guardian of the person who
        # actually runs the business" — that relationship lives only in Fuime's
        # guardianships table, which is why it goes into metadata below.
        #
        # On an institutionally sponsored venture there is no guardian and the
        # entity itself is the account holder — see #institutional? above.
        business_type: institutional? ? "company" : "individual",
        # Both come from the profile. See PROFILES for what each choice costs;
        # `controller` in particular is create-only and permanent.
        controller: profile_config[:controller],
        capabilities: profile_config[:capabilities],
        business_profile: {
          name: @event.name
        },
        # Manual payouts, which is what makes the guardian approval gate real.
        #
        # On Stripe's default automatic schedule, the balance drains to the
        # family's bank on a timer and the platform cannot create arbitrary
        # payouts — so a "request a payout / parent approves" flow would be
        # theatre over money that was leaving anyway, and Fuime::PayoutService's
        # Stripe::Payout.create call would be rejected outright.
        #
        # Manual means nothing moves until an adult decides it should, which is
        # the ownership structure from L2 expressed as a Stripe setting rather
        # than as UI copy. The cost is that a family who never approves anything
        # accumulates a balance at Stripe indefinitely; the payout screen exists
        # to make that visible rather than silent.
        settings: {
          payouts: {
            schedule: { interval: "manual" }
          }
        },
        # The join back to Fuime. Stripe is the payments rail; Fuime's
        # guardianship record is the authority on who is responsible for whom, and
        # without this there is no way to reconcile an account to a family.
        metadata: {
          fuime_event_id: @event.id,
          fuime_event_slug: @event.slug,
          # On a school venture this is the manager who completed onboarding, not
          # a guardian. Recorded under a distinct key so reconciliation can never
          # mistake a business-office employee for a student's parent.
          **(if institutional?
               { fuime_onboarded_by_user_id: @guardian.id, fuime_sponsorship: "institution" }
             else
               { fuime_guardian_user_id: @guardian.id }
             end)
        },
        **individual_prefill
      }
    end

    # Fuime: hand Stripe everything we already know about the guardian, so they are
    # not asked to retype it.
    #
    # ── Why this is worth a method ──────────────────────────────────────────
    #
    # Every venture needs its guardian through Stripe's identity flow, and that flow
    # is the single biggest drop-off in the funnel. At a school rolling out to
    # thousands of families, the difference between a parent confirming prefilled
    # details and a parent typing their name, date of birth and phone number into a
    # form on a phone is measured in hundreds of students who never get to trade.
    #
    # `docs/fuime/STRIPE_PASS.md` records that API prefill was exercised against real
    # Stripe and accepted — "everything accepted except `tos_acceptance`" — so this is
    # a proven capability that was simply never wired up. Only `email` and the
    # business name were being sent.
    #
    # ── What this does NOT change ───────────────────────────────────────────
    #
    # The privacy position is untouched. `requirement_collection` stays "stripe" on
    # the default profile, so Stripe still collects and holds identity documents and
    # Fuime still stores none. These are fields Fuime already has (a guardian gives a
    # birthday at signup) and that Stripe requires regardless; sending them earlier
    # does not create a new copy anywhere.
    #
    # ── Why every field is optional and individually guarded ────────────────
    #
    # A malformed prefill is worse than no prefill: Stripe validates on create, so one
    # bad value fails the whole account and the family cannot onboard at all. That is
    # a strictly worse outcome than a parent typing their own phone number. So each
    # field is omitted unless it is present and well-formed, and nothing here can
    # raise — `first_name`/`last_name` already use safe navigation internally, and a
    # user with no birthday simply contributes no `dob`.
    def individual_prefill
      # Institutional accounts are `business_type: "company"` — the account holder is
      # the school, and its representative fields are a different shape entirely
      # (company name, EIN, a named representative). Prefilling an `individual` block
      # onto a company account is not a smaller version of this; it is wrong.
      return {} if institutional?

      individual = {
        email: @guardian.email,
        first_name: @guardian.first_name(legal: true),
        last_name: @guardian.last_name(legal: true),
        phone: e164_phone,
        dob: dob_for(@guardian)
      }.compact_blank

      individual.present? ? { individual: } : {}
    end

    def dob_for(user)
      return nil if user.birthday.blank?

      { day: user.birthday.day, month: user.birthday.month, year: user.birthday.year }
    end

    # Stripe wants E.164. Fuime's `phone_number` is free text a user typed, and is
    # only meaningful once verified — an unverified number is a claim, not a fact.
    #
    # Deliberately strict rather than clever: a normaliser that guesses at country
    # codes would eventually guess wrong and fail an account create. Anything that is
    # not already unambiguous E.164 is left for the parent to enter themselves, which
    # costs one field and cannot break onboarding.
    def e164_phone
      return nil unless @guardian.phone_number_verified?

      phone = @guardian.phone_number.to_s.strip
      phone.match?(/\A\+[1-9]\d{7,14}\z/) ? phone : nil
    end

    # See the class comment: never rely on the global Stripe.api_key here.
    def request_options
      { api_key: StripeService.secret_key }
    end

  end
end
