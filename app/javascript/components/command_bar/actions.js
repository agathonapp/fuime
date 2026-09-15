/* eslint react/prop-types:0 */

import { Priority } from 'kbar'
import Icon from '@hackclub/icons'
import csrf from '../../common/csrf'
import React from 'react'
import SvgIcon, { preload } from '../icons/SvgIcon'

// FUIME: hashtag / cheque / reimbursement / wise / column dropped with the
// destinations that used them (see the FUIME note in adminActions). Preloading
// an icon for a row that no longer exists is five wasted requests on every page
// that renders the command bar.
preload('/icons/perks.svg', '/icons/receipt.svg')

const restrictedFilter = e => !e.demo_mode

export const generateEventActions = data => {
  return [
    ...data.map(event => ({
      id: event.slug,
      name: event.name,
      icon:
        event.logo && event.logo != 'none' ? (
          <img
            src={event.logo}
            height="16px"
            width="16px"
            style={{ borderRadius: '4px' }}
          />
        ) : (
          <Icon glyph="bank-account" size={16} />
        ),
      priority: !event.member ? Priority.LOW : Priority.HIGH,
      section: 'Organizations',
    })),
    ...data.map(event => ({
      id: `${event.slug}-home`,
      name: 'Home',
      perform: navigate(`/${event.slug}`),
      icon: <Icon glyph="home" size={16} />,
      parent: event.slug,
    })),
    ...data.filter(restrictedFilter).map(event => ({
      id: `${event.slug}-announcements`,
      name: 'Announcements',
      perform: navigate(`/${event.slug}/announcements`),
      icon: <Icon glyph="announcement" size={16} />,
      parent: event.slug,
    })),
    ...data.filter(restrictedFilter).map(event => ({
      id: `${event.slug}-transactions`,
      name: 'Transactions',
      perform: navigate(`/${event.slug}/transactions`),
      icon: <Icon glyph="bank-account" size={16} />,
      parent: event.slug,
      keywords: 'ledger payments',
    })),
    // FUIME: the venture rows below mirror app/helpers/events_helper.rb
    // NAV_ITEMS. Removed because the sidebar hides each of them via
    // `module_prefix` + Fuime::DisabledModules.blocked_prefixes, or because the
    // route is gone: Account numbers (no partner, `sponsor_banking?` off),
    // Donations, Invoices, Check deposits, Transfers, Grants, Google Workspace,
    // Reimbursements (route removed — was a 404). Added: the four Fuime pages a
    // founder actually lives on.
    ...data.map(event => ({
      id: `${event.slug}-offers`,
      name: 'What you sell',
      perform: navigate(`/${event.slug}/offers`),
      icon: <Icon glyph="bag" size={16} />,
      parent: event.slug,
      keywords: 'offers products prices storefront',
    })),
    ...data.map(event => ({
      id: `${event.slug}-sales`,
      name: 'Sales',
      perform: navigate(`/${event.slug}/sales`),
      icon: <Icon glyph="transactions" size={16} />,
      parent: event.slug,
    })),
    ...data.filter(restrictedFilter).map(event => ({
      id: `${event.slug}-payouts`,
      name: 'Payouts',
      perform: navigate(`/${event.slug}/payouts`),
      icon: <Icon glyph="payment-transfer" size={16} />,
      parent: event.slug,
    })),
    ...data.filter(restrictedFilter).map(event => ({
      id: `${event.slug}-payout-method`,
      name: 'Payout account',
      perform: navigate(`/${event.slug}/payout-method`),
      icon: <Icon glyph="payment" size={16} />,
      parent: event.slug,
      keywords: 'payout destination where money goes',
    })),
    ...data.map(event => ({
      id: `${event.slug}-cards`,
      name: 'Cards',
      perform: navigate(`/${event.slug}/cards`),
      icon: <Icon glyph="card" size={16} />,
      parent: event.slug,
    })),
    ...data.map(event => ({
      id: `${event.slug}-team`,
      name: 'Team',
      perform: navigate(`/${event.slug}/team`),
      icon: <Icon glyph="people-2" size={16} />,
      parent: event.slug,
    })),
    ...data.filter(restrictedFilter).map(event => ({
      id: `${event.slug}-perks`,
      name: 'Perks',
      perform: navigate(`/${event.slug}/promotions`),
      icon: <SvgIcon src="/icons/perks.svg" size={16} />,
      parent: event.slug,
    })),
    ...data.filter(restrictedFilter).map(event => ({
      id: `${event.slug}-documents`,
      name: 'Documents',
      perform: navigate(`/${event.slug}/documents`),
      icon: <Icon glyph="docs" size={16} />,
      parent: event.slug,
    })),
    ...data
      .filter(e => e.features.subevents)
      .map(event => ({
        id: `${event.slug}-subevents`,
        name: 'Sub-businesses',
        perform: navigate(`/${event.slug}/sub_organizations`),
        keywords: 'sub organizations subsidiary',
        icon: <Icon glyph="channels" size={16} />,
        parent: event.slug,
      })),
    ...data.filter(restrictedFilter).map(event => ({
      id: `${event.slug}-settings`,
      name: 'Settings',
      perform: navigate(`/${event.slug}/settings`),
      icon: <Icon glyph="settings" size={16} />,
      parent: event.slug,
    })),
  ]
}

