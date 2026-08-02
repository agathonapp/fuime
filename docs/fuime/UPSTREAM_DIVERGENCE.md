# Fuime Upstream Divergence Log

This document tracks all intentional divergences from the upstream HCB codebase.
Purpose: preserve ability to merge upstream ledger/security fixes later.

## M1: Identity Rebrand

| Change | Why | Files |
|--------|-----|-------|
| Title suffix "HCB" → "Fuime" | Brand identity | `app/views/layouts/_head.html.erb` |
| Console ASCII art updated | Brand identity | `app/views/layouts/_head.html.erb` |
| Primary color #ec3750 → #2242FF | Fuime blue branding | `app/views/layouts/_head.html.erb`, `app/assets/stylesheets/_variables.scss` |
| Removed Plausible analytics | Points to hcb.hackclub.com | `app/views/layouts/_head.html.erb` |
| Footer text updated | Attribution to HCB/Hack Club | `app/views/application/_footer.html.erb` |
| Logo alt text "HCB" → "Fuime" | Brand identity | `app/views/application/_logo.html.erb` |
| Removed seasonal Hack Club CDN logos | External dependency | `app/views/application/_logo.html.erb` |
| Welcome text updated | Brand identity | `app/views/layouts/application.html.erb` |
| Login page copy updated | Teen business focus | `app/views/layouts/login.html.erb` |
| README rewritten | Fuime description + HCB attribution | `README.md` |
| Deleted hcb_laser.gif | Hack Club branding | `hcb_laser.gif` |
| Added $fuime-blue color variable | Primary accent color | `app/assets/stylesheets/_variables.scss` |

## M2: Guardianship System

| Change | Why | Files |
|--------|-----|-------|
| Created guardianships table | Parent-teen linking | `db/migrate/20260801100000_create_guardianships.rb` |
| Added Guardianship model | Core guardianship logic | `app/models/guardianship.rb` |
| Added guardianship associations to User | Link guardians and minors | `app/models/user.rb` |
| Added guardian helper methods to User | Check guardian status | `app/models/user.rb` |
| Under-13 validation | COPPA compliance | `app/models/user.rb` |
| Guardianship controller | Invite/accept flows | `app/controllers/guardianships_controller.rb` |
| Guardianship policy | Pundit authorization | `app/policies/guardianship_policy.rb` |
| Guardian routes | Invite/accept URLs | `config/routes.rb` |
| Guardian views | new.html.erb, show.html.erb | `app/views/guardianships/` |
| Guardianship mailer | Invite/accepted emails | `app/mailers/guardianship_mailer.rb` |
| Mailer views | invite.html.erb, accepted.html.erb | `app/views/guardianship_mailer/` |
| Redirect minors to guardian invite | Onboarding flow | `app/controllers/users_controller.rb` |
| Application mailer rebranding | HCB → Fuime emails | `app/mailers/application_mailer.rb` |
| Onboarding button text | "Start using HCB" → "Start using Fuime" | `app/views/users/edit.html.erb` |
| Settings data sharing text | HCB → Fuime | `app/views/users/edit.html.erb` |

## M4: Account UI + Payment Links

| Change | Why | Files |
|--------|-----|-------|
| Dashboard rebranding | HCB → Fuime, organizations → businesses | `app/views/static_pages/index.html.erb` |
| Onboarded email rebranding | HCB → Fuime | `app/views/user_mailer/onboarded.html.erb` |
| Payment link service | Generate Stripe Checkout sessions | `app/services/fuime/payment_link_service.rb` |
| Payment webhook handler | Map payments to business ledgers | `app/services/fuime/payment_webhook_handler.rb` |
| Fuime webhooks controller | Handle Stripe webhook events | `app/controllers/fuime/webhooks_controller.rb` |
| Fuime webhook route | POST /fuime/webhooks/stripe | `config/routes.rb` |

## M3: Business Creation Flow

| Change | Why | Files |
|--------|-----|-------|
| Added business_category + storefront_tagline to events | Business categorization | `db/migrate/20260801110000_add_fuime_business_fields_to_events.rb` |
| Added BUSINESS_CATEGORIES constant | Category validation | `app/models/event.rb` |
| Restrung _begin.html.erb | HCB → Fuime, nonprofit → business | `app/views/event/applications/_begin.html.erb` |
| Restrung project_info.html.erb | Project → Business terminology | `app/views/event/applications/project_info.html.erb` |
| Restrung _title.html.erb | Organization → Business | `app/views/events/_title.html.erb` |
| Restrung settings details | Organization → Business | `app/views/events/settings/_details.html.erb` |

## M5: Ledger Strings + Event Page Rebranding

| Change | Why | Files |
|--------|-----|-------|
| OG meta tags HCB → Fuime | Brand identity | `app/views/events/show.html.erb` |
| Removed HCB OG image URL | External dependency | `app/views/events/show.html.erb` |
| Onboarding message HCB → Fuime | Brand identity | `app/views/events/show.html.erb` |

## M6: Tax Tracker

| Change | Why | Files |
|--------|-----|-------|
| Tax Tracker service | Compute net income, $400 threshold | `app/services/fuime/tax_tracker_service.rb` |
| Tax Tracker controller | /taxes page + CSV download | `app/controllers/fuime/taxes_controller.rb` |
| Tax Tracker page view | Full tax details + packet download | `app/views/fuime/taxes/show.html.erb` |
| Tax Tracker card | Home page summary card | `app/views/events/home/_tax_tracker.html.erb` |
| Added Tax Tracker card to home | Demo visibility | `app/views/events/show.html.erb` |
| Added Taxes nav item | Navigation | `app/helpers/events_helper.rb` |
| Tax routes | /taxes, /taxes/download | `config/routes.rb` |

## M7: Public Storefront

