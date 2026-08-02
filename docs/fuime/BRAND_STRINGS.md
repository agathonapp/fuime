# Brand strings — what was changed, and what deliberately was not

Milestone 3 deliverable (CLAUDE.md: "listing every file touched"). This covers
the whole rebrand, including the two earlier passes logged in
`UPSTREAM_DIVERGENCE.md` under *Milestone 3: surface rebrand* and *Milestone 3
(cont.)*, plus the closing pass on 2026-08-02.

The useful content here is not the file list — `git log` has that. It is the
**classification**: which occurrences of "HCB" and "Hack Club" are branding,
which are load-bearing data, and which are legally required to stay.

---

## The four categories

Every `HCB` / `Hack Club` / `hackclub.com` occurrence falls into one of these.
Decide which one you are looking at *before* editing it.

### 1. Branding — change freely

Display copy naming the product: page titles, nav labels, button text, mailer
bodies, tooltips. This is what Milestone 3 exists to change.

### 2. Upstream attribution — must NOT change (CLAUDE.md Rule 7)

The AGPL requires the fork be identified. Three lines say "Fuime is a fork of
HCB by Hack Club" and name the *upstream project*, not Fuime:

| File | Line |
|---|---|
| `app/views/application/_footer.html.erb` | 8 |
| `app/views/layouts/_head.html.erb` | 31 |
| `app/views/layouts/mailer/_footer.html.erb` | 10 |

A blanket replace previously turned these into "Fuime is a fork of **Fuime** by
Hack Club". Restored verbatim; do not touch again.

### 3. Legal identity — must NOT change, and must not be claimed

Text naming **The Hack Foundation**, its d.b.a., or its EIN **81-2908499**.
Rewriting "d.b.a. Hack Club" to "d.b.a. Fuime" asserts that Fuime is a d.b.a.
of Hack Club's charity and claims their EIN. That is false and was reverted in
12 mailers.

The correct action for this category is usually to **remove the document or
disable the page**, not to rebrand it. See "Disabled rather than rebranded".

### 4. Load-bearing data — changing it corrupts the ledger

`HCB` is a **stored data prefix**, not only a brand. These are compared against
or written to the database:

| File | What |
|---|---|
| `app/services/transaction_grouping_engine/calculate/hcb_code.rb` | `HCB_CODE = "HCB"` — the prefix every HCB code in the DB is built from |
| `app/models/canonical_transaction.rb` | `ilike '%Hack Club Bank Fee TO ACCOUNT%'` and ~6 sibling scopes — bank **memo** strings |
| `app/models/transaction.rb` | `start_with?("Hack Club Bank PAYOUT", …)`, `/(?:HACKC\|Hack Club Bank) PAYOUT/` — parses real bank memos |
| `app/models/event_tag.rb` | `HACK_CLUB = "Hack Club"` — a persisted tag value |

**Rule:** before replacing `HCB` in a `.rb` file, check whether the literal is
compared against or written to the database. `HCB-` followed by digits, an
interpolation, or `\w{5}` is data, never branding. A previous sweep rewrote
`HCB_CODE = "HCB"` to `"Fuime"`, which orphaned all existing ledger data and
broke 10 `statement_of_activity` specs.

---

## Disabled rather than rebranded

Some surfaces have no truthful Fuime version, because they describe a
501(c)(3) fiscal-sponsorship product Fuime is not. Rebranding them would turn a
true statement about Hack Club into a false one about Fuime. These are disabled
(CLAUDE.md Rule 2 — views and actions remain).

| Surface | Mechanism | Why |
|---|---|---|
| Fiscal sponsorship letter | routes removed (`config/routes.rb`) | PDF on Hack Club letterhead — their logo, a real employee's scanned signature, EIN 81-2908499 — certifying The Hack Foundation as the business's fiscal sponsor |
| Verification letter | routes removed | Same letterhead, plus an attestation of an account "in good standing with **Column N.A.**, a Member of the FDIC" and printed account + routing numbers. A bank-verification document Fuime cannot substantiate |
| Termination agreement | `EventPolicy#termination?` → false | Legal document terminating "the Agreement between The Hack Foundation and \<business\>", transferring "the balance of assets in Hack Club's restricted Fund" |
| Perks page | `EventPolicy#promotions?` → false | Every perk is a Hack Club program (HCB stickers, their 1Password / StickerNinja / Replit / GitHub partnerships, hackathon grants). The PVSA perk claimed the user could issue Presidential Volunteer Service Awards — eligibility that depends on 501(c)(3) status Fuime lacks |
| Google Workspace, Cards, Donations overviews | `EventPolicy#{g_suite,card,donation}_overview?` → false | See "trap pages" below |
| `/for/funders*` | `MarketingController` before_action | JSON-LD declared `"legalName": "The Hack Foundation"` with `taxID: 81-2908499` on an indexable page |
| Changelog widget | partial renders nothing | See "Live calls to Hack Club infrastructure" |