export const initalActions = [
  {
    id: 'search-main',
    // FUIME-DIVERGENCE: "Search HCB" → "Search Fuime". This is the FIRST row of
    // the ⌘K palette and every signed-in user sees it, including teenagers who
    // have never heard of Hack Club. The two remaining "HCB" labels in
    // adminActions ("HCB codes", "HCB fees") were relabelled 2026-09-15 — see
    // the FUIME note there; no user-facing string in this file says HCB now.
    name: 'Search Fuime',
    keywords: 'search',
    icon: <Icon glyph="search" size={16} />,
    priority: Priority.HIGH,
  },
  {
    id: 'my-home',
    name: 'Home',
    keywords: 'index',
    perform: navigate('/'),
    icon: <Icon glyph="home" size={16} />,
    section: 'Pages',
    priority: Priority.HIGH,
  },
  {
    id: 'my-feed',
    name: 'Feed',
    keywords: 'index',
    perform: navigate('/my/feed'),
    icon: <Icon glyph="announcement" size={16} />,
    section: 'Pages',
    priority: Priority.HIGH,
  },
  {
    id: 'my-cards',
    name: 'Cards',
    keywords: 'cards',
    perform: navigate('/my/cards'),
    section: 'Pages',
    icon: <Icon glyph="card" size={16} />,
    priority: Priority.HIGH,
  },
  {
    id: 'my-receipts',
    name: 'Receipts',
    keywords: 'receipts inbox',
    perform: navigate('/my/inbox'),
    section: 'Pages',
    icon: <SvgIcon src="/icons/receipt.svg" size={16} />,
    priority: Priority.HIGH,
  },
  // FUIME: '/my/reimbursements' removed — the route is commented out in
  // config/routes.rb, so this row was a 404 in the top-level palette.
  {
    id: 'my-settings',
    name: 'Settings',
    keywords: 'settings',
    section: 'Pages',
    icon: <Icon glyph="settings" size={16} />,
    priority: Priority.HIGH,
  },
  {
    id: 'my-settings-account',
    name: 'Account',
    keywords: 'account profile personal name birthday picture email sign',
    perform: navigate('/my/settings'),
    parent: 'my-settings',
    icon: <Icon glyph="profile" size={16} />,
    priority: Priority.HIGH,
  },
  {
    id: 'my-settings-notifications',
    name: 'Notifications',
    keywords: 'notifications alerts emails',
    perform: navigate('/my/settings/notifications'),
    parent: 'my-settings',
    icon: <Icon glyph="notification" size={16} />,
    priority: Priority.HIGH,
  },
  {
    id: 'my-settings-payouts',
    name: 'Payout settings',
    // FUIME: L5 — the old keywords were 'reimbursement payouts payment bank
    // direct deposit'. Reimbursements are gone and the rest is forbidden
    // vocabulary while no partner bank exists.
    keywords: 'payouts payment destination where my money goes',
    perform: navigate('/my/settings/payouts'),
    parent: 'my-settings',
    icon: <Icon glyph="payment-transfer" size={16} />,
    priority: Priority.HIGH,
  },
  {
    id: 'my-settings-security',
    name: 'Security',
    keywords: 'security password authentication 2fa two-factor',
    perform: navigate('/my/settings/security'),
    parent: 'my-settings',
    icon: <Icon glyph="private" size={16} />,
    priority: Priority.HIGH,
  },
  {
    id: 'my-settings-previews',
    name: 'Feature previews',
    keywords: 'feature previews beta experimental',
    perform: navigate('/my/settings/previews'),
    parent: 'my-settings',
    icon: <Icon glyph="rep" size={16} />,
    priority: Priority.HIGH,
  },
  {
    id: `theme-light`,
    name: `Set theme to light`,
    section: 'Actions',
    icon: <Icon glyph="sun" size={16} />,
    keywords: 'theme light', // eslint-disable-next-line no-undef
    perform: () => BK.setDark('light'),
  },
  {
    id: `theme-dark`,
    name: `Set theme to dark`,
    section: 'Actions',
    icon: <Icon glyph="moon" size={16} />,
    keywords: 'theme dark', // eslint-disable-next-line no-undef
    perform: () => BK.setDark('dark'),
  },
  {
    id: `theme-system`,
    name: `Set theme to system`,
    section: 'Actions',
    icon: <Icon glyph="lightbulb" size={16} />,
    keywords: 'theme system', // eslint-disable-next-line no-undef
    perform: () => BK.setDark('system'),
  },
  {
    id: 'signout',
    name: 'Sign out',
    keywords: 'sign out logout log out',
    perform: () =>
      fetch('/users/logout', {
        method: 'DELETE',
        headers: {
          'Content-Type': 'application/json',
          'X-CSRF-Token': csrf(),
        },
      }).then(navigate('/')),
    section: 'Actions',
    icon: <Icon glyph="door-leave" size={16} />,
    priority: Priority.HIGH,
  },
]