| Change | Why | Files |
|--------|-----|-------|
| Storefront controller | Public /b/:slug page | `app/controllers/fuime/storefronts_controller.rb` |
| Storefront view | Official badge, payment button, public ledger | `app/views/fuime/storefronts/show.html.erb` |
| Storefront route | GET /b/:slug | `config/routes.rb` |

## M8: Login Page Rebrand

| Change | Why | Files |
|--------|-----|-------|
| Login page HCB → Fuime | Brand identity | `app/views/logins/new.html.erb` |
| Login header HCB → Fuime | Brand identity | `app/views/logins/_header.html.erb` |
| Removed "What's HCB?" link | Brand identity | `app/views/logins/_footer.html.erb` |
| Removed right side image panel | Simpler login UI | `app/views/layouts/login.html.erb` |
| Logout page HCB → Fuime | Brand identity | `app/views/users/logout.html.erb` |
| User nav HCB → Fuime | Brand identity | `app/views/users/_nav.html.erb` |
| Removed HCB Wrapped promo | HCB-specific feature | `app/views/users/_nav.html.erb` |

## Render Deployment

| Change | Why | Files |
|--------|-----|-------|
| Added render.yaml Blueprint | Render deployment | `render.yaml` |
| Ruby version 3.4.7 → 3.4.9 | Match .ruby-version | `production.Dockerfile` |
| Active Storage default to local | No S3 required for initial deploy | `config/environments/production.rb` |

## Login + Email Delivery Fix (Render)

Root cause: `config/application.rb` built `smtp_settings` purely from
`Credentials.fetch(:SMTP, ...)` with no fallbacks. On Render only
`SMTP__PASSWORD` is `sync: false`, but `credentials.yml.enc` contains just
`secret_key_base` — so any unset SMTP var resolved to `nil`, producing
`address: nil` and `Errno::ECONNREFUSED ... for nil port 25`.

Because `LoginCodeService::Request` calls `deliver_now` inline, that SMTP
exception surfaced as a failed login, not merely a missing email. Both
reported symptoms were the same bug.

| Change | Why | Files |
|--------|-----|-------|
| SMTP defaults for Resend + integer port + `enable_starttls_auto` | Missing env vars no longer yield `address: nil`; String port can leave STARTTLS off | `config/application.rb` |
| Rescue delivery errors in login code service | SMTP outage returns a readable error via the existing `resp[:error]` path instead of a 500 on login | `app/services/login_code_service/request.rb` |
| Spec for unreachable SMTP | Regression cover for the login-breaks-on-mail-failure path | `spec/services/login_code_service/request_spec.rb` |
| Boot-time SMTP warning | Surfaces the misconfiguration in logs instead of as a buried request error | `config/initializers/smtp_check.rb` |
| Login code subject HCB → Fuime | Brand | `app/mailers/login_code_mailer.rb` |

Operator action required: set `SMTP__PASSWORD` to the Resend API key in the
Render dashboard for BOTH `fuime-web` and `fuime-worker`, and verify the
`fuime.com` domain in Resend so `no-reply@fuime.com` is an allowed sender.

## Mailer Host + Redis Fixes (Render)

Two further production bugs found after the SMTP fix, both diagnosed by running
`rails runner` one-off jobs against the live service.

**1. Missing mailer host.** SMTP was correctly configured (verified against
Resend: `address=smtp.resend.com port=587 user=resend pw_set=true`), but
`LIVE_URL_HOST` was unset. Mailer templates build absolute URLs, so rendering
raised `Missing host to link to!` *before* SMTP was contacted. Because login
codes send inline via `deliver_now`, this broke login itself.

**2. `REDIS_CACHE_URL` never set.** `config/cable.yml` and the production
`cache_store` both read `REDIS_CACHE_URL`, but `render.yaml` only provided
`REDIS_URL`. Both fell back to `redis://localhost:6379/1`. ActionCable failed
loudly — every `Turbo::Streams::ActionBroadcastJob` died with
`Redis::CannotConnectError` — which broke guardian invite emails
(`deliver_later`) and signed-in page rendering. The cache store failed silently
with `url: nil`.

| Change | Why | Files |
|--------|-----|-------|
| Mailer host falls back to `RENDER_EXTERNAL_HOSTNAME` | Render always injects it; removes dependence on a hand-set var | `config/environments/production.rb`, `config/application.rb` |
| Boot warning when no mailer host configured | Missing host breaks email at render time, not send time | `config/initializers/smtp_check.rb` |
| `REDIS_CACHE_URL` added to web + worker | cable.yml and cache_store read it | `render.yaml` |
| cable.yml / cache_store fall back to `REDIS_URL` | Works whether or not the Blueprint is re-synced | `config/cable.yml`, `config/environments/production.rb` |

Verified on production: login code emails accepted by Resend; both guardianship
mailers deliver; previously-failing broadcast jobs now report `done` with zero
`CannotConnectError`.

Note: `render.yaml` is a Blueprint — the `REDIS_CACHE_URL` entry only reaches
Render on a manual Blueprint re-sync. The code fallbacks make that optional.

## Homepage 500 + Error Visibility

**The homepage returned 500 on every request.** The exception was invisible
because `config.lograge.logger` pointed at Appsignal, which has no
`APPSIGNAL_PUSH_API_KEY` set — so request logs and stack traces went nowhere,
and the `ERR-xxxxxxxx` reference codes shown to users could not be traced.

Once lograge was pointed at stdout, the cause appeared immediately:

```
ActionView::SyntaxErrorInTemplate
app/views/static_pages/index.html.erb:241: unexpected 'end', ignoring it
```

An ERB comment tag ends at the *first* closing delimiter. The `<%#` used to
disable the announcement block was terminated by the very next line, so the
`<% if %>` / `<% end %>` inside the "commented" region still compiled. The
unmatched `end` broke the entire template — and with it, `/` and `/guardian`
(which is `guardianships#new`, routed via `path: "guardian"`).