### The "trap page" pattern — worth understanding before adding more modules

`Fuime::DisabledModules` blocks **writes only**, deliberately: it preserves read
access to records inherited from upstream. But the *nav* entries for Cards,
Donations and Google Workspace were gated on `EventPolicy` predicates that only
checked plan features — and `Event::Plan::Standard` (the default for every new
org via `EventService::Create`) enables all three.

Net effect: a normal Fuime org member saw three sidebar entries for products
Fuime does not offer, clicked through to fully-rendered pages, and discovered
the truth only when a form submission bounced with "That feature isn't
available on Fuime."

Fixing this at the **policy** predicate rather than the route closes the page
and the nav link together, because the controller action calls `authorize` on
the same predicate the nav is built from. Prefer that lever for a whole feature;
use `DisabledModules` when you need to keep reads working.

---

## Live calls to Hack Club infrastructure (Prime Directive 4)

Not branding — these were **runtime requests to another organization's servers**
from a running Fuime app. The most severe finding of the closing pass.

| What | Where | Severity |
|---|---|---|
| `fetch('blog.hcb.hackclub.com/api/unreads', {credentials: 'include'})` on every page load | `app/javascript/controllers/blog_controller.js` | Credentialed cross-origin request, header of every authenticated page |
| `<iframe src="blog.hcb.hackclub.com/embed">` | `app/views/application/_blog_widget.html.erb` | Rendered in 4 layouts |
| Phantom Sans `@font-face` from `assets.hackclub.com` | `app/assets/stylesheets/components/_marketing.scss` | Also a trademark use — the AGPL covers code, not the typeface |
| Default avatar from `cdn.hackclub.com` | `app/helpers/users_helper.rb` | Nearly every authenticated page; now `icons/person.svg`, served locally |
| ~40 images/backgrounds via `cdn.hackclub.com/rescue` | `_promos.scss`, `_cards.scss`, `_dark.scss`, `_seasonal.html.erb`, `flavor_text_service.rb`, one-pager empty states | Tailwind arbitrary-value classes compiled these into **all three** CSS bundles, so they shipped even to pages that never rendered them |
| Static location maps from `maps.hackclub.com` | (earlier pass) `application_helper.rb` and 4 views | Shipped users' lat/long to Hack Club's Vercel project |

After this pass, `grep hackclub app/assets/builds/*.css` returns **1 hit per
bundle** — a `github.com/hackclub/hcb` issue link in a source comment, which is
legitimate attribution.

## URLs that pointed users at hcb.hackclub.com

Not third-party *calls*, but links and text handed to Fuime users that resolve
to Hack Club's app, where their data does not exist. All now derive from this
deployment's own host via `Rails.application.routes.url_helpers.root_url`.

| File | What it was |
|---|---|
| `app/models/event.rb`, `app/models/hcb_code.rb`, `app/models/user.rb` | The **URL column of user CSV exports** — `comma` blocks hardcoding `https://hcb.hackclub.com/…` |
| `app/jobs/twilio/process_webhook_job.rb` | SMS replies telling a teen to visit `hcb.hackclub.com/my/settings` and `/my/inbox` |
| `app/jobs/discord/process_notification_job.rb` | Rewrote relative links in Discord notifications to absolute `hcb.hackclub.com` URLs |
| `app/models/announcement/templates/monthly.rb` | Announcement body linking to the org on HCB |

Roughly 20 "Learn more about X **on Fuime** →" links pointed at
`help.hcb.hackclub.com` — a Fuime label on Hack Club's help centre. Removed
rather than repointed; Fuime has no help centre yet. Files:
`hcb_codes/_decline_reason`, `hcb_codes/transaction_types/_wise_transfer`,
`hcb_codes/reimbursement/_expense_payout`, `users/payout_form/_fields`,
`check_deposits/index`, `wise_transfers/new`, `receipts/_form_v3`,
`reimbursement/expenses/_receipts`, `reimbursement/reports/_actions`,
`reimbursement/reports/wise_transfer_breakdown`,
`organizer_position/spending/controls/index`,
`organizer_position/spending/controls_mailer/new_allowance`,
`javascript/controllers/transfer_form_controller.js`.

