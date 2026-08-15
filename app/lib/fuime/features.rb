# frozen_string_literal: true

module Fuime
  # Fuime: structural feature flags — the ones that change what Fuime *legally is*.
  #
  # ── Why this is not Flipper ─────────────────────────────────────────────────
  #
  # Fuime already has Flipper (config/initializers/flipper.rb), with an admin UI,
  # actor gates and percentage rollouts. Flipper is the right tool for "show the
  # new payouts page to 10% of ventures". It is the wrong tool for this.
  #
  # A Flipper flag is a checkbox in a web UI that any admin can tick. The flags in
  # this file gate whether Fuime holds customer funds. Ticking one of those on
  # without a sponsor bank behind it is not a bad rollout — it is unlicensed money
  # transmission (18 U.S.C. § 1960, criminal; CLAUDE.md L1). A control whose
  # failure mode is "a support admin commits a felony by clicking a toggle" must
  # not be reachable from a browser at all.
  #
  # So these read the process environment and nothing else. Changing one requires
  # a deploy, which means a person, a diff and a review — and
  # config/initializers/fuime_safety_check.rb refuses to boot if the flag is on
  # without the credentials that make it lawful.
  #
  # ── Which flag goes where ───────────────────────────────────────────────────
  #
  #   Structural (here)  — "is Fuime a custodian?", "is Fuime the seller?"
  #                        Off by default. Deploy-time only. Boot-checked.
  #   Rollout (Flipper)  — "who can see this page yet?"
  #                        Safe to toggle live. Not this file's business.
  #
  # ── Adding a flag ───────────────────────────────────────────────────────────
  #
  # Only if getting it wrong has a legal consequence rather than a product one.
  # Everything else belongs in Flipper. Default MUST be off: a missing env var on
  # a fresh environment has to mean the safe answer, because the environment that
  # forgets to set it is exactly the one nobody has reviewed.
  module Features
    # Does Fuime hold customer funds, on its own or through a partner bank?
    #
    # Gates: stored balances presented as spendable, card issuing, ACH/wire/check
    # origination, balance fronting — everything that only makes sense if money
    # sits in an account Fuime controls on a user's behalf.
    #
    # OFF is the shipping posture and has been since Phase 0. It stays off until a
    # sponsor bank partner exists, at which point turning it on is a config change
    # rather than a rewrite — which is the entire reason this code is gated instead
    # of deleted (CLAUDE.md Rule 2).
    #
    # Under the umbrella merchant-of-record model this flag being OFF is what makes
    # the model true: money reaching Fuime's Stripe balance is Fuime's own revenue
    # from its own sale, and what an operator is owed is a PAYABLE, not a balance
    # they have on deposit with us. See docs/fuime/MOR_MIGRATION_PLAN.md §1.
    SPONSOR_BANKING = "FEATURE_SPONSOR_BANKING"

    # Is Fuime LLC the legal seller of what operators sell?
    #
    # Gates the umbrella merchant-of-record model: customer payments landing in
    # Fuime's own Stripe balance, operators paid afterwards as vendors on a
    # cadence. See docs/fuime/MOR_MIGRATION_PLAN.md §8.
    #
    # ── Why this needs a flag of its own ────────────────────────────────────────
    #
    # SPONSOR_BANKING and this one look similar and are close to opposites. Custody
    # is "Fuime holds YOUR money" — that needs a bank. MoR is "the money is Fuime's
    # own revenue, and we owe you a payable" — that needs no bank, but it only
    # holds if Fuime really is the seller: Fuime's terms of sale, Fuime's name on
    # the receipt, Fuime bearing the refund and chargeback obligation to the buyer.
    #
    # That is a fact about the commercial relationship, not about the code. Turning
    # this on when those documents do not exist does not make Fuime a merchant of
    # record — it makes Fuime a conduit accepting a stranger's payment, which is
    # the unlicensed money transmission L1 has been architected around since Phase
    # 0. The flag cannot make the structure true; it can only stop the code
    # pretending the structure is there.
    #
    # Hence the boot guard in config/initializers/fuime_safety_check.rb: this flag
    # alone will not enable it. FUIME_MOR_COUNSEL_MEMO must cite the memo, for the
    # same reason FUIME_SPONSOR_BANK_PARTNER must name a bank — someone has to
    # write down an answer that cannot be given truthfully unless the work is real.
    #
    # OFF is the shipping posture. MOR_MIGRATION_PLAN §7 Q1, Q2 and Q4 are open:
    # two questions for counsel and one for Stripe. Phases 3+ are built behind this
    # so the engineering can run alongside the legal work rather than behind it —
    # writing the code moves no money, and this is what keeps that true.
    MERCHANT_OF_RECORD = "FEATURE_MERCHANT_OF_RECORD"

    # Every structural flag, so the safety check and the admin diagnostics page can
    # enumerate them without this list drifting out of sync with reality.
    ALL = [SPONSOR_BANKING, MERCHANT_OF_RECORD].freeze

    class << self
      def sponsor_banking?
        enabled?(SPONSOR_BANKING)
      end

      def merchant_of_record?
        enabled?(MERCHANT_OF_RECORD)
      end

      # Raise unless Fuime is configured as the seller of record.
      #
      # Same reasoning as #sponsor_banking! — for the call sites where a safe
      # default would silently do the wrong thing. A service that would collect a
      # payment into Fuime's balance must fail loudly when Fuime is not the seller,
      # because the quiet version of that failure is money transmission.
      def merchant_of_record!
        return true if merchant_of_record?

        raise Disabled, <<~MSG.squish
          This requires the merchant-of-record model, which is off
          (#{MERCHANT_OF_RECORD} is not enabled). Fuime is not configured as the
          legal seller, so a payment collected here would be a third party's money.
          See docs/fuime/MOR_MIGRATION_PLAN.md §8.
        MSG
      end

      # Raise unless custody is enabled.
      #
      # For the handful of call sites where returning a safe default would silently
      # do the wrong thing — a service that would otherwise originate a transfer, or
      # report success having moved nothing. A loud failure is correct there; a
      # quiet zero is not.
      def sponsor_banking!
        return true if sponsor_banking?

        raise Disabled, <<~MSG.squish
          This requires sponsor banking, which is off. Fuime does not hold customer
          funds (#{SPONSOR_BANKING} is not enabled). See docs/fuime/MOR_MIGRATION_PLAN.md.
        MSG
      end

      # The word "true", case-insensitively. Nothing else.
      #
      # Emphatically not `.present?`, which would read the string "false" as
      # enabled — the single most dangerous way to misparse a flag like this one.
      # Also not truthy-ish parsing of "1"/"yes"/"on": those are conventions
      # different tools disagree about, and a flag that decides whether Fuime
      # holds customer money should have exactly one spelling that turns it on.
      #
      # Case is folded and whitespace stripped because deploy dashboards and CI
      # exporters mangle both, and "TRUE" from a config UI means what it says. The
      # values that must never enable it — "", "false", "0", "no", nil — all fail
      # this comparison on their own terms rather than by being enumerated, so a
      # spelling nobody anticipated fails safe.
      def enabled?(name)
        ENV[name].to_s.strip.downcase == "true"
      end

      # May Fuime issue and authorise cards right now?
      #
      # Not a flag of its own, and deliberately not a second env var: it is a
      # DERIVED answer, and putting it here rather than in a controller concern
      # gives the request layer and the authorisation layer one definition
      # instead of two that can drift.
      #
      # Cards need custody — a swipe is funded from a balance somebody holds. With
      # sponsor banking off, that balance would be Fuime's own money advanced
      # against an operator's unpaid payable (see Fuime::DisabledModules'
      # CARD_ISSUING_CONTROLLER_PREFIXES for the full argument, and Celtic Bank's
      # Accountholder terms for why the liability is Fuime's).
      #
      # The test-mode carve-out is not a loophole, it is the existing posture
      # written down: a card issued against Stripe TEST keys spends nothing real,
      # and the fork has deliberately kept Issuing demonstrable since 2026-08-02.
      # The note recording that decision ended "Blocked again the moment this fork
      # points at anything but test keys" — this is the code that finally means it.
      #
      # Reads STRIPE_MODE through StripeService rather than Rails.env, because
      # this fork runs test-mode Stripe in production on purpose and the question
      # is about the keys, not the environment.
      def card_issuing_permitted?
        return true if sponsor_banking?

        !::StripeService.live?
      end

      # What every structural flag is set to, for the boot log and admin display.
      def to_h
        ALL.index_with { |name| enabled?(name) }
      end
    end

    class Disabled < StandardError; end

  end
end
