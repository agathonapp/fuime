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

    # Controller path prefixes for modules Fuime does not offer.
    #
    # Deliberately does NOT include: invoices (money IN — Fuime's model),
    # receipts, comments, ledger/transactions, card grants' read views, or the
    # admin console.
    DISABLED_CONTROLLER_PREFIXES = [
      # Outbound money movement — Fuime holds no funds and cannot originate.
      "ach_transfers",
      "increase_checks",
      "checks",
      "check_deposits",
      "wires",
      "disbursements",
      "reimbursement", # namespace: reimbursement/reports, /expenses, ...

      # Nonprofit fundraising — not applicable to a teen business.
      "donations",
      "donation",      # namespace
      "recurring_donations",
      "card_grants",
      "card_grant",    # namespace

      # Google Workspace provisioning for fiscally-sponsored orgs.
      "g_suite",
      "g_suite_accounts",
      "g_suite_aliases",

      # Physical/virtual card issuing — explicitly a later phase.
      "stripe_cards",
      "stripe_cardholders",
      "emburse_cards",
      "emburse_card_requests",
      "emburse_transactions",
    ].freeze

    private

    def block_disabled_fuime_modules
      return unless fuime_module_disabled?
      return if current_user&.admin?

      respond_to do |format|
        format.html do
          redirect_back_or_to root_path,
                              alert: "That feature isn't available on Fuime."
        end
        format.json { render json: { error: "Feature not available" }, status: :not_found }
        format.any  { head :not_found }
      end
    end

    def fuime_module_disabled?
      DISABLED_CONTROLLER_PREFIXES.any? do |prefix|
        controller_path == prefix || controller_path.start_with?("#{prefix}/")
      end
    end
  end
end
