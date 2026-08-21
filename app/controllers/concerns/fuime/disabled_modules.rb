# frozen_string_literal: true

module Fuime
  # Fuime: block HCB modules Fuime does not offer.
  #
  # Fuime inherited HCB's full banking surface — ACH origination, checks, wires,
  # disbursements, donations, grants, G Suite provisioning. Fuime has no custody
  # and no license to move money out (docs/fuime/PRODUCTION_READINESS.md §1.5),
  # so none of it should be reachable. Previously these were "disabled" by not
  # rendering nav links, which leaves every route live to anyone who types a URL
  # — and the people typing URLs here are teenagers.
  #
  # This blocks at the request level, which is enforcement; hiding a nav link is
  # not. Nothing is deleted (CLAUDE.md Rule 2), so re-enabling a module is a
  # one-line change here once it is actually supported.
  #
  # Admins are exempt so support staff can still inspect inherited records.
  module DisabledModules
    extend ActiveSupport::Concern

    included do
      before_action :block_disabled_fuime_modules
    end

    # ── Three lists, because there are three different reasons ────────────────
    #
    # This was one list. Splitting it, because "Fuime will never do this" and
    # "Fuime cannot do this yet" are different statements and only one of them is
    # meant to be reversible.
    #
    # Under the umbrella merchant-of-record model the custody modules are supposed
    # to come back the day a sponsor bank partner exists. A module that comes back
    # by editing a frozen array inside a controller concern comes back by
    # rewriting code and re-reviewing a diff — which is exactly what CLAUDE.md
    # Rule 2 ("disable, don't delete") was written to avoid. Putting them behind
    # Fuime::Features makes re-enabling what Rule 2 promised: a config change.
    #
    #   DISABLED_CONTROLLER_PREFIXES        — never. Not Fuime's product.
    #   SPONSOR_BANKING_CONTROLLER_PREFIXES — until a sponsor bank exists.
    #   CARD_ISSUING_CONTROLLER_PREFIXES    — until cards have a funding rail.
    #
    # Deliberately in NONE of them: receipts,
    # comments, ledger/transactions, card grants' read views, or the admin console.
    #
    # NOTE: reimbursements are deliberately absent too. FUIME_HACKATHON_SPEC lists
    # them as "hide nav", not disable — a teen reimbursing themselves for a
    # business expense is a legitimate flow, and the money moves within Fuime
    # rather than out of it. Blocking them silently no-opped report updates: a
    # PATCH that returned success while changing nothing, which is worse than
    # either allowing the action or plainly refusing it.

    # Modules Fuime does not offer and will not offer. No flag reaches these.
    DISABLED_CONTROLLER_PREFIXES = [
      # Nonprofit fundraising — not applicable to a teen business. Fuime has no
      # charitable status that could make a donation deductible, so this is a
      # product statement rather than a licensing one and no partner bank changes
      # it.
      "donations",
      "donation", # namespace
      "recurring_donations",

      # FUIME 2026-08-20: invoices, and this one is a MONEY-CORRECTNESS decision
      # rather than a product one — it was previously listed here as deliberately
      # NOT disabled, "money IN — Fuime's model". That was true before Fuime had
      # its own money-in path and is now actively dangerous.
      #
      # `Fuime::PayablesLedger` attributes a sale to an operator by MEMO PREFIX:
      # gross sales are `settled_sum("fuime_pi_")`, written only by Fuime's own
      # payment recorders. An upstream HCB invoice payment writes an
      # invoice-shaped memo, so under merchant-of-record the money lands in
      # FUIME'S Stripe balance, appears on the ledger, and **never becomes
      # something Fuime owes the operator** — no payable, and no 5% fee either.
      # A teenager would invoice a client, be paid, and have no record that Fuime
      # holds their money.
      #
      # Offers and payment links are the money-in path now and they are wired
      # correctly. Invoices are a stale second door that mis-accounts, so they are
      # closed rather than left to be discovered by a founder chasing $400.
      #
      # Re-enable only alongside a recorder that writes the `fuime_pi_` prefix and
      # takes the fee — at which point this comment is the specification.
      "invoices",
      # The v4 API twin. Blocking only the HTML controller would leave the same
      # capability open on a different path — asserted by disabled_modules_spec.
      "api/v4/invoices",
      "card_grants",
      "card_grant", # namespace

      # Google Workspace provisioning for fiscally-sponsored orgs.
      "g_suite",
      "g_suite_accounts",
      "g_suite_aliases",

      # The v4 API exposes the same capabilities under a different path, so
      # blocking only the HTML controllers would leave an open back door.
      "api/v4/card_grants",
      "api/v4/donations",
    ].freeze

    # Modules that only make sense when money sits in an account Fuime controls on
    # someone else's behalf — origination of outbound transfers, and the inherited
    # Emburse spend platform.
    #
    # Blocked while Fuime::Features.sponsor_banking? is false, which is Fuime's
    # shipping posture and has been since Phase 0. Nothing here is deleted, none of
    # the models are touched, and their specs still run: flipping the flag restores
    # the routes exactly as upstream wrote them.
    #
    # These were formerly hardcoded into the list above with the reason "Fuime
    # holds no funds and cannot originate", which is true today and is precisely
    # the condition the flag now names.
    SPONSOR_BANKING_CONTROLLER_PREFIXES = [
      "ach_transfers",
      "increase_checks",
      "checks",
      "check_deposits",
      "wires",
      # Wise is outbound international transfer — the same category as wires,
      # and it was the one member of it not on this list, so Fuime could still
      # originate one. Reaching it also raised Faraday::BadRequestError from a
      # live Wise API call rather than being refused: a policy gap and a 500.
      "wise_transfers",
      "disbursements",

      # Emburse is the pre-Stripe card platform inherited from upstream. Custody
      # shaped and long dead, but kept loadable for existing rows.
      "emburse_cards",
      "emburse_card_requests",
      "emburse_transactions",

      "api/v4/ach_transfers",
      "api/v4/check_deposits",
      "api/v4/checks",
      "api/v4/disbursements",
      "api/v4/wires",
    ].freeze

    # Stripe Issuing.
    #
    # ⚠️ READ BEFORE GOING LIVE WITH CARDS (note from 2026-08-03, still true).
    # Inherited Issuing is structurally incompatible with any model where Fuime
    # does not own the funds, and the incompatibility is a funding one, not a
    # config one:
    #
    #   * A swipe is approved against `StripeCard#balance_available`, i.e. the
    #     EVENT'S LEDGER balance (app/models/stripe_card.rb:392).
    #   * The debit lands on the PLATFORM's Stripe Issuing balance, which HCB
    #     tops up from its own money (upstream app/jobs/topup_stripe_job.rb) —
    #     one shared balance for every org, with per-org limits enforced only by
    #     the subledger.
    #   * Under Connect that ledger MIRRORS THE GUARDIAN'S Stripe balance. The
    #     money is the family's, held by Stripe, not Fuime's to spend. Under the
    #     merchant-of-record model it mirrors a PAYABLE — money Fuime owes but has
    #     not yet paid — so a swipe is Fuime advancing cash against its own unpaid
    #     invoice to a minor.
    #
    # Either way, going live as-is means Fuime funds the swipe: uncollateralised
    # credit extended to a minor's business. Celtic Bank's own Authorized User
    # Terms make this explicit — the "Accountholder" is the entity with the credit
    # account, and "all expenses on your card are the responsibility of the
    # Accountholder". HCB can carry that because it is a 501(c)(3) that legally
    # owns the funds. Fuime cannot.
    #
    # Cards therefore need their own funding rail, not a flag flip — so the flag
    # here is a floor, not a green light. See #card_issuing_blocked? for why test
    # mode is carved out, and docs/fuime/MOR_MIGRATION_PLAN.md §1 C3.
    CARD_ISSUING_CONTROLLER_PREFIXES = [
      "stripe_cards",
      "stripe_cardholders",
      "fuime/cards",
      "api/v4/stripe_cards",
    ].freeze

    # Every prefix blocked *right now*, given the current flag state.
    #
    # Exists because "what is turned off?" stopped being a constant the moment the
    # answer depended on a flag. Callers that used to read
    # DISABLED_CONTROLLER_PREFIXES to answer it — specs, and any future admin
    # diagnostics page — were asking about behaviour and happening to get it from a
    # list. Now the list and the behaviour can differ, so the question needs a real
    # answer rather than a lucky one.
    def self.blocked_prefixes
      prefixes = DISABLED_CONTROLLER_PREFIXES.dup
      prefixes.concat(SPONSOR_BANKING_CONTROLLER_PREFIXES) unless ::Fuime::Features.sponsor_banking?
      prefixes.concat(CARD_ISSUING_CONTROLLER_PREFIXES) unless ::Fuime::Features.card_issuing_permitted?
      prefixes.freeze
    end

    # Every prefix any list mentions, regardless of flags. For checks about the
    # lists themselves — that each names a controller that exists, say — where the
    # current flag state is beside the point.
    def self.all_gated_prefixes
      (DISABLED_CONTROLLER_PREFIXES +
        SPONSOR_BANKING_CONTROLLER_PREFIXES +
        CARD_ISSUING_CONTROLLER_PREFIXES).freeze
    end

    private

    def block_disabled_fuime_modules
      return unless fuime_module_disabled?
      return if current_user&.admin?
      return if safe_request_method?

      respond_to do |format|
        format.html do
          redirect_back_or_to root_path,
                              alert: "That feature isn't available on Fuime."
        end
        format.json { render json: { error: "Feature not available" }, status: :not_found }
        format.any  { head :not_found }
      end
    end

    # Only state-changing requests are blocked.
    #
    # The goal is that Fuime cannot originate a payment, issue a card, or
    # provision a mailbox — all of which require a POST/PATCH/PUT/DELETE.
    # Blocking GETs as well stopped anyone from *viewing* records inherited
    # from upstream (an existing ACH transfer's detail page, a card grant's
    # history), which prevents nothing and breaks legitimate read paths — the
    # transaction drawer links to these pages, and upstream specs exercise them.
    #
    # Read access is still governed by the normal Pundit policies; this filter
    # only removes the ability to act.
    def safe_request_method?
      request.get? || request.head?
    end

    def fuime_module_disabled?
      return true if matches_prefix?(DISABLED_CONTROLLER_PREFIXES)
      return true if !::Fuime::Features.sponsor_banking? &&
                     matches_prefix?(SPONSOR_BANKING_CONTROLLER_PREFIXES)
      return true if card_issuing_blocked? &&
                     matches_prefix?(CARD_ISSUING_CONTROLLER_PREFIXES)

      false
    end

    # Deliberately delegated rather than restated: StripeCard#balance_available
    # asks the same question when it decides whether to approve a swipe, and two
    # copies of "may Fuime issue cards" is how a card gets refused at the form and
    # approved at the terminal.
    def card_issuing_blocked?
      !::Fuime::Features.card_issuing_permitted?
    end

    def matches_prefix?(prefixes)
      prefixes.any? do |prefix|
        controller_path == prefix || controller_path.start_with?("#{prefix}/")
      end
    end
  end
end
