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

  # Re-enabled for test-mode card issuing (2026-08-02), reverting the
  # FUIME-DISABLED stub added during the brand sweep — which was written to be
  # undone exactly this way. Upstream's implementation, unmodified.
  #
  # This is Stripe Issuing in TEST MODE ONLY, per CLAUDE.md Rule 4. Card issuing
  # remains out of scope for a real Phase 0 launch (custody, KYC and the
  # merchant-of-record structure all gate it); this makes it demonstrable, not
  # shippable.
  def card_overview?
    show? && record.approved? && record.plan.cards_enabled?
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

  # Fuime: outstanding-receipt count for one org, shown on a parent's roster.
  #
  # Deliberately NOT show? (which async_balance? uses). A transparent org's
  # balance is public by design; how far behind it is on receipt collection is
  # internal compliance state, and on a school roster it is a per-student
  # figure. reader? keeps it to people with a role in the org or an ancestor,
  # which is what makes it safe for a guide to see across their students while
  # remaining invisible to the public on a transparent org.
  def async_missing_receipts?
    reader?
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

  # Fuime: who may set up (or repair) the venture's payment account.
  #
  # The guardian only, plus admins for support. Not the minor, and this is the
  # one place in the policy where that restriction is not about the guardianship
  # gate but about who the account legally belongs to: Stripe requires the
  # account owner and representative of an under-18 account to be the adult, and
  # onboarding collects that adult's identity details (DOB, address, SSN last 4).
  # A teen cannot supply those and must not be asked to.
  #
  # Note this does NOT require `permitted_to_operate_business?`: the guardian is
  # an adult and is never subject to that gate, and the whole point of the flow
  # is that it runs before the venture can trade.
  #
  # MUST STAY ABOVE `private`. Pundit resolves a query with `public_send`, and
  # Fuime::PaymentSetupsController both calls `authorize @event, :setup_payments?`
  # and reads `policy(@event).setup_payments?` directly. Below the `private`
  # keyword — where this and #payment_setup_status? were originally written — every
  # request to the Connect onboarding flow raised NoMethodError, so the whole
  # payment-setup feature 500'd. The private section below is for helpers like
  # #reader? and #member? that only this class calls.
  def setup_payments?
    return false if user.blank?
    return true if user.admin?

    # Fuime: on an institutionally sponsored org there is no guardian to be, so
    # the guardian check below can never pass and a school could not connect
    # Stripe at all. The equivalent responsible party is a manager — the business
    # office — and manager? already resolves through the event tree, so a manager
    # on the school qualifies on each student's sub org beneath it.
    #
    # Kept as a separate branch rather than widening guardian_reader?, so the
    # rule stays legible: a parent-backed venture is still guardian-only.
    return manager? if record.institutionally_sponsored?

    guardian_reader?
  end

  # Fuime: the venture's payment status page. Readable by the team as well as the
  # guardian — a teen needs to know whether they can be paid and whose action is
  # outstanding, even though they cannot act on it themselves.
  #
  # Public for the same reason as #setup_payments? above.
  def payment_setup_status?
    auditor_or_reader?
  end

  # Fuime: the payout destination under merchant-of-record — the page, and the
  # act of connecting a bank to it.
  #
  # Public for the same reason as #setup_payments? above: Pundit resolves a query
  # with `public_send`, and Fuime::PayoutMethodsController reads both of these
  # directly off `policy(@event)`.
  #
  # ── Why the split mirrors payments rather than payouts ──────────────────────
  #
  # Reading is team-wide: a teen needs to see whether their venture can be paid
  # and whose action is outstanding, exactly as on the Connect status page.
  #
  # Connecting is the responsible adult's alone, and that is not a courtesy — a
  # minor generally cannot open a bank account, so the destination is a
  # guardian-owned one (MOR_MIGRATION_PLAN §4.3 diligence item 2) and the adult
  # is the person who can actually log into it. It is also the same control as
  # #decide_payout?: the party who decides money leaves is the party who says
  # where it goes. A teen who could repoint the destination could route their own
  # earnings past the approval that makes the ownership structure real (L2).
  def payout_method?
    auditor_or_reader?
  end

  def connect_payout_method?
    return false if user.blank?
    return true if user.admin?

    # Fuime: a school programme has no guardian by design — the school is in
    # loco parentis — so the responsible party is a manager (the business
    # office), exactly as in #setup_payments? and #decide_payout?. Without this
    # branch a school venture could never connect a destination and every one of
    # its students would be skipped from every payout run.
    return manager? if record.institutionally_sponsored?

    guardian_reader?
  end

  # Fuime: who may ask to move money out, and who may decide.
  #
  # Requesting is a member action (the teen running the venture). Deciding is the
  # guardian's alone, because they own the account and the funds — see
  # PayoutRequest and CLAUDE.md L2. Admins can decide too, for support on stuck
  # payouts.
  # Fuime: asking to be paid.
  #
  # ── Why this re-asks for the guardian that #member? no longer asks for ─────
  #
  # Under merchant-of-record a minor may run a venture without a guardian —
  # User#permitted_to_operate_business? explains why, and #member? passes them
  # through as a result. Money leaving is where that stops, and this predicate is
  # where a teenager meets that fact.
  #
  # Without this branch the failure is not a locked door but the same trap the
  # school carve-out in #decide_payout? was written for, and worse. A parentless
  # operator would file a request; `decide_payout?` requires a guardian, so no
  # human except a Fuime admin could ever action it; and
  # `one_pending_request_per_venture` would then refuse them a second request
  # forever. One click, permanently wedged, with their money on the far side.
  #
  # So the request is refused up front, while it is still recoverable and while
  # there is a sentence to show them: invite your parent. That ask now lands at
  # the moment it means something — a teenager with money waiting is a teenager
  # whose parent has a reason to say yes — which is the whole point of moving the
  # gate here rather than in front of selling.
  #
  # Belt and braces with Fuime::PayableAssessment#compute_structural_skip_reason,
  # which independently refuses to put an unguardianed operator in a payout run.
  # That one covers the batch path, where no policy is consulted at all.
  def request_payout?
    return false if user.blank?
    return true if user.admin?
    return false unless member?

    if ::Fuime::Features.merchant_of_record? && !record.institutionally_sponsored?
      return false if user.minor_or_unknown_age? && !user.has_active_guardian?
    end

    true
  end

  def decide_payout?
    return false if user.blank?
    return true if user.admin?

    # Fuime: on an institutionally sponsored venture there is no guardian, by
    # design — the school is in loco parentis and no Guardianship row exists or
    # should. So `guardian_reader?` could never pass, and the effect was not a
    # locked door but a trap: `request_payout?` resolves through `member?`, which
    # #permitted_to_operate_business? lets a school's students through, so a
    # student could file a request that nobody on earth except a Fuime admin could
    # decide. `one_pending_request_per_venture` then blocked them from ever filing
    # another. Every school venture was one click from being permanently wedged.
    #
    # The equivalent responsible party is a manager — the guide or business office
    # — exactly as in #setup_payments?, and `manager?` already resolves through the
    # event tree so a manager on the school qualifies on each student's sub org.
    #
    # Segregation of duties still holds: a manager is >= member and so could both
    # request and decide, which PayoutRequest#approver_must_not_be_the_requester
    # refuses at the record level.
    return manager? if record.institutionally_sponsored?

    # Deliberately NOT `member? || guardian_reader?`. A teen approving their own
    # payout would defeat the entire ownership structure, and PayoutRequest
    # validates the same rule at the record level.
    guardian_reader?
  end

  # Fuime: confirming that a school actually paid a student.
  #
  # Only reachable on the personal_transfer path, which only exists on a venture
  # inside a school programme, so this is a manager question and never a guardian
  # one. Kept separate from #decide_payout? because it is a different assertion at a
  # different time — "I approve this" vs "the money has gone" — and the business
  # office making the second one is not necessarily the guide who made the first.
  def settle_payout?
    return false if user.blank?
    return true if user.admin?
    return false unless record.institutionally_sponsored?

    manager?
  end

  # Fuime: a school putting its own money into a student's venture ("$100 per A").
  #
  # A manager question and never a student one, and the direction is what makes that
  # obvious: unlike a payout, nobody asks for this — the school initiates it, and it
  # spends the school's own balance. There is no second approval step for the same
  # reason. A payout needs one because a minor is moving money out of an account they
  # do not own; here the account owner IS the party acting.
  #
  # Institutional trees only. On a family venture the equivalent — a parent putting
  # money into their child's business — has no shared account to move it within, so
  # there is nothing this could post against.
  def grant_school_award?
    return false if user.blank?
    return true if user.admin?
    return false unless record.institutionally_sponsored?

    manager?
  end

  # Seeing the awards a venture has received. The student needs this — it is their
  # money and their running total toward the school's 1099 threshold — so it is
  # reader-level, unlike granting.
  def school_awards?
    auditor_or_reader?
  end

  # Adding the school's own money to the school's own Stripe balance.
  #
  # Manager-only and, unlike #school_awards?, NOT visible to students at all. A student
  # has no business seeing the school's treasury operations, and the page shows the
  # school's whole balance — which on a shared account is every sibling venture's
  # revenue as well.
  #
  # Guarded on the venture owning its OWN account rather than merely being
  # institutionally sponsored: a top-up funds `stripe_connected_account`, and a student
  # sub org resolves its payment account up the tree, so offering this there would let
  # someone fund the school from a page that looks like the student's.
  def fund_school?
    return false if user.blank?
    return true if user.admin?
    return false unless record.institutionally_sponsored?
    return false if record.stripe_connected_account.blank?

    manager?
  end

  # The payouts screen itself: the team needs to see the balance and the state of
  # their request, the guardian needs to see what they are being asked to approve.
  def payouts?
    auditor_or_reader?
  end

  # Fuime: offers — what the venture sells and what it costs.
  #
  # Deliberately the OPPOSITE split from payouts, and the contrast is the point.
  # A guardian decides money leaving because they own the account and the funds
  # (L2). A guardian does not decide what their kid's work is worth: §8.3 D2's
  # mitigation for worker misclassification is that the operator controls their
  # own pricing, and a third party setting the rate is a third party setting the
  # rate whether that party is Fuime or a parent.
  #
  # So the guardian reads and the operator writes. Visibility without control —
  # every offer is on the storefront and every sale is in the ledger a guardian
  # can already see.
  def offers?
    auditor_or_reader?
  end

  def manage_offers?
    return false if user.blank?
    return true if user.admin?

    # #permitted_to_operate_business? rather than a bare `member?`: it is the
    # same gate as spending, and it carries the guardianship check a minor needs
    # before acting on a venture at all.
    member? && permitted_to_operate_business?
  end

  # Fuime: cards. Four predicates rather than one, because the interesting design here
  # is that they do NOT all belong to the same person.
  #
  # The teen operates the business and so needs to see the cards and be able to FREEZE
  # one. The guardian is the Accountholder who carries the card liability and so is the
  # only one who can create a card, raise a limit, or unfreeze.
  def cards?
    auditor_or_reader?
  end

  # Issuing a card creates a liability the guardian carries. Not the teen's to create.
  def issue_cards?
    return false if user.blank?
    return true if user.admin?

    # Fuime: same substitution as #setup_payments? and #decide_payout?. On a school
    # venture the liability sits with the institution, so the manager who acts for
    # it is the one who may create the liability. Without this branch "reinvest the
    # money rather than cash it out" was not actually available to a school
    # student — the balance was reachable only through a card nobody could issue.
    return manager? if record.institutionally_sponsored?

    guardian_reader?
  end

  # Limits, unfreezing, cancelling. Same reasoning as #issue_cards?: each of these
  # increases what can be spent or restores the ability to spend, which is the
  # Accountholder's decision.
  def manage_cards?
    return false if user.blank?
    return true if user.admin?

    return manager? if record.institutionally_sponsored?

    guardian_reader?
  end

  # Freezing is the deliberate exception, and it is the one control a minor SHOULD have.
  #
  # A teenager who has lost their card needs to stop it in the moment, not wait for a
  # parent to wake up. Freezing can only ever reduce what is spendable, so handing it to
  # the person most likely to notice a problem first costs nothing and prevents real
  # loss. Unfreezing stays with the guardian, which is what keeps this from being a way
  # around #manage_cards?.
  def freeze_cards?
    return false if user.blank?
    return true if user.admin?

    member? || guardian_reader?
  end

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
    OrganizerPosition.role_at_least?(user, record, :reader) || guardian_reader?
  end

  # Fuime: the guardian's side of that sentence, which until now had no
  # mechanism behind it. §3 of the guardian agreement promises the signing adult
  # visibility into "transactions, balances, and the people on their team", and
  # says it "cannot be turned off by the minor" — but accepting a guardianship
  # created no organizer position, so `reader?` was false for every guardian and
  # the promise was unimplemented.
  #
  # Granting it here rather than by inserting an OrganizerPosition at acceptance
  # is what makes the "cannot be turned off by the minor" half true: positions
  # are membership rows a manager can delete, and the minor is the manager.
  # See Guardianship.overseeing_event.
  #
  # Read-only by construction: `member?` and `manager?` do not consult this, so
  # a guardian can see a venture and act on nothing in it. Acting is the
  # minor's job, and a guardian who wants to intervene revokes instead.
  def guardian_reader?
    return false if user.blank?

    user.guardian_of_event?(record)
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

    # Fuime: the guardianship control asks "has an adult taken responsibility for
    # this minor?". On an institutionally sponsored org the school already has,
    # in loco parentis and under enrolment contracts its families signed. Without
    # this, a 14-year-old at a school would hold the correct member role on their
    # own venture and still be refused every action on it, because
    # User#needs_guardian? is fail-closed and no guardianship row exists — nor
    # should one.
    #
    # Scoped to this record, not to the user: the same student operating a
    # personal venture outside the school programme still needs a guardian.
    return true if record.institutionally_sponsored?

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