| Change | Why | Files |
|--------|-----|-------|
| lograge → stdout unless Appsignal configured | Exceptions were invisible in `render logs` | `config/environments/production.rb` |
| Log exception class/message/backtrace via lograge | Make ERR- codes traceable | `config/environments/production.rb` |
| Log ERR- reference next to the exception | `render logs --text ERR-XXXXXXXX` finds the trace | `app/controllers/errors_controller.rb` |
| Rewrite broken ERB comment block | Stray `end` broke the homepage template | `app/views/static_pages/index.html.erb` |

Verified: all 9 `static_pages` views compile under Rails' Erubi handler
(`broken=0`); `/` and `/guardian` return 302 instead of 500; zero `status=500`
in the logs.

Note: `app/views/card_grants/transaction_index.html.erb` has a similar
`<%# <%= ... %>` pattern, but it leaves only stray text rather than an
unbalanced `end`, so it does not break that template. Left as upstream code
per Rule 6.

## Guardian Invite Submission 500

With request logging finally visible, submitting the invite form surfaced:

```
POST /guardian → 500
ActiveModel::UnknownAttributeError: unknown attribute 'guardian_email'
for Guardianship. (guardianships_controller.rb:17)
```

`guardian_email` is a form-only field used to find or create the guardian
User — it is not a column on `guardianships`. Passing the permitted params
straight into `Guardianship.new` raised on every submission. `/guardian/new`
rendered fine (200), so only the POST failed.

| Change | Why | Files |
|--------|-----|-------|
| Build record from `minor:` only; read guardian_email from params | `guardian_email` is not a model attribute | `app/controllers/guardianships_controller.rb` |
| `params.fetch` instead of `params.require` | Missing key returned 500 instead of a form error | `app/controllers/guardianships_controller.rb` |
| `formats: [:html]` on error re-renders | Form posts as turbo_stream; no turbo_stream template exists for `new` | `app/controllers/guardianships_controller.rb` |

Verified on production: the old constructor call still raises
`ActiveModel::UnknownAttributeError`, while the new flow creates the guardian,
saves the guardianship, and enqueues the invite (`NEW_FLOW=OK`, `enqueue=OK`).

## Guardian Link Host + Hack Club Branding Removal

**Guardian link.** A delivered invite pointed at `https://guardian/<token>` —
no host. This was an email generated *before* the `LIVE_URL_HOST` fix
deployed; with the mailer host set, `guardianship_url(token)` now correctly
produces `https://fuime-web.onrender.com/guardian/<token>` (verified on
production for positional, `id:`, and explicit-host forms). No code change
needed — old emails contain the bad link, new ones do not.

**Branding.** The signed-in homepage rendered an "Explore Hack Club" card grid
(Stardance, Macondo, Outpost, Hack Club Slack, Hack Clubs, Boba Drops) plus a
Hack Club teenager raffle promo.

| Change | Why | Files |
|--------|-----|-------|
| Stop rendering `_explore` | "Explore Hack Club" promo grid | `app/views/static_pages/index.html.erb` |
| Stop rendering `_teenager_raffle` | Hack Club raffle promo | `app/views/static_pages/index.html.erb` |

Partials left on disk per Rule 2, tagged `FUIME-DISABLED`.

The footer attribution ("Fuime is a fork of HCB by Hack Club (AGPL-3.0)")
**stays** — Rule 7 requires it.

Remaining `Hack Club` references live in marketing pages, PDF templates
(`verification_letter`, `fiscal_sponsorship_letter`, transfer confirmations),
`static_pages/branding`, and disabled modules — none render in the current
teen flow. A full sweep is Milestone 3 work.

## Production Data Reset (fresh state for demo)

The admin console showed inherited HCB seed state: $17,994,358.00 in
transactions, 15 organizations, and several 9999-count queues.

**What was deleted** (via `rails runner` on production, not a code change):
all canonical transactions / pending transactions / hcb_codes / fees /
ledger_items, 48 activity records, the 3 demo events (DevHacks, ExpensiCon,
Hack The Seas), and the `admin@bank.engineering` seed user.

**What was deliberately kept:**

- The **12 HCB system orgs** — `EventMappingEngine::EventIds` references them
  by hardcoded id (fee routing in `HcbCode`, `StripeServiceFee`, grant-fund
  qualifiers in `Disbursement`). Deleting them breaks the ledger, so they are
  hidden from the admin count instead.
- `bank@hackclub.com` (id 2891) — this is `User::SYSTEM_USER_ID`, required by
  the app, not a seed account.
- All three real user accounts.

**Gotchas hit** (worth knowing before any future reset):

- `TRUNCATE ... CASCADE` on ledger tables also empties `ledgers`, which is
  only populated by `Event#after_create :create_ledger`. Every surviving event
  had to have its primary ledger recreated (`missing_ledger=0` confirmed).
- `admin@bank.engineering` was `point_of_contact` on all 12 system orgs; the
  FK had to be reassigned (to `rushilchopra@gmail.com`) before deletion.
- `organizer_position_invites` must be deleted before `organizer_positions`.

| Change | Why | Files |
|--------|-----|-------|
| Exclude system orgs from Organizations badge | 12 inherited orgs aren't real Fuime businesses | `app/views/static_pages/admin_tools.html.erb` |
| Hide Airtable/identity cards | `admin_controller.rb:1789` returns 9999 when the Hack Club Airtable base is unreachable — permanently broken counters in this fork | `app/views/static_pages/admin_tools.html.erb` |

Verified: volume `$0`, org badge `0`, 0 transactions, 0 activities,
12/12 ledgers intact, admin_tools template compiles.

## Money Loop: Stripe → Ledger

