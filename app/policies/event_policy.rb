# frozen_string_literal: true

class EventPolicy < ApplicationPolicy
  def index?
    user.present?
  end

  def index_in_v4?
    auditor_or_reader?
  end

  # Event homepage
  def show?
    is_public || auditor_or_reader?
  end

  def show_in_v4?
    auditor_or_reader?
  end

  # Turbo frames for the event homepage (show)
  alias_method :team_stats?, :show?
  alias_method :recent_activity?, :show?
  alias_method :money_movement?, :show?
  alias_method :balance_transactions?, :show?
  alias_method :merchants_chart?, :show?
  alias_method :categories_chart?, :show?
  alias_method :top_categories?, :show?
  alias_method :tags_chart?, :show?
  alias_method :users_chart?, :show?
  alias_method :transaction_heatmap?, :show?

  alias_method :transactions?, :show?
  alias_method :transactions_list?, :transactions?
  alias_method :merchants_filter?, :transactions?
  alias_method :stats?, :show?

  def toggle_hidden?
    user&.admin?
  end

  def new?
    user&.admin?
  end

  def create?
    user&.admin?
  end

  def balance_by_date?
    is_public || auditor_or_reader?
  end

  def edit?
    auditor_or_member?
  end

  # pinning a transaction to an event
  def pin?
    admin_or_member?
  end

  def permit_merchant?
    admin_or_member?
  end

  def update?
    admin_or_manager?
  end

  alias remove_header_image? update?

  alias remove_background_image? update?

  alias remove_logo? update?

  alias enable_feature? update?

  alias disable_feature? update?

  alias toggle_fee_waiver_eligible? update?

  def validate_slug?
    admin_or_member?
  end

  def destroy?
    user&.admin? && record.demo_mode?
  end

  def team?
    is_public || auditor_or_reader?
  end

  def announcement_overview?
    is_public || record.announcements.published.any? || auditor_or_reader?
  end

  def feed?
    announcement_overview?
  end

  def emburse_card_overview?
    is_public || auditor_or_reader?
  end

  # FUIME-DISABLED: the org Cards page.
  #
  # Card issuing is explicitly a later phase (CLAUDE.md Milestone 5: "hide,
  # don't delete, the Stripe Issuing/cards UI"). Fuime::DisabledModules already
  # blocks stripe_cards/stripe_cardholders writes, but writes-only meant the
  # nav item and overview page still rendered, offering a "Create card" button
  # that could not work. Hidden here; nothing is deleted, so reviving this is
  # reverting one method.
  def card_overview?
    false
  end

  def card_overview_in_v4?
    show_in_v4? && card_overview?
  end

  def new_stripe_card?
    create_stripe_card?
  end

  def create_stripe_card?
    admin_or_member? && is_not_demo_mode?
  end

  def documentation?
    auditor_or_reader? && record.plan.documentation_enabled?
  end

  def statements?
    show?
  end

  def statement_of_activity?
    show? && auditor?
  end

  def async_balance?
    show?
  end

  def async_sub_organization_balance?
    sub_organizations?
  end

  def create_transfer?
    admin_or_manager? && !record.demo_mode?
  end

  def new_transfer?
    auditor_or_reader? && !record.demo_mode?
  end

  # FUIME-DISABLED: Google Workspace provisioning.
  #
  # `g_suite`, `g_suite_accounts` and `g_suite_aliases` are all in
  # Fuime::DisabledModules, but that concern blocks writes only — so the nav
  # item stayed visible and the overview page rendered in full, with every CTA
  # on it bouncing off the write filter. Standard is the default plan for new
  # orgs (EventService::Create) and it enables google_workspace, so this was
  # shown to every Fuime business.
  def g_suite_overview?
    false
  end

  def g_suite_create?
    admin_or_manager? && is_not_demo_mode? && record.plan.google_workspace_enabled?
  end

  def g_suite_verify?
    auditor_or_reader? && is_not_demo_mode? && record.plan.google_workspace_enabled?
  end

  def transfers?
    show? && record.plan.transfers_enabled?
  end

  def payments?
    Flipper.enabled?(:payments_contractors_refresh_2026_06_26, record) && show? && record.plan.transfers_enabled?
  end

  def contractors?
    # The contractors list is visible in transparency mode (public events),
    # but only shows status/name/period/purpose to the public. Sensitive
    # details (email, rate, totals, invoices) are gated by contractor_details?.
    Flipper.enabled?(:payments_contractors_refresh_2026_06_26, record) && show? && record.plan.transfers_enabled?
  end

  def contractor_details?
    # Contractor PII, pay rates, payment totals, and invoices — org members only.
    contractors? && auditor_or_reader?
  end

  def new_payment?
    payments? && new_transfer?
  end

  def create_payment?
    payments? && create_transfer?
  end

  def transfers_in_v4?
    show_in_v4? && transfers?
  end

  def card_grant_overview?
    (is_public || auditor_or_reader?) && (record.plan.card_grants_enabled? || record.card_grants.any?)
  end

  def bulk_upload_card_grants?
    admin_or_manager? && record.plan.card_grants_enabled?
  end

  # FUIME-DISABLED: the Perks page (events#promotions).
  #
  # Every perk on it is a Hack Club program Fuime cannot deliver: HCB stickers,
  # Hack Club's 1Password / StickerNinja / StickerMule / Replit / GitHub
  # partnerships, hackathon grants, free domains. Offering them to a teen
  # running a Fuime business is a promise that cannot be kept, and the page was
  # reachable by every org member — `auditor_or_reader?` was the loosest gate
  # of any page in the app.
  #
  # The PVSA perk went further and told the user "Since you run on Fuime, you
  # can issue Presidential Volunteer Service Awards" — an eligibility that
  # depends on the 501(c)(3) status Fuime does not have.
  #
  # Gating here rather than at the route disables the nav item and the action
  # together: EventsController#promotions calls `authorize @event`, and the nav
  # entry in EventsHelper::NAV_ITEMS is built from `policy(event).promotions?`.
  # Views and partials are left in place (CLAUDE.md Rule 2).
  def promotions?
    false
  end

  def reimbursements_pending_review_icon?
    show?
  end

  def reimbursements?
    auditor_or_reader? && record.plan.reimbursements_enabled?
  end

  def employees?
    auditor_or_reader? && Flipper.enabled?(:payroll_2025_02_13, record)
  end

  def sub_organizations?
    # Gating on the sub-organizations this viewer may see, rather than on all of
    # them: a page that exists only for organizations with a private roster
    # gives away that the roster is there.
    (is_public || auditor_or_reader?) && (record.subevents_enabled? || record.visible_subevents(user).exists?)
  end

  alias async_sub_organizations_graph? sub_organizations?

  def sub_organizations_in_v4?
    auditor_or_reader? && sub_organizations?
  end

  def create_sub_organization?
    return false unless record.subevents_enabled?

    admin_or_manager? || (Flipper.enabled?(:member_subevent_creation, record) && member?)
  end

  # FUIME-DISABLED: the Donations page.
  #
  # Donations are nonprofit fundraising — `donations`, `donation` and
  # `recurring_donations` are already in Fuime::DisabledModules. A teen
  # business does not solicit tax-deductible donations, and Fuime has no
  # charitable status to make them deductible. Writes-only blocking left the
  # nav item and the overview page live for every approved Standard-plan org.
  def donation_overview?
    false
  end

  def donation_page?
    record.approved? && record.plan.donations_enabled? && record.donation_page_enabled?
  end

  def invoices?
    show? && record.approved? && (record.plan.invoices_enabled? || record.invoices.any?)
  end

  def account_number?
    (auditor? || member?) && record.plan.account_number_enabled?
  end

  def toggle_event_tag?
    user&.admin?
  end

  def receive_grant?
    OrganizerPosition.role_at_least?(user, record, :reader)
  end

  def audit_log?
    # EventsController skips :signed_in_user so public org pages render for
    # logged-out visitors, so `user` can be nil here. Without the safe
    # navigation this raises NoMethodError and returns a 500 instead of
    # redirecting to login.
    user&.auditor?
  end

  # FUIME-DISABLED: the termination agreement PDF (events#termination).
  #
  # It generates a legal document terminating a *fiscal sponsorship* — "the
  # Agreement between The Hack Foundation ('Hack Club') and <business>" —
  # under which "Hack Club shall… transfer the balance of assets in Hack
  # Club's restricted Fund" to a successor, defaulting to The Hack Foundation
  # itself. Fuime is not a fiscal sponsor, holds no restricted fund, and
  # cannot execute an agreement on Hack Club's behalf.
  #
  # Auditor-gated and unlinked upstream, so this was never reachable by a teen
  # — but it is the same class of document as the fiscal sponsorship and
  # verification letters disabled in config/routes.rb, and is closed for the
  # same reason. The action and template remain (CLAUDE.md Rule 2).
  def termination?
    false
  end

  def can_invite_user?
    admin_or_manager?
  end

  def claim_point_of_contact?
    user&.admin?
  end

  def activation_flow?
    user&.admin? && record.demo_mode?
  end

  def activate?
    user&.admin? && record.demo_mode?
  end

  def toggle_scoped_tag?
    admin_or_manager?
  end

  def request_call?
    signee?
  end

  def ledger?
    auditor? || (reader? && (Flipper.enabled?(:new_ledger_2026_06_30, record) || Flipper.enabled?(:new_ledger_2026_07_17, user)))
  end

  def toggle_new_ledger?
    auditor_or_reader?
  end

  alias hide_onboarding_message? request_call?

  private

  def admin_or_member?
    admin? || member?
  end

  def auditor_or_reader?
    auditor? || reader?
  end

  def auditor_or_member?
    auditor? || member?
  end

  def admin?
    user&.admin?
  end

  def auditor?
    user&.auditor?
  end

  def reader?
    # Read access is NOT gated on guardianship: a teen waiting on their parent
    # can still see their own business, and a guardian needs to see the ledger
    # they are responsible for. Only acting on the business is gated.
    OrganizerPosition.role_at_least?(user, record, :reader)
  end

  # Fuime: member and manager are the roles that can *act* on a business —
  # every write path in this policy resolves through one of them. Gating here
  # rather than on ~40 individual predicates means a minor without an active
  # guardianship cannot mutate a business through any of them, including any
  # added later.
  def member?
    return false unless permitted_to_operate_business?

    OrganizerPosition.role_at_least?(user, record, :member)
  end

  def manager?
    return false unless permitted_to_operate_business?

    OrganizerPosition.role_at_least?(user, record, :manager)
  end

  # Admins are staff, not teen business owners, and are not subject to the
  # guardianship control.
  def permitted_to_operate_business?
    return true if user.blank?
    return true if user.admin?

    user.permitted_to_operate_business?
  end

  def signee?
    OrganizerPosition.find_by(event: record, user:)&.is_signee?
  end

  def admin_or_manager?
    admin? || manager?
  end

  def admin_or_reader?
    admin? || reader?
  end

  def is_not_demo_mode?
    !record.demo_mode?
  end

  def is_public
    record.is_public?
  end

end