## Another person's signature

`zach_signature.png` — the scanned signature of Hack Club's founder — was
prefilled as the **countersignature** on Fuime contracts and drawn on the check
template:

- `app/models/contract/fiscal_sponsorship.rb` (fetched from `hcb.hackclub.com`)
- `app/models/contract/payroll_position.rb` (same)
- `app/views/increase_checks/_paper_check.html.erb`

Latent rather than live — the DocuSeal flow is gated off by default
(`FUIME_DOCUSEAL_TEMPLATE_ID` unset) — but configuring a template would have
countersigned Fuime agreements on his behalf. Removed; the signature field is
now blank for a real countersignatory to sign.

## Social proof that was not Fuime's

Real third parties presented as Fuime's customers, team, or backers:

| Where | What |
|---|---|
| `app/helpers/users_helper.rb` `onboarding_gallery` | 8 screenshots of real Hack Club orgs (Zephyr, Assemble, HackPenn…) on the signup screen, each linking to that org on `hcb.hackclub.com` |
| `app/helpers/marketing_helper.rb`, `marketing/funders.html.erb` | Named people (Jasmine Sun, Isaac Sevier, Richard Littauer) quoted about HCB; 3 Hack Club staff shown as Fuime's team; Ford / Omidyar / Hewlett / Sloan / SoftBank / Founders Fund logos under "Major funders already back organizations on Fuime" |
| `app/services/flavor_text_service.rb` | 29 dashboard taglines that were Hack Club in-jokes ("The Hack Club Federal Reserve", "From the makers of Hack Club"), links to their properties, or CDN images |

---

## Still outstanding

Honest list; none of it is a string swap.

- **~138 non-comment `Hack Club` occurrences remain in `app/`.** The large
  concentrations are all category 3 or 4, or on disabled surfaces:
  `static_pages/branding.html.erb` (11), `marketing/funders.html.erb` (9),
  `events/termination.pdf.erb` (9, now disabled), `transaction.rb` (6, ledger
  data), `static_pages/index/_explore.html.erb` (5, an orphan partial nothing
  renders), `canonical_transaction.rb` (4, ledger data), the two disabled
  letters (8), `ach_transfers`/`disbursements` confirmation letters (7, on
  write-disabled modules).
- **`app/views/static_pages/branding.html.erb`** is a brand-guidelines page
  still describing Hack Club's brand. Reachable. Needs Fuime brand guidelines
  written before it can be rewritten — a content task.
- **`marketing/_footer.html.erb`** links to `hackclub.com/fiscal-sponsorship`,
  their blog, help centre, and org directory. Only rendered by the
  marketing layout, which `MarketingController` disables wholesale, so it is
  currently unreachable — but it should be rewritten before any marketing page
  is revived.
- **`app/views/events/landing/_footer.html.erb`**, `events/settings/_affiliation_form.html.erb`,
  `event/application.rb`, and `event/affiliation.rb` reference Hack Club
  affiliations (`Event::Plan::HackClubHQ`, `HackClubAffiliate`) — these are
  *plan class names* and affiliation values, closer to category 4 than to
  branding. Renaming is a Phase 1+ refactor (Rule 6).
- **Orphan partials** `static_pages/index/_explore.html.erb` and
  `_teenager_raffle.html.erb` are full of Hack Club outbound links but are
  rendered by nothing (`static_pages/index.html.erb` never calls them). Left
  in place per Rule 2; delete or rewrite if the dashboard is ever redesigned.
- **`app/services/search_service/specification.md`** (3) is an internal design
  doc, not user-facing.

## How to re-measure

The naive count is misleading, because explanatory comments legitimately say
"Hack Club". Count non-comment occurrences only:

```bash
grep -rn "Hack Club" app/ \
  | grep -v "app/assets/builds" \
  | grep -vE ':\s*(#|//|<%#|\*)' \
  | wc -l
```

For live third-party calls, the sharper check is the built CSS and the JS
bundle, since those are what actually ship:

```bash
grep -c hackclub app/assets/builds/*.css
```