`Fuime::PaymentWebhookHandler` was a stub — it logged incoming payments and
returned, with `# TODO: Create canonical pending transaction` where the ledger
write belonged. A test payment would succeed in Stripe and never appear on the
business's page.

Implemented using HCB's existing pipeline entry points (Rule 3 — feed the
ledger, never modify it):

```
RawPendingDonationTransaction  (narrowest legitimate "money in" source)
  -> CanonicalPendingTransaction   (callbacks create HcbCode + ledger item)
    -> CanonicalPendingEventMapping (assigns the line to the business)
```

Donation is the correct analogue: an outside party sending money into an org.
Because the HcbCode is created by the normal callbacks, receipts and comments
work on the resulting line.

Idempotency is keyed on the Stripe object id (`fuime_<id>`), so Stripe's
retries cannot double-post.

| Change | Why | Files |
|--------|-----|-------|
| Implement webhook → ledger | Payments never reached the ledger | `app/services/fuime/payment_webhook_handler.rb` |
| Guard `likely_event_id` | Fuime rows have no Donation record; shared pipeline would raise | `app/models/raw_pending_donation_transaction.rb` |
| Memo "Payment" for Fuime rows | These are customer payments, not donations | `app/models/raw_pending_donation_transaction.rb` |
| Fix missing icons | `inline_icon` reads SVGs off disk; `money-dollar-box` / `alert-triangle` don't exist and 500'd the storefront + tax tracker | `app/views/fuime/storefronts/show.html.erb`, `app/views/fuime/taxes/show.html.erb`, `app/views/events/home/_tax_tracker.html.erb` |
| Rebrand transparency banner | Customer-facing page said "This HCB organization…" | `app/views/application/_banner_container.html.erb`, `app/views/layouts/docs.html.erb` |

Verified on production: a simulated `checkout.session.completed` produced a
ledger line (`$45.00`, memo from the Stripe description, HcbCode present);
replaying the same event kept the count at 1; `/b/sunset-cookies` returns 200
showing a `$41.85` balance (net of the 4% fee) and a public ledger.

**Still required for a live payment:** `STRIPE__TEST__SECRET_KEY`,
`STRIPE__TEST__PUBLISHABLE_KEY`, and `FUIME_STRIPE_WEBHOOK_SECRET` are unset in
Render, so no real Checkout session can be created yet.

Audited all 137 `inline_icon` names across `app/views`: no missing icons.

## Production Hardening (real-user readiness)

Driven by the full sweep in `docs/fuime/PRODUCTION_READINESS.md`. This is the
work that turns a working demo into something that can face real teenagers and
real parents. Engineering blockers only — the legal items (§1.2 identity
verification, §1.5 money transmission, §1.6 CPA review) remain open and gate
launch independently of any code here.

### Guardianship is now an enforced control, not a redirect (§1.1, §1.2)

Previously `needs_guardian?` was consulted in exactly one place — a redirect
after profile creation. A teen could dismiss it and then create, own, and
transact on a business freely. Two further bypasses compounded it: `is_minor?`
returns **nil** when no birthday is recorded (falsy, so every guard passed), and
the under-13 COPPA validation only ran `if birthday.present?` — so omitting the
date of birth disabled both controls at once.

| Change | Why | Files |
|--------|-----|-------|
| `minor_or_unknown_age?` / `known_adult?` / `permitted_to_operate_business?` | Fail closed: unknown age is treated as a minor. `is_minor?` keeps its upstream tri-state so HCB code is unaffected | `app/models/user.rb` |
| Request-level `GuardianshipEnforcement` filter (deny-by-default allowlist) | A redirect on one happy path is a suggestion; this blocks every URL | `app/controllers/concerns/fuime/guardianship_enforcement.rb`, `app/controllers/application_controller.rb` |
| Gate `member?` / `manager?` in EventPolicy | Every write path resolves through these two, so one change covers ~40 predicates and any added later. Read access deliberately NOT gated | `app/policies/event_policy.rb` |
| Birthday required to finish onboarding (`:onboarding` context) | Closes the "skip the DOB field" bypass. Scoped to the user's own onboarding so invites, guardian stubs, and seeds still work | `app/models/user.rb`, `app/controllers/users_controller.rb` |
| `activation_blockers` / `activatable?`; `accept!` refuses unless guardian is a confirmed adult | A stub guardian with no birthday could previously sign as the responsible adult | `app/models/guardianship.rb`, `app/controllers/guardianships_controller.rb` |
| Consent record: agreement version, IP, user agent | "They clicked accept" is not evidence of informed consent | `db/migrate/20260801170000_*`, `..._170001_*`, `..._170002_*` |
| Invite token expiry (7 days) + `resend_invite!` | Invite links are bearer tokens over a minor's account; they never expired | `app/models/guardianship.rb` |
| `revoke!` records who and when | Withdrawing consent is a legal requirement and must be auditable | `app/models/guardianship.rb` |

### Money path (§1.3, §1.4)

| Change | Why | Files |
|--------|-----|-------|
| `STRIPE_MODE` env var; default `:test` everywhere incl. production | Upstream hardcoded `:live` in production, but only `STRIPE__TEST__*` keys exist — so every Stripe call in production read credentials that were never set | `app/services/stripe_service.rb`, `render.yaml` |
| Handle `payment_intent.succeeded` only; ignore `checkout.session.completed` | Both fire for one Checkout payment with different object ids, so keying idempotency on the object id **double-posted every payment** | `app/services/fuime/payment_webhook_handler.rb` |
| `fronted: false` | `fronted` means the platform advances spendable credit against unsettled money — backed by Hack Club's reserves upstream. Fuime has none, and Stripe is T+2 with refund/chargeback risk after | `app/services/fuime/payment_webhook_handler.rb` |
| Handle `charge.refunded` and `charge.dispute.created` | A refunded payment stayed on the ledger as income and inflated the family's tax number. Reversals are capped at the outstanding amount so cumulative refund events don't stack | `app/services/fuime/payment_webhook_handler.rb` |
| Refuse unsigned webhooks (503, not "accept anything") | This endpoint writes to business ledgers; an unverified event is an attacker-controlled ledger line | `app/controllers/fuime/webhooks_controller.rb` |
| `FUIME_STRIPE_WEBHOOK_SECRET` added to Render | Was never set, so production rejected **every** Stripe webhook | `render.yaml` |