export const adminActions = (adminUrls, isPretending) => {
  if (isPretending) {
    return [
      {
        id: 'admin-pretend',
        name: 'Stop pretending not to be an admin',
        keywords: 'pretend admin',
        perform: () =>
          fetch('/users/toggle_pretend_is_not_admin', {
            method: 'POST',
            headers: {
              'Content-Type': 'application/json',
              'X-CSRF-Token': csrf(),
            },
          }).then(navigate('/')),
        section: 'Actions',
        icon: <Icon glyph="bolt" size={16} />,
        priority: Priority.HIGH,
      },
    ]
  }
  return [
    {
      id: 'admin-pretend',
      name: 'Pretend to not be an admin',
      keywords: 'pretend admin',
      perform: () =>
        fetch('/users/toggle_pretend_is_not_admin', {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            'X-CSRF-Token': csrf(),
          },
        }).then(navigate('/')),
      section: 'Actions',
      icon: <Icon glyph="bolt" size={16} />,
      priority: Priority.HIGH,
    },
    // FUIME (2026-09-15): trimmed to what Fuime actually operates.
    //
    // This list was never touched during the admin cleanup, so it was a fourth
    // admin surface offering 20 destinations the other three had already
    // dropped. It navigates by hardcoded URL, not by path helper, so a removed
    // route degrades to a silent 404 instead of raising — which is why nobody
    // noticed. Keep it that way: every URL here must be checked against
    // config/routes.rb by hand.
    //
    // The three surfaces that must agree — this file,
    // app/models/admin/nav.rb, and StaticPagesHelper#admin_queues /
    // #admin_directories. Change one, change all three.
    //
    // Removed, and why:
    //   ACH transfers, Checks, Disbursements, Wires, Wise transfers,
    //   Reimbursements   — Admin::Nav#spending is FUIME-DISABLED; every one of
    //                      these rails is in SPONSOR_BANKING_CONTROLLER_PREFIXES.
    //   Employees, Payments, W9s — Admin::Nav#payroll is FUIME-DISABLED.
    //   Donations, Recurring donations, Sponsors, Check deposits
    //                    — nonprofit money-in; DISABLED/SPONSOR_BANKING.
    //   Google Workspaces, Account numbers, Bank accounts, Column statements,
    //   Intrafi transactions — no Column, no Plaid, no bank feeds, no G Suite.
    //   Card designs     — physical-card personalization; a later phase.
    //   Applications (HCB) — a duplicate of 'Applications' on the same URL.
    //
    // Do not re-add from upstream. Re-enabling a module means restoring its
    // Admin::Nav entry first; this list follows.
    // ledger
    {
      id: 'admin-ledger',
      section: 'Admin Tools',
      priority: Priority.HIGH,
      name: 'Ledger',
      icon: <Icon glyph="list" size={16} />,
      perform: navigate('/admin/ledger'),
    },
    {
      id: 'admin-pending-ledger',
      section: 'Admin Tools',
      priority: Priority.HIGH,
      name: 'Pending ledger',
      icon: <Icon glyph="list" size={16} />,
      perform: navigate('/admin/pending_ledger'),
    },
    {
      id: 'admin-raw-transactions',
      section: 'Admin Tools',
      priority: Priority.HIGH,
      name: 'Raw transactions',
      icon: <Icon glyph="list" size={16} />,
      perform: navigate('/admin/raw_transactions'),
    },
    {
      id: 'admin-hcb-codes',
      section: 'Admin Tools',
      priority: Priority.HIGH,
      // Admin::Nav calls this "Fuime Codes"; the tools page "Fuime codes".
      // `hcb` stays as a search keyword only — HcbCode is the model name
      // (Rule 6), and keywords are never rendered.
      name: 'Fuime codes',
      keywords: 'hcb codes',
      icon: <Icon glyph="list" size={16} />,
      perform: navigate('/admin/hcb_codes'),
    },
    {
      id: 'admin-unknown-merchants',
      section: 'Admin Tools',
      priority: Priority.HIGH,
      name: 'Unknown merchants',
      icon: <Icon glyph="search" size={16} />,
      perform: navigate('/admin/unknown_merchants'),
    },
    {
      id: 'admin-audits',
      section: 'Admin Tools',
      priority: Priority.HIGH,
      name: 'Audits',
      icon: <Icon glyph="flag" size={16} />,
      perform: navigate('/admin/ledger_audits'),
    },
    // incoming money
    {
      id: 'admin-invoices',
      section: 'Admin Tools',
      priority: Priority.HIGH,
      name: 'Invoices',
      icon: <Icon glyph="docs-fill" size={16} />,
      perform: navigate('/admin/invoices'),
    },
    // FUIME: the queues a human has to action. Every one of these is in
    // Admin::Nav and/or StaticPagesHelper#admin_queues and was reachable from
    // ⌘K only by typing the URL.
    {
      id: 'admin-payout-batches',
      section: 'Admin Tools',
      priority: Priority.HIGH,
      name: 'Payout runs',
      keywords: 'payouts batches pay operators',
      icon: <Icon glyph="payment-transfer" size={16} />,
      perform: navigate('/admin/payout_batches'),
    },
    {
      id: 'admin-subscriptions',
      section: 'Admin Tools',
      priority: Priority.HIGH,
      name: 'Subscriptions',
      keywords: 'family plan billing',
      icon: <Icon glyph="transactions" size={16} />,
      perform: navigate('/admin/subscriptions'),
    },
    {
      id: 'admin-waitlist',
      section: 'Admin Tools',
      priority: Priority.HIGH,
      name: 'Waitlist',
      icon: <Icon glyph="member-add" size={16} />,
      perform: navigate('/admin/waitlist'),
    },
    // organizations
    {
      id: 'admin-operator-vetting',
      section: 'Admin Tools',
      priority: Priority.HIGH,
      name: 'Operator vetting',
      keywords: 'vetting may they sell',
      icon: <Icon glyph="flag" size={16} />,
      perform: navigate('/admin/operator_vetting'),
    },
    {
      id: 'admin-cohorts',
      section: 'Admin Tools',
      priority: Priority.HIGH,
      name: 'Cohorts',
      icon: <Icon glyph="group" size={16} />,
      perform: navigate('/admin/cohorts'),
    },
    {
      id: 'admin-guardianships',
      section: 'Admin Tools',
      priority: Priority.HIGH,
      name: 'Guardian invites',
      keywords: 'guardianships parents stale',
      icon: <Icon glyph="people-2" size={16} />,
      perform: navigate('/admin/guardianships'),
    },
    {
      id: 'admin-organizations',
      section: 'Admin Tools',
      priority: Priority.HIGH,
      // StaticPagesHelper#admin_directories calls these "Businesses" and
      // "Business balances"; Admin::Nav still says "Organizations" /
      // "Organization Balances". Following the tools page — Fuime's product
      // word is business — with the old word kept as a search keyword.
      name: 'Businesses',
      keywords: 'organizations events ventures',
      icon: <Icon glyph="explore" size={16} />,
      perform: navigate('/admin/events'),
    },
    {
      id: 'admin-organization-balances',
      section: 'Admin Tools',
      priority: Priority.HIGH,
      name: 'Business balances',
      keywords: 'organization balances',
      icon: <Icon glyph="payment" size={16} />,
      perform: navigate('/admin/balances'),
    },
    {
      id: 'admin-opdrs',
      section: 'Admin Tools',
      priority: Priority.HIGH,
      name: 'OPDRs',
      icon: <Icon glyph="member-remove" size={16} />,
      perform: navigate('/organizer_position_deletion_requests'),
    },
    // misc
    {
      id: 'admin-blazer',
      section: 'Admin Tools',
      priority: Priority.HIGH,
      name: 'Blazer',
      icon: <Icon glyph="bolt" size={16} />,
      perform: navigate('/blazer'),
    },
    {
      id: 'admin-flipper',
      section: 'Admin Tools',
      priority: Priority.HIGH,
      name: 'Flipper',
      icon: <Icon glyph="flag-fill" size={16} />,
      perform: navigate('/flipper/features'),
    },
    {
      id: 'admin-common-documents',
      section: 'Admin Tools',
      priority: Priority.HIGH,
      name: 'Common documents',
      icon: <Icon glyph="docs" size={16} />,
      perform: navigate('/documents'),
    },
    {
      id: 'admin-hcb-fees',
      // Admin::Nav calls this "Fuime Fees". The old label said HCB (Rule 6
      // covers user-facing strings) and the row above it said "Bank accounts",
      // which L5 forbids while no partner bank exists — that destination is
      // Plaid-fed and gone from Admin::Nav anyway.
      section: 'Admin Tools',
      priority: Priority.HIGH,
      name: 'Fuime fees',
      icon: <Icon glyph="bank-circle" size={16} />,
      perform: navigate('/admin/bank_fees'),
    },
    {
      id: 'admin-fee-revenues',
      section: 'Admin Tools',
      priority: Priority.HIGH,
      name: 'Fee revenues',
      icon: <Icon glyph="bank-circle" size={16} />,
      perform: navigate('/admin/fee_revenues'),
    },
    {
      id: 'admin-users',
      section: 'Admin Tools',
      priority: Priority.HIGH,
      name: 'Users',
      icon: <Icon glyph="leaders" size={16} />,
      perform: navigate('/admin/users'),
    },
    {
      id: 'admin-cards',
      section: 'Admin Tools',
      priority: Priority.HIGH,
      name: 'Cards',
      icon: <Icon glyph="card" size={16} />,
      perform: navigate('/admin/stripe_cards'),
    },
    {
      id: 'admin-emails',
      section: 'Admin Tools',
      priority: Priority.HIGH,
      name: 'Emails',
      icon: <Icon glyph="email" size={16} />,
      perform: navigate('/admin/emails'),
    },
    {
      id: 'admin-referral-programs',
      section: 'Admin Tools',
      priority: Priority.HIGH,
      name: 'Referral programs',
      icon: <Icon glyph="share" size={16} />,
      perform: navigate('/admin/referral_programs'),
    },
    {
      id: 'admin-event-groups',
      section: 'Admin Tools',
      priority: Priority.HIGH,
      name: 'Event groups',
      icon: <Icon glyph="group" size={16} />,
      perform: navigate('/admin/event_groups'),
    },
    {
      id: 'admin-contracts',
      section: 'Admin Tools',
      priority: Priority.HIGH,
      name: 'Contracts',
      icon: <Icon glyph="docs" size={16} />,
      perform: navigate('/admin/contracts'),
    },
    {
      id: 'admin-active-teens-leaderboard',
      section: 'Admin Tools',
      priority: Priority.HIGH,
      name: 'Active teenagers leaderboard',
      icon: <Icon glyph="leader" size={16} />,
      perform: navigate('/admin/active_teenagers_leaderboard'),
    },
    {
      id: 'admin-new-teens-leaderboard',
      section: 'Admin Tools',
      priority: Priority.HIGH,
      name: 'New teenagers leaderboard',
      icon: <Icon glyph="member-add" size={16} />,
      perform: navigate('/admin/new_teenagers_leaderboard'),
    },
    // FUIME-DIVERGENCE: applications are reviewed in this admin console, not
    // Airtable. The Hack Club perk/program entries (stickers, 1Password, domains,
    // hackathons, PVSA, The Event Helper, Google Workspace waitlist) were all backed
    // by Hack Club Airtable bases and have no Fuime equivalent.
    //
    // The duplicate 'Applications (HCB)' row that pointed at this same URL is
    // gone; Admin::Nav calls the page "Applications (Fuime)" and the tools page
    // "Applications".
    {
      id: 'admin-applications',
      section: 'Admin Tools',
      priority: Priority.HIGH,
      name: 'Applications',
      icon: <Icon glyph="align-left" size={16} />,
      perform: navigate('/admin/applications'),
    },
  ]
}

function navigate(to) {
  return () => {
    if (to.startsWith('https://')) {
      window.open(to, '_blank')
    } else {
      window.Turbo.visit(to)
    }
    window?.FS?.event('command_bar_navigation', {
      query: document.querySelector('[role="combobox"]').value,
      to,
    })
  }
}
