# frozen_string_literal: true

require "cgi"

module EventsHelper
  # Items in the NAV_ITEMS array can be either nav links or sections, and are rendered in order:

  # Nav link schema
  # name (string): nav item name, displayed in sidebar and placeholder page
  # path_proc (event_id -> string): path used as link href
  # tooltip (string): description shown on hover and on placeholder page
  # dynamic_tooltip (event -> string): different tooltip to show based on event data
  # icon (string): name of icon to display beside name
  # symbol (symbol): shows nav item as selected when matches with argument passed to event_nav
  # available_proc (event -> boolean): whether or not the nav item is available for the given event
  # adminTool (boolean, optional): whether or not the nav item is shown as an admin tool
  # async_badge_proc (event -> string, optional): path to a turbo frame that will be displayed as a badge in the top-right corner of the icon
  # data (hash, optional): HTML data attributes on the link

  # Section schema
  # section (string): name of the section
  # available_proc (event -> boolean): whether or not the section header should be shown for the given event

  # Dropdown menu schema
  # dropdown (string): name of the dropdown menu
  # available_proc (event -> boolean): whether or not the dropdown and any of its items are available for the given event
  # tooltip (string): description shown on hover and on placeholder page
  # icon (string): name of icon to display beside name
  # dropdown_items (array of nav links): nav links for this dropdown menu. icon, async_badge_proc, and dynamic_tooltip are not supported.

  NAV_ITEMS = [
    {
      name: "Activate",
      path_proc: ->(event_id) { event_activation_flow_path(event_id:) },
      tooltip: "Activate this organization",
      icon: "checkmark",
      symbol: :activation_flow,
      adminTool: true,
      available_proc: ->(event) { policy(event).activation_flow? }
    },
    {
      name: "Sign",
      path_proc: lambda do |event_id|
        event = Event.friendly.find_by_friendly_id(event_id)
        if event.present?
          contract_party_path(event.contracts_pending_on_hcb.first.party(:hcb))
        else
          nil
        end
      end,
      tooltip: "Sign the Fuime agreement as Fuime",
      icon: "checkmark",
      adminTool: true,
      available_proc: ->(event) { event.financially_frozen? && event.contracts_pending_on_hcb.one? && event.contracts.signed.none? }
    },
    {
      name: "Home",
      path_proc: ->(event_id) { event_path(id: event_id) },
      tooltip: "See everything at-a-glance",
      icon: "home",
      symbol: :home,
      available_proc: ->(event) { policy(event).show? }
    },
    # Fuime: payment setup (guardian-owned Stripe account) nav item.
    #
    # Visible to the whole team, not just the guardian, because a teen needs to
    # see whether their venture can be paid; the page itself decides who gets the
    # button.
    #
    # No `async_badge_proc`: that field takes a path to a turbo frame, not a badge
    # string, so signalling "setup unfinished" through it would need its own
    # endpoint. Left off rather than misused — the storefront and the status page
    # both say plainly when a venture cannot be paid.
    #
    # `icon:` is verified to exist in app/assets/images/icons — `inline_icon`
    # raises Errno::ENOENT on a missing SVG, which 500s the entire org nav rather
    # than just this item (see the Taxes note below).
    {
      name: "Payments",
      path_proc: ->(event_id) { fuime_payment_setup_path(event_slug: event_id) },
      tooltip: "Set up and check how this venture gets paid",
      icon: "bank-account",
      symbol: :payments,
      # Fuime: hidden under merchant-of-record, because there is nothing to set up.
      #
      # This screen is the Connect path: Stripe asks the guardian for an SSN
      # last-4, a home address, a phone number, an MCC, a business URL and ToS
      # acceptance BEFORE a teenager can sell anything. Under MoR the money is
      # Fuime's own revenue from Fuime's own sale, so no merchant account exists
      # for the operator to open — the only thing they need is a payout
      # destination, and that is asked when they have money to send.
      #
      # Reads the flag rather than being deleted, so the two models swap cleanly
      # in either direction (Rule 2).
      available_proc: lambda { |event|
        !::Fuime::Features.merchant_of_record? &&
          policy(event).payment_setup_status? && organizer_signed_in?
      }
    },
    # Fuime: what the venture sells.
    #
    # Ahead of Payments and Payouts because it is the first thing a founder
    # actually does — the money screens are about a business that already has
    # something to sell, and until offers existed the storefront was a box a
    # stranger typed an amount into. See Fuime::Offer.
    #
    # `bag.svg` is verified to exist in app/assets/images/icons — a missing icon
    # 500s the whole org nav rather than just one entry (see the Taxes note).
    {
      name: "What you sell",
      path_proc: ->(event_id) { fuime_offers_path(event_slug: event_id) },
      tooltip: "List what you sell and set your prices",
      icon: "bag",
      symbol: :offers,
      available_proc: ->(event) { policy(event).offers? && organizer_signed_in? }
    },
    # Fuime: Payouts — moving money to the family's bank.
    #
    # Separate from "Payments" above because they are opposite directions and
    # different people act on them: Payments is the guardian setting up how money
    # comes IN, Payouts is the teen asking for money to go OUT and the guardian
    # deciding. Collapsing them into one screen would bury the approval, which is
    # the control that makes the ownership structure real (CLAUDE.md L2).
    #
    # `cash.svg` is verified to exist in app/assets/images/icons — see the note on
    # the Taxes item below for why a missing icon 500s the whole org nav rather
    # than just one entry.
    {
      name: "Payouts",
      path_proc: ->(event_id) { fuime_payouts_path(event_slug: event_id) },
      tooltip: "Move money to your bank account",
      icon: "cash",
      symbol: :payouts,
      available_proc: ->(event) { policy(event).payouts? && organizer_signed_in? }
    },
    # Fuime: money the school put in ("$100 per A").
    #
    # Only shown inside a school programme, because on a family venture there is no
    # shared account for an award to move within and the page would say so and nothing
    # else. `shares_payment_account?` rather than `institutionally_sponsored?` — a
    # school tree that has not onboarded Stripe yet has nowhere to move money from.
    #
    # `bank-account.svg` is verified to exist in app/assets/images/icons (there is no
    # bare `bank.svg` — the family is bank-account/bank-circle/bank-icon). See the
    # Taxes note below for why a missing icon 500s the whole org nav rather than one
    # entry.
    {
      name: "School awards",
      path_proc: ->(event_id) { fuime_school_awards_path(event_slug: event_id) },
      tooltip: "Money your school has put into this venture",
      icon: "bank-account",
      symbol: :awards,
      available_proc: lambda { |event|
        event.shares_payment_account? && policy(event).school_awards? && organizer_signed_in?
      }
    },
    # Fuime: the school's own treasury page — the counterpart to School awards, and
    # the answer to "the school has nothing to award".
    #
    # The mirror image of the entry above in every way: that one appears on the
    # STUDENT venture (which shares an account upward), this one only on the school
    # ITSELF (which owns the account a top-up funds), and this one is manager-only.
    # A student never sees it — the balance it leads to is the whole programme's.
    {
      name: "Add funds",
      path_proc: ->(event_id) { fuime_school_fundings_path(event_slug: event_id) },
      tooltip: "Put money into your school's account so you can award it",
      icon: "bank-account",
      symbol: :funding,
      available_proc: lambda { |event|
        policy(event).fund_school? && organizer_signed_in?
      }
    },
    # Fuime: business cards.
    #
    # Only shown for ventures whose Stripe account was actually created with card
    # support — `controller` is create-only, so a payments-only venture can never have
    # cards and a nav item leading to a permanent dead end is worse than no nav item.
    #
    # `card-list.svg` is verified to exist in app/assets/images/icons; a missing icon
    # 500s the whole org nav (see the Taxes note below).
    {
      name: "Cards",
      path_proc: ->(event_id) { fuime_cards_path(event_slug: event_id) },
      tooltip: "Business cards for buying supplies",
      icon: "card-list",
      symbol: :cards,
      available_proc: lambda { |event|
        policy(event).cards? && organizer_signed_in? &&
          event.payment_account&.cards_profile?
      }
    },
    # Fuime: Tax Tracker nav item
    {
      name: "Taxes",
      path_proc: ->(event_id) { fuime_taxes_path(event_slug: event_id) },
      tooltip: "Track income toward IRS threshold",
      # `inline_icon` reads the SVG off disk and raises Errno::ENOENT if it is
      # missing, which 500s every page rendering the org nav — not just the
      # Taxes item. "money-dollar-box" does not exist in app/assets/images/icons.
      icon: "calculator",
      symbol: :taxes,
      available_proc: ->(event) { policy(event).show? && organizer_signed_in? }
    },
    {
      name: "Announcements",
      path_proc: ->(event_id) { event_announcement_overview_path(event_id:) },
      tooltip: "View your announcements",
      icon: "announcement",
      symbol: :announcements,
      available_proc: ->(event) { policy(event).announcement_overview? }
    },
    {
      name: "Transactions",
      path_proc: ->(event_id) { (organizer_signed_in? && Flipper.enabled?(:new_ledger_2026_07_17, current_user) ? event_ledger_path(event_id:) : event_transactions_path(event_id:)) },
      tooltip: "View detailed ledger",
      icon: "bank-account",
      symbol: :transactions,
      available_proc: ->(event) { policy(event).transactions? }
    },
    {
      name: "Account numbers",
      path_proc: ->(event_id) { account_number_event_path(id: event_id) },
      tooltip: "View account numbers",
      icon: "hashtag",
      symbol: :account_number,
      # Fuime: hidden until Fuime holds funds somewhere that has account numbers.
      #
      # The one gated item that cannot use `module_prefix`: it is served by
      # EventsController, so a prefix rule would take every venture page down with
      # it. Upstream this is real — HCB holds funds at a partner bank and an org
      # genuinely has a routing and account number. Fuime holds none and has no
      # such relationship, so the page shows a number nobody can send money to.
      #
      # `sponsor_banking?` rather than a bare `false`, so it returns with the
      # feature rather than needing somebody to remember this line (Rule 2).
      available_proc: lambda { |event|
        ::Fuime::Features.sponsor_banking? && policy(event).account_number?
      }
    },
    {
      section: "Receive",
      available_proc: ->(event) { policy(event).donation_overview? || policy(event).invoices? || policy(event.check_deposits.build).index? }
    },
    {
      name: "Donations",
      module_prefix: "donations",
      path_proc: ->(event_id) { event_donation_overview_path(event_id:) },
      tooltip: "Support this organization",
      icon: "support",
      data: { tour_step: "donations" },
      symbol: :donations,
      available_proc: ->(event) { policy(event).donation_overview? }
    },
    {
      name: "Invoices",
      path_proc: ->(event_id) { event_invoices_path(event_id:) },
      tooltip: "Collect sponsor payments",
      icon: "payment-docs",
      symbol: :invoices,
      available_proc: ->(event) { policy(event).invoices? }
    },
    {
      name: "Check deposits",
      module_prefix: "check_deposits",
      path_proc: ->(event_id) { event_check_deposits_path(event_id:) },
      tooltip: "Deposit a check",
      icon: "cheque",
      symbol: :deposit_check,
      available_proc: ->(event) { policy(event.check_deposits.build).index? }
    },
    {
      section: "Spend",
      available_proc: ->(event) { policy(event).card_overview? || policy(event).card_grant_overview? || policy(event).transfers? || policy(event).reimbursements? || policy(event).employees? }
    },
    {
      name: "Cards",
      path_proc: ->(event_id) { event_cards_overview_path(event_id:) },
      tooltip: "Manage team Fuime cards",
      icon: "card",
      data: { tour_step: "cards" },
      symbol: :cards,
      available_proc: ->(event) { policy(event).card_overview? }
    },
    {
      name: "Grants",
      module_prefix: "card_grants",
      path_proc: ->(event_id) { event_card_grant_overview_path(event_id:) },
      tooltip: "Manage card grants",
      icon: "bag",
      symbol: :card_grants,
      available_proc: ->(event) { policy(event).card_grant_overview? }
    },
    {
      name: "Transfers",
      module_prefix: "ach_transfers",
      path_proc: ->(event_id) { event_transfers_path(event_id:) },
      tooltip: "Send & transfer money",
      icon: "payment-transfer",
      symbol: :transfers,
      available_proc: ->(event) { policy(event).transfers? && !Flipper.enabled?(:payments_contractors_refresh_2026_06_26, event) }
    },
    {
      name: "Payments",
      path_proc: ->(event_id) { event_payments_path(event_id:) },
      tooltip: "Send & transfer money",
      icon: "payment-transfer",
      symbol: :payments,
      available_proc: ->(event) { policy(event).payments? }
    },
    {
      name: "Contractors",
      path_proc: ->(event_id) { event_contractors_path(event_id:) },
      tooltip: "Manage payroll",
      icon: "person-badge",
      symbol: :contractors,
      beta: true,
      available_proc: ->(event) { policy(event).contractors? }
    },
    {
      name: "Reimbursements",
      path_proc: ->(event_id) { event_reimbursements_path(event_id:) },
      async_badge_proc: ->(event) { event_reimbursements_pending_review_icon_path(event) },
      tooltip: "Reimburse team members & volunteers",
      icon: "reimbursement",
      symbol: :reimbursements,
      available_proc: ->(event) { policy(event).reimbursements? }
    },
    {
      section: "",
      available_proc: ->(event) { policy(event).team? || policy(event).promotions? || policy(event).g_suite_overview? || policy(event).documentation? || policy(event).sub_organizations? }
    },
    {
      name: "Team",
      path_proc: ->(event_id) { event_team_path(event_id:) },
      tooltip: "Manage your team",
      icon: "people-2",
      symbol: :team,
      available_proc: ->(event) { policy(event).team? }
    },
    {
      name: "Perks",
      path_proc: ->(event_id) { event_promotions_path(event_id:) },
      tooltip: "Receive promos & discounts",
      dynamic_tooltip: ->(event) { !policy(event).promotions? ? "Your account isn't eligble for receive promos & discounts" : "Receive promos & discounts" },
      icon: "perks",
      data: { tour_step: "perks" },
      symbol: :promotions,
      available_proc: ->(event) { policy(event).promotions? }
    },
    {
      name: "Google Workspace",
      module_prefix: "g_suite",
      path_proc: ->(event_id) { event_g_suite_overview_path(event_id:) },
      tooltip: "Manage domain Google Workspace",
      dynamic_tooltip: lambda do |event|
        if !policy(event).g_suite_overview?
          "Your organization isn't eligible for Google Workspace."
        else
          if event.g_suites.any?
            "Manage domain Google Workspace"
          else
            Flipper.enabled?(:google_workspace, event) ? "Set up domain Google Workspace" : "Register for Google Workspace Waitlist"
          end
        end
      end,
      icon: "google",
      symbol: :google_workspace,
      available_proc: ->(event) { policy(event).g_suite_overview? }
    },
    {
      name: "Documents",
      path_proc: ->(event_id) { event_documents_path(event_id:) },
      tooltip: "View legal documents and financial statements",
      icon: "docs",
      symbol: :documentation,
      available_proc: ->(event) { policy(event).documentation? }
    },
    {
      name: "Sub-organizations",
      path_proc: ->(event_id) { event_sub_organizations_path(event_id:) },
      tooltip: "Create & manage subsidiary organizations",
      icon: "channels",
      symbol: :sub_organizations,
      available_proc: ->(event) { policy(event).sub_organizations? }
    },
    {
      dropdown: "Settings",
      available_proc: ->(event) { policy(event).edit? },
      tooltip: "Edit organization settings",
      icon: "settings",
      dropdown_items: [
        {
          name: "Organization",
          path_proc: ->(event_id) { edit_event_path(event_id, tab: "details") },
          tooltip: "Edit organization details and visibility",
          symbol: :settings_details,
          available_proc: ->(event) { true },
        },
        {
          name: "Donations",
          module_prefix: "donations",
          path_proc: ->(event_id) { edit_event_path(event_id, tab: "donations") },
          tooltip: "Edit donation page, goals, and tiers",
          symbol: :settings_donations,
          available_proc: ->(event) { event.approved? && event.plan.donations_enabled? }
        },
        {
          name: "Reimbursements",
          path_proc: ->(event_id) { edit_event_path(event_id, tab: "reimbursements") },
          tooltip: "Edit reimbursement page and review requirements",
          symbol: :settings_reimbursements,
          available_proc: ->(event) { event.approved? && event.plan.reimbursements_enabled? }
        },
        {
          name: "Card grants",
          path_proc: ->(event_id) { edit_event_path(event_id, tab: "card_grants") },
          tooltip: "Edit card grant default settings, restrictions, and support",
          symbol: :settings_card_grants,
          available_proc: ->(event) { event.approved? && event.plan.card_grants_enabled? },
        },
        {
          name: "Tags",
          path_proc: ->(event_id) { edit_event_path(event_id, tab: "tags") },
          tooltip: "Manage transaction tags",
          symbol: :settings_tags,
          available_proc: ->(event) { true }
        },
        {
          name: "Affiliations",
          path_proc: ->(event_id) { edit_event_path(event_id, tab: "affiliations") },
          tooltip: "Update organization affiliations",
          symbol: :settings_affiliations,
          available_proc: ->(event) { true }
        },
        {
          name: "Integrations",
          path_proc: ->(event_id) { edit_event_path(event_id, tab: "integrations") },
          tooltip: "Setup and manage integrations with Fuime",
          symbol: :settings_integrations,
          available_proc: ->(event) { true }
        },
        {
          name: "Feature previews",
          path_proc: ->(event_id) { edit_event_path(event_id, tab: "features") },
          tooltip: "Enable new Fuime features",
          symbol: :settings_features,
          available_proc: ->(event) { true }
        },
        {
          name: "Audit log",
          path_proc: ->(event_id) { edit_event_path(event_id, tab: "audit_log") },
          tooltip: "View all organization activity",
          symbol: :settings_audit_log,
          available_proc: ->(event) { true }
        },
        {
          name: "Admin",
          path_proc: ->(event_id) { edit_event_path(@event, tab: "admin") },
          symbol: :settings_admin,
          available_proc: ->(event) { true },
          adminTool: true
        }
      ]
    }
  ].freeze

  # Fuime: is this nav item's controller one Fuime has turned off?
  #
  # ── Why the nav asks the blocker rather than carrying its own list ─────────
  #
  # `Fuime::DisabledModules` already refuses these at the request level, so
  # every one of them was a link to a page that answers "That feature isn't
  # available on Fuime." A teenager clicking "Deposit a check" and being bounced
  # is worse than not seeing it: it reads as broken rather than as absent, and
  # Milestone 5's own verification step says a click-through must find no dead
  # nav links.
  #
  # Driven off `DisabledModules.blocked_prefixes` rather than a second hardcoded
  # list, because the answer depends on feature flags — `sponsor_banking?` and
  # `card_issuing_permitted?` — and two lists that must agree eventually will
  # not. Flip a flag and the nav item returns on its own, which is what Rule 2's
  # "disable, don't delete" is supposed to feel like.
  #
  # GETs are still permitted by the blocker (a transaction drawer legitimately
  # links to an existing ACH transfer's detail page). This hides the *entry
  # point* — you cannot start one — without breaking a deep link to a record
  # that already exists.
  def fuime_module_hidden?(prefix)
    return false if prefix.blank?

    ::Fuime::DisabledModules.blocked_prefixes.include?(prefix)
  end

  def events_nav(event = @event, selected: nil)
    NAV_ITEMS.reject { |i| fuime_module_hidden?(i[:module_prefix]) }
             .select { |i| instance_exec(event, &i[:available_proc]) }.map do |item|
      item.dup.tap do |h|
        if h[:dropdown].present?
          h[:dropdown_items] = h[:dropdown_items].reject { |i| fuime_module_hidden?(i[:module_prefix]) }
                                                 .select { |i| instance_exec(event, &i[:available_proc]) }.map do |dropdown_item|
            dropdown_item[:selected] = dropdown_item[:symbol] == selected if dropdown_item[:symbol].present?
            dropdown_item[:path] = instance_exec(event.slug, &dropdown_item[:path_proc]) if dropdown_item[:path_proc].present?

            dropdown_item
          end
          h[:selected] = h[:dropdown_items].any? { |i| i[:selected] }
        else
          h[:selected] = h[:symbol] == selected if h[:symbol].present?
        end

        h[:path] = instance_exec(event.slug, &h[:path_proc]) if h[:path_proc].present?
        h[:async_badge] = instance_exec(event, &h[:async_badge_proc]) if h[:async_badge_proc].present?
        h[:tooltip] = instance_exec(event, &h[:dynamic_tooltip]) if h[:dynamic_tooltip].present?
      end
    end
  end

  def dock_item(name, url = nil, icon: nil, tooltip: nil, async_badge: nil, disabled: false, selected: false, admin: false, beta: false, **options)
    icon_tag = icon.present? ? inline_icon(icon, size: 32) : nil
    badge_tag = async_badge.present? ? turbo_frame_tag(async_badge, src: async_badge, data: { controller: "cached-frame", action: "turbo:frame-render->cached-frame#cache" }) : nil

    icon_wrapper =
      if icon_tag || badge_tag
        content_tag(:div, class: "dock__item-icon-wrapper") do
          safe_join([icon_tag, badge_tag].compact)
        end
      end

    children = []
    children << icon_wrapper if icon_wrapper
    children << tag.span(name, class: "dock__item-label")
    children << tag.span("BETA", class: "badge bg-info text-xs ml-3") if beta
    children = safe_join(children)

    if admin && !auditor_signed_in?
      return ""
    end

    link_to children, (disabled ? "javascript:" : url), options.merge(
      class: "dock__item #{"tooltipped tooltipped--e" if tooltip} #{"disabled" if disabled} #{"admin-tools" if admin}",
      'aria-label': tooltip,
      'aria-current': selected ? "page" : "false",
      'aria-disabled': disabled ? "true" : "false",
    )
  end

  # Playground Mode's mock data, restored from upstream (removed there in
  # 73d010de6, "Remove playground mode & mock data"). Fuime keeps Playground
  # Mode as a live product surface — an empty org is a bad demo — so the stub
  # that commit left behind (`false`) is back to the real implementation.
  #
  # Session-scoped per event, so two orgs can be viewed differently in one
  # session and nothing about the org record changes when it is toggled.
  def show_mock_data?(event = @event)
    event&.demo_mode? && session[mock_data_session_key(event)]
  end

  def set_mock_data!(bool = true, event = @event)
    session[mock_data_session_key(event)] = bool
  end

  def mock_data_session_key(event = @event)
    "show_mock_data_#{event.id}".to_sym
  end

  def paypal_transfers_airtable_form_url(embed: false, event: nil, user: nil)
    # The airtable form is located within the Bank Promotions base
    form_id = "4j6xJB5hoRus"
    embed_url = "https://forms.hackclub.com/t/#{form_id}"
    url = "https://forms.hackclub.com/t/#{form_id}"

    prefill = []
    prefill << "prefill_Event/Project+Name=#{CGI.escape(event.name)}" if event
    prefill << "prefill_Submitter+Name=#{CGI.escape(user.full_name)}" if user
    prefill << "prefill_Submitter+Email=#{CGI.escape(user.email)}" if user

    "#{embed ? embed_url : url}?#{prefill.join("&")}"
  end

  def transaction_memo(tx)
    # needed to handle mock data in playground mode
    if tx.local_hcb_code.method(:memo).parameters.empty?
      tx.local_hcb_code.memo
    else
      tx.local_hcb_code.memo(event: @event)
    end
  end

  def humanize_audit_log_value(field, value)

    if field == "point_of_contact_id"
      return User.find(value).email
    end

    if field == "maximum_amount_cents"
      return render_money(value.to_s)
    end

    if field == "event_id"
      return Event.find(value).name
    end

    if field == "reviewer_id"
      return User.find(value).name
    end

    return "Yes" if value == true
    return "No" if value == false

    if field.ends_with?("_at")
      begin
        return local_time(value)
      rescue
        return value
      end
    end

    return value
  end

  def render_audit_log_field(field)
    field.delete_suffix("_cents").humanize
  end

  def render_audit_log_value(field, value, color:)
    return tag.span "unset", class: "muted" if value.nil? || value.try(:empty?)

    return tag.span humanize_audit_log_value(field, value), class: color
  end

  def show_org_switcher?
    signed_in? && current_user.events.not_hidden.count > 1
  end

  def check_filters?(filter_options, params)
    filter_options.any? do |opt|
      key = opt[:key].to_s

      case opt[:type]
      when "date_range"
        params["#{opt[:key_base]}_before"].present? || params["#{opt[:key_base]}_after"].present?
      when "amount_range"
        params["#{opt[:key_base]}_less_than"].present? || params["#{opt[:key_base]}_greater_than"].present?
      else
        params[key].present?
      end
    end
  end

  def validate_filter_options(filter_options, params)
    filter_options.each do |opt|
      case opt[:type]
      when "date_range"
        validate_date_range(opt[:key_base], params)
      when "amount_range"
        validate_amount_range(opt[:key_base], params)
      end
    end
  end

  def auto_discover_feed(event)
    if event.announcements.any?
      content_for :head do
        auto_discovery_link_tag :atom, event_feed_url(event, format: :atom), title: "Announcements for #{event.name}"
      end
    end
  end

  private

  def validate_date_range(base, params)
    less = params["#{base}_after"]
    greater = params["#{base}_before"]
    return unless less.present? && greater.present?

    begin
      less_date = Date.parse(less)
      greater_date = Date.parse(greater)
      if greater_date < less_date
        flash[:error] = "Invalid date range: 'after' date is greater than 'before' date"
      end
    rescue ArgumentError
      flash[:error] = "Invalid date format"
    end
  end

  def validate_amount_range(base, params)
    less = params["#{base}_less_than"]
    greater = params["#{base}_greater_than"]
    return unless less.present? && greater.present?

    if greater.to_f > less.to_f
      flash[:error] = "Invalid amount range: minimum is greater than maximum"
    end
  end

end