### Data durability + boot safety (§1.7)

| Change | Why | Files |
|--------|-----|-------|
| `ACTIVE_STORAGE_SERVICE=amazon` + `S3__*` on web and worker | Default was `:local` with no persistent disk on Render — every deploy **permanently destroyed every uploaded receipt**, silently and unrecoverably | `render.yaml` |
| Boot-time safety check: raises on `:local` storage, half-configured live keys, or a hackclub.com host; warns on test mode and missing webhook secret | CLAUDE.md Milestone 2. Misconfiguration here is data loss or unauthorised money movement, not degraded service | `config/initializers/fuime_safety_check.rb` |

### Honest claims + privacy (§1.6, §2.2, §2.4)

| Change | Why | Files |
|--------|-----|-------|
| Tax threshold applied to **net earnings** (net profit x 92.35%), not raw net income | IRS Schedule SE. The $400 test bites at ~$433.14 of profit; businesses between $400 and $433 were told they owed when they may not | `app/services/fuime/tax_tracker_service.rb` |
| Income classification excludes transfers, owner deposits, refund/dispute reversals | Every positive ledger line counted as taxable income | `app/services/fuime/tax_tracker_service.rb` |
| Copy reframed from determinations to estimates; disclaimer + quarterly-estimates warning | Fuime is not a tax preparer and must not state obligations as fact | `app/services/fuime/tax_tracker_service.rb`, `app/views/fuime/taxes/show.html.erb`, `app/controllers/fuime/taxes_controller.rb` |
| Progress bar reads net earnings | It compared net income to $400 while the verdict used net earnings — the two disagreed | `app/views/fuime/taxes/show.html.erb` |
| Storefront: balance removed, owner name shown only for adult owners, tax figures never public | A minor's first name + live balance + ledger is a targeting profile. HCB's transparency page was built for nonprofit *organisations* | `app/controllers/fuime/storefronts_controller.rb`, `app/views/fuime/storefronts/show.html.erb` |
| Badge "Parent-signed account" → "Guardian on account" | Accepting an invite proves control of an email and a self-asserted birthday, not a verified parental relationship. Restore when §1.2 ships | `app/views/fuime/storefronts/show.html.erb` |
| Comment mailer `from`/`reply_to`/`Message-ID` moved off hcb.hackclub.com | Fuime users' replies were routed into Hack Club's inbound parser | `app/mailers/comment_mailer.rb` |
| `receipt_upload_email` returns nil unless `FUIME_RECEIPT_PARSE_DOMAIN` is set | Was advertising an hcb.hackclub.com address that delivered Fuime users' receipts to a third party | `app/models/hcb_code.rb`, `app/views/hcb_codes/show.html.erb` |
| Admin alert recipients from `FUIME_ENGINEER_EMAILS` | Was a hardcoded list of Hack Club staff | `app/mailers/admin_mailer.rb` |

### Disabled modules are actually blocked (§2.3)

Upstream money-out modules were "disabled" by not rendering nav links, leaving
~60 routes live to anyone who types a URL — and the people typing URLs here are
teenagers. Now blocked at the request level (admins exempt); nothing deleted,
per Rule 2.

| Change | Why | Files |
|--------|-----|-------|
| `DisabledModules` filter: ACH, checks, wires, disbursements, reimbursements, donations, card grants, G Suite, card issuing | Nav hiding is not enforcement | `app/controllers/concerns/fuime/disabled_modules.rb`, `app/controllers/application_controller.rb` |

Deliberately still enabled: invoices (Fuime's money-in), receipts, comments,
the ledger, transparency mode, admin console, auth.

### Secrets hygiene (§2.6)

| Change | Why | Files |
|--------|-----|-------|
| Removed the real-looking 64-hex `LOCKBOX` value | Anyone copying the example inherited a publicly-known encryption key | `.env.development.example` |
| `LIVE_URL_HOST` example no longer hcb.hackclub.com | Pointed local dev at Hack Club production (Rule 4) | `.env.development.example` |
| Documented the new Fuime env vars | Setup was undiscoverable | `.env.development.example` |

### Tests (§2.7)

Fuime previously had **zero** specs — no coverage on guardianship, payments,
taxes, or the storefront, despite Prime Directive #1. Added 68:

- `spec/models/guardianship_spec.rb` — activation preconditions, consent record, token expiry, revocation
- `spec/models/user_guardianship_spec.rb` — fail-closed age logic, COPPA floor, onboarding DOB requirement
- `spec/services/fuime/tax_tracker_service_spec.rb` — threshold arithmetic against hand-computed values, incl. the $400/$433 boundary
- `spec/services/fuime/payment_webhook_handler_spec.rb` — idempotency, no double-post, refunds/disputes, cumulative-refund capping
- `spec/controllers/fuime/guardianship_enforcement_spec.rb` — the control actually blocks, at request and policy level
- `spec/controllers/fuime/disabled_modules_spec.rb` — blocked list is real and doesn't over-reach

`spec/factories/user_factory.rb` now defaults users to adults (with `:minor`,
`:minor_with_guardian`, `:unknown_age` traits). Without this, every unrelated
spec would silently become a test of the guardianship gate.

---

## Parent/child roles, admin visibility, and the guardian agreement

### Role vocabulary (§3.x, Rule 6-compliant)

The `role` enum keeps upstream's values — `reader` / `member` / `manager` are
woven through policies, `OrganizerPosition.role_at_least?`, spending controls,
invites, and team filters, and renaming them would end our ability to merge
upstream fixes. Only the words a teenager or parent reads changed.

| Change | Why | Files |
|--------|-----|-------|
| New `RolesHelper` mapping manager→Owner, member→Team member, reader→Parent | Role names were rendered ad-hoc with `.capitalize` / `.humanize` / `.titleize` in five partials, so a rename would land half-applied | `app/helpers/roles_helper.rb` |
| Replaced every ad-hoc role render with `role_label` | Single source of truth | `organizer_positions/_organizer_position*.html.erb`, `organizer_position_invites/_organizer_position_invite.html.erb`, `_role_and_control_form.html.erb`, `organizer_position_mailer/role_change.html.erb` |
| Team filter tabs relabelled; `filter` **param values unchanged** | `EventsController` maps the param to a role enum value — only the tab text is Fuime's | `app/views/events/team.html.erb` |
| Rewrote the roles explainer, which was an HCB changelog post from March 2024 | Described a feature launch to HCB users, in HCB's vocabulary | `app/views/static_pages/roles.html.erb` |
| `helper :roles` added to `ApplicationMailer` | `role_change.html.erb` needs `role_label`; mailers only had `:application` and `:logo` | `app/mailers/application_mailer.rb` |

Deliberately NOT done: a real guardianship-derived "Parent" seat on an org. The
Parent role is a read-only view, not proof of guardianship — the actual legal
link is the `Guardianship` record. Noted so nobody later mistakes the seat for
the control.

### Admin user page (§5 — "no guardian revocation UI")

| Change | Why | Files |
|--------|-----|-------|
| `User#account_type` / `#account_type_label` / `#primary_guardianship` | `/users/:id/admin` could not answer "is this a parent or a kid?" — admins reverse-engineered it from a birthday and two association counts, which is how you revoke the wrong person's guardianship | `app/models/user.rb` |
| Guardianship panel: account type, age, status, guardian/wards, consent record, resend + revoke | Closes the §5 gap. A parent could not withdraw consent through any UI, though `revoke!` existed on the model | `app/views/users/_admin_guardianship.html.erb`, `users/edit_admin.html.erb` |
| `revoke` / `resend_invite` / `record` actions + policies | Revoke excludes the **minor** by design: a teen must not be able to remove their own supervision | `guardianships_controller.rb`, `guardianship_policy.rb`, `config/routes.rb` |

`:show` and `:accept` stay token-addressed (a guardian follows them from email
before having an account); the three new actions are id-addressed and
authenticated.

### Guardian agreement (in-app, no DocuSeal)

HCB's `Contract` machinery is DocuSeal-backed, which needs a third-party
credential Phase 0 forbids (Rule 4), so the guardian agreement is in-app.

| Change | Why | Files |
|--------|-----|-------|
| Versioned agreement text as a partial per version | The schema already stored `agreement_version` / `_ip` / `_user_agent` / `_signed_at`, but no agreement text existed anywhere — "Accept & Sign" was a JS `confirm()` | `app/views/guardianships/agreements/_2026_08_01_v1.html.erb` |
| `Guardianship.agreement_partial_for` resolves a version to its file | A guardian who signed v1 must always see v1, not today's terms. Version strings come from the DB, so the slug is allowlisted (`/\A[a-z0-9_]+\z/`) before being interpolated into a path | `app/models/guardianship.rb` |
| Accept page renders the agreement + a checkbox, re-checked server-side | `required` is a client-side hint; consent is the entire legal product of the action | `guardianships/show.html.erb`, `guardianships_controller.rb` |
| `record` page — permanent, re-readable proof of what was signed | Consent you cannot review is not meaningful consent. Stays readable after revocation | `app/views/guardianships/record.html.erb` |

**Bug fixed:** `guardianships.revoked_by_id` and its foreign key shipped in
migration `20260801170001` with **no `belongs_to :revoked_by`**, so any
`guardianship.revoked_by` call raised `NoMethodError`. Added the association
(`optional: true`) and refreshed the stale schema annotation on the model.

### Tests

- `spec/models/user_account_type_spec.rb` — classification incl. fail-closed unknown age and guardian-before-teen ordering
- `spec/models/guardianship_agreement_spec.rb` — version resolution, path-traversal rejection, historical versions, `revoked_by`
- `spec/policies/guardianship_policy_spec.rb` — added `#record?` coverage

**Also fixed:** two `return_to` redirects pointed at `accept_guardianship_path`,
which is POST-only — a guardian who signed out, or who had to go add a date of
birth first, would be GET-redirected there and 404. Both now return to the
invite page.

## Airtable Removal (HCB admin is the only system of record)

Upstream HCB mirrored applications, user PII, and ops queues into Hack Club's
Airtable bases via the `airrecord` gem. Fuime reviews business applications
entirely in the HCB admin console, so Airtable is gone rather than disabled.

**Why removal, not a feature flag:** the five table constants in
`config/initializers/airrecord.rb` were *hardcoded Hack Club base IDs*. Left in
place, any `AIRTABLE` credential entering the environment would have made this
fork read and write Hack Club's production Airtable — a Prime Directive 4
violation waiting on a single env var. Deleting the initializer removes the
possibility, not just the default.

Airtable was only ever a mirror: approve/reject/activate already operated on
Postgres `aasm_state`, and the admin list at `admin#applications` already
queried `Event::Application` directly. Nothing about the review workflow moved.

| Change | Why | Files |
|---|---|---|
| Deleted `airrecord` gem + the 5-table initializer | Hardcoded Hack Club base IDs; see above | `Gemfile`, `Gemfile.lock`, `config/initializers/airrecord.rb` |
| Deleted the 3 sync jobs and the nightly cron | Mirror had no consumer in Fuime | `app/jobs/event/*_airtable*.rb`, `app/jobs/event/sync_to_airtable*.rb`, `config/schedule.yml` |
| Dropped the `after_commit :schedule_airtable_sync` hook | Every application save enqueued a doomed outbound job | `app/models/event/application.rb` |
| Removed `set_airtable_status` / `sync_to_airtable` / `airtable_record` / `airtable_url` | Writers to a mirror that no longer exists | `app/models/event.rb`, `app/models/event/application.rb`, `app/controllers/events_controller.rb` |
| Removed the `airtable` redirect action, route, and policy method | Pointed at a Hack Club Airtable record | `app/controllers/event/applications_controller.rb`, `config/routes.rb`, `app/policies/event/application_policy.rb` |
| Removed `event_new/create_from_airtable` | Orgs come from approving an application; `event_create` (manual) already exists | `app/controllers/admin_controller.rb`, `config/routes.rb`, `app/views/admin/event_new_from_airtable.html.erb`, `app/views/admin/events.html.erb` |
| Removed `airtable_task_size` + all `*_airtable` pending-task badges | Each badge was a live authenticated call to Hack Club's Airtable API on admin dashboard load | `app/controllers/admin_controller.rb` |
| Removed `airtable_info` / `link_to_airtable_task` (12 Hack Club base IDs) | Hack Club perk queues with no Fuime equivalent | `app/helpers/static_pages_helper.rb` |
| Command bar: "Applications (Airtable)" → in-app `/admin/applications`; dropped 8 Hack Club perk entries | Admin actions are all in-app now | `app/javascript/components/command_bar/actions.js`, `app/views/application/_command_bar.html.erb` |
| Also removed `hackathons_task_size` | Orphaned with the badge block, and called `dash.hackathons.hackclub.com` with TLS verification disabled | `app/controllers/admin_controller.rb` |

### Behaviour changes (not just deletions)

- **Submission page admin panel** showed Airtable ID / status / last-synced.
  Now shows application ID, `aasm.human_state`, and `submitted_at` — the real
  Postgres state, which is strictly more accurate than the mirror ever was.
- **Contract reminder job** skipped reminders when the Airtable status was
  "Interview Scheduled"/"Invited to Interview". Interview state existed *only*
  in Airtable and has no Postgres equivalent, so the check is gone and reminders
  always send. Left as-is, `airtable_record["Status"]` would have raised
  `NoMethodError` on nil and killed every contract reminder.
- **`UserService::SyncWithLoops`** sent teenagers' legal name, date of birth and
  home address to a Hack Club Airtable base, and only adults to Loops. Since
  every Fuime user is a teenager, that was the hot path *and* the worst leak.
  All users now sync to Loops; `userGroup` is `"Teen"`/`"Adult"`, source `"Fuime"`.
- **`OrganizerPositionInvite#send_contract`** prefilled the contract description
  from Airtable's "Tell us about your event". Now uses `event.description`.
- **`Event#onboarding_scheduling_link`** returned a Hack Club onboarder's
  scheduling link; stubbed to `nil` (Fuime has no onboarding calls).
- **G Suite waitlist** check (`GWaitlistTable`) now `false`; G Suite is a
  Milestone 5 DISABLE target anyway.

### Tests

- `spec/models/event/application_spec.rb` — rewritten: the file previously tested
  only the Airtable sync. Now asserts saving enqueues **no** background job and
  that `Event::ApplicationSyncToAirtableJob` is undefined, so the outbound sync
  cannot be reintroduced silently.
- `spec/controllers/organizer_position_invites_controller_spec.rb` — dropped the
  `ApplicationsTable` stub; only Docuseal is stubbed now.
- `bundle exec rails zeitwerk:check` passes (whole app eager-loads), RuboCop
  clean on all touched files.

### Known remaining Hack Club endpoints (NOT part of this change)

- `disputed_transactions_airtable_form_url` (`app/helpers/hcb_code_helper.rb`)
  and `paypal_transfers_airtable_form_url` (`app/helpers/events_helper.rb`) send
  users to `forms.hackclub.com`. Despite the names these hit Hack Club's form
  host, not the Airtable API, and the dispute flow is live and user-facing —
  replacing it is its own task.
- `pending_identity_vault_verifications_task_size` calls
  `identity.hackclub.com`. Already `FUIME-DISABLED` in the admin_tools view, but
  the method remains.

## Loops.so Contact Sync Removal (Resend is the only email service)

Fuime already sends **all** transactional email through Resend via SMTP
(`config/application.rb` defaults to `smtp.resend.com`). Loops.so was never an
email sender in this codebase — it was a separate **marketing-CRM contact sync**
that pushed user profiles outbound and subscribed people to a mailing list.

**Why not "port Loops to Resend":** they are not equivalent services. Resend
Audiences stores only email, first name, last name, and unsubscribe status — it
has no custom fields. Most of what this sync pushed (birthday, last-seen,
last-login, billing address, `hasActiveOrg`, `hasCardGrant`, mailing-list
segmentation) has nowhere to land in Resend. Rather than ship a lossy port of a
CRM Fuime does not use, the sync is removed. Resend keeps doing what it already
does: sending the actual mail.

This also closes the last outbound path for teen PII. The Airtable removal above
had already rerouted teenagers' legal name / date of birth / home address from
Hack Club's Airtable into Loops; now that data does not leave Postgres at all.

| Change | Why | Files |
|---|---|---|
| Deleted `UserService::SyncWithLoops` | Pushed name, birthday, address, last-seen/login and org+card flags to Loops | `app/services/user_service/sync_with_loops.rb` |
| Deleted `User::SyncUserToLoopsJob` and `User::SyncToLoopsJob` | Per-user and nightly-backfill wrappers with nothing left to call | `app/jobs/user/sync_user_to_loops_job.rb`, `app/jobs/user/sync_to_loops_job.rb` |
| Removed the `user_sync_to_loops_job` cron (daily 07:00) | Walked **every** user and synced each one outbound | `config/schedule.yml` |
| Removed `after_update :queue_sync_with_loops_job, if: :verified?` and its method | Every verified-user update enqueued an outbound sync | `app/models/user.rb` |
| Deleted `spec/models/user_loops_sync_spec.rb` | Tested only the enqueue-gating of a job that no longer exists | `spec/models/user_loops_sync_spec.rb` |

**Kept deliberately:** the `users.subscribed_to_loops_at` column. Prime Directive 5
is new-migrations-only, and dropping a column is irreversible; it is now simply
unread. `was_onboarding?` also stays — `send_onboarded_email` still uses it.

`LOOPS` / `LOOPS__MAILING_LIST` credentials are now referenced nowhere in the app.

### Tests

- `bundle exec rails zeitwerk:check` passes (whole app eager-loads).
- `config/schedule.yml` parses; 65 jobs remain, none referencing Loops or Airtable.
- `spec/models/user_spec.rb` + `spec/models/user_account_type_spec.rb`: 72 examples, 0 failures.
- RuboCop on `app/models/user.rb`: the 2 remaining `Layout/ExtraSpacing` offenses
  (lines 128–129, guardianship associations) are **pre-existing** — verified
  identical on a clean stash — and were left alone.

## Auth: Security Keys, Phone Verification, Email Verification

**Security keys were broken in production.** WebAuthn validates the browser's
origin against `config.allowed_origins`, which was built from `LIVE_URL_HOST`.
That variable is unset on Render, so the allowed origin was the bare string
`"https://"` and every registration and sign-in attempt failed.

`rp_name` was also still `"Hack Club Bank"` — the name the browser/OS shows in
the passkey prompt, so it was user-visible branding.

**Phone verification hidden.** SMS login codes and phone 2FA go through Twilio
Verify. `TWILIO__SMS_VERIFY__*` are unset, so "verify your phone number" could
only ever fail. Gated behind `phone_verification_available?`; setting the
Twilio credentials restores the UI automatically. The phone *field* remains, so
a number can still be stored.

**Email verification: none exists.** There is no email-verification flow in
this codebase and no mailer for one. `User#verified` is set in
`LoginsController#complete` when a login completes — receiving the login code
*is* the verification. Nothing was missing or misdelivered.

| Change | Why | Files |
|--------|-----|-------|
| WebAuthn origin falls back to `RENDER_EXTERNAL_HOSTNAME` | `LIVE_URL_HOST` unset ⇒ origin `"https://"` ⇒ all keys fail | `config/initializers/webauthn.rb` |
| `rp_name` → "Fuime" | Shown in the OS passkey prompt | `config/initializers/webauthn.rb` |
| `phone_verification_available?` helper | Single switch for all phone UI | `app/helpers/users_helper.rb` |
| Gate SMS/2FA card, warning, and modals | Twilio unconfigured; controls could not work | `app/views/users/edit_security.html.erb`, `app/views/users/edit.html.erb` |
| "Sign in to HCB" → Fuime | Branding on the security page | `app/views/users/edit_security.html.erb` |

Verified on production: `allowed_origins=["https://fuime-web.onrender.com"]`,
`rp_name="Fuime"`, challenge generation succeeds, both settings templates
compile, zero 500s.

Note: keys registered against the Render hostname stop working if the site
moves to a custom domain — WebAuthn credentials are bound to the RP ID. Both
hosts are listed once `LIVE_URL_HOST` is set, but existing keys must be
re-registered after a domain change.

## Canonical Domain: fuime.com

`LIVE_URL_HOST=fuime.com` is set on both services, so mailer links, route
URL generation, WebAuthn origins, and markdown link handling all follow it.

`fuime-web.onrender.com` stays resolvable (Render owns that DNS), so instead
of serving the app there, `CanonicalHost` middleware 301s it to fuime.com.
That leaves one address for search, cookies, and WebAuthn.

Middleware rather than a controller filter, so it also covers routes that skip
ApplicationController's callbacks. Path and query string are preserved.

**Deliberately exempt** — these must answer on any hostname:
- `/up` — Render probes the health check on the internal hostname. Redirecting
  it fails the check and takes the service down.
- `/fuime/webhooks/stripe` — a 301 on a POST can drop the body, and Stripe's
  signature covers the original request. The endpoint verifies its own
  signature, so leaving it reachable is safe.

The middleware only activates when `LIVE_URL_HOST` is set AND differs from
`RENDER_EXTERNAL_HOSTNAME`, so it cannot redirect to itself in a loop.

| Change | Why | Files |
|--------|-----|-------|
| `CanonicalHost` middleware | Old URL served a full second copy of the app | `app/middleware/canonical_host.rb`, `config/application.rb` |
| Rebrand SEO meta tags | Every page shipped HCB nonprofit marketing copy and a hardcoded `og:url` of `hcb.hackclub.com` | `app/views/application/_seo_meta_tags.html.erb` |
| Disable brand download menu | `/brand/fuime-logo-{light,dark}.png` never existed; the links 404'd on the public storefront | `app/views/application/_logo.html.erb` |

Verified: old host 301s in a single hop with path+query intact; `/up` still
200 on the old host; fuime.com serves without redirecting; `og:url` is
`https://fuime.com/`; zero `hcb.hackclub.com` references in storefront HTML.

**Before launch:**
- Add real logo PNGs to `public/brand/` and restore the download menu.
- Replace the social image with a 1200x630 card (currently reuses
  `apple-touch-icon.png`, which exists but is small and square).
- WebAuthn credentials bind to the domain. `allowed_origins` lists both hosts,
  but any key registered on the Render hostname must be re-registered on
  fuime.com. Currently zero keys exist, so there is nothing to migrate.
