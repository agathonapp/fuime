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

## Regression coverage: impersonation activity feed

The fix in `189cdfeab` (dashboard 500 after impersonating an unverified user)
landed without a spec. Added one, since the failure mode is high blast radius:
the partial renders inside the dashboard activity feed, so a single
unrenderable row 500s every load of `/` for the admin.

| Change | Why | Files |
|--------|-----|-------|
| Add view spec for the session-create activity partial | The nil-user crash had no test pinning it and could silently return | `spec/views/public_activity/user_session/create_spec.rb` |

Verified by reverting the guard to `activity.trackable.user.name`: 3 of 5
examples fail with the original `undefined method 'name' for nil`. Restored the
guard; all 5 pass, plus the existing `spec/requests/users/unimpersonate_spec.rb`.

Notes for future sessions:
- `spec/rails_helper.rb:21` sets `PublicActivity.enabled = false` suite-wide, so
  any spec asserting on activity records must wrap them in
  `PublicActivity.with_tracking { ... }`.
- Tested at the view layer, not through `StaticPagesController`: the dashboard
  layout requires a compiled `bundle.js`, which the test environment does not
  build, so a `render_views` controller spec fails on the asset pipeline before
  reaching the partial.
- `user(allow_unverified: true)` resolves an unverified target's real name, so
  the `|| "an account"` fallback only fires for a session with no user row at
  all. Both branches are covered.
- `SessionSupport#create_session` writes `cookies.encrypted[...]` with an
  options hash, which only controller-spec cookie jars accept — it does not work
  in `type: :request` specs.

## 2026-08-01 — Milestone 3: surface rebrand (`fuime/m3-surface-rebrand`)

User-facing identity becomes Fuime; internals untouched per Rule 6. 336 files.

| Change | Why | Files |
|---|---|---|
| `hcb@hackclub.com` → `support@fuime.com` (62 sites) | Support mail was routed to Hack Club's inbox. Matches the existing `ApplicationMailer::OPERATIONS_EMAIL` convention already used by the guardianship code | `app/views`, `app/mailers`, `app/models`, `app/api`, `app/services`, `app/controllers`, `app/mailboxes`, `app/jobs` |
| `help_email` reads `OPERATIONS_EMAIL`; `help_phone` removed | Single source of truth. The phone number was Hack Club's support line — routing Fuime users there sends them to another org's desk. Removed rather than re-pointed; Fuime has no line | `app/helpers/application_helper.rb`, `app/views/layouts/apply.html.erb` |
| Standalone `HCB` → `Fuime` in display text (703 sites) | Brand surface. Applied only to the bare uppercase word; `hcb_code`, `HcbCode`, `hcb_*` helpers and `*.hcb.hackclub.com` domains excluded by the pattern and verified intact afterwards (2181 `hcb_code` refs still present) | `app/views`, `app/mailers` |
| Static location maps gated behind `STATIC_MAP_URL`, default off | **Privacy leak.** `maps.hackclub.com` is a private Hack Club Vercel project; every session list and login-notification email shipped the user's lat/long to another org's infrastructure on render. Now returns nil and callers omit the map (Prime Directive 4) | `app/helpers/application_helper.rb`, `app/helpers/stripe_cards_helper.rb`, `app/views/users/_user_session.html.erb`, `app/views/users/_oauth_authorization.html.erb`, `app/views/user/session_mailer/new_login.html.erb` |
| Login-alert security link → `settings_security_url` | Pointed at `hcb.hackclub.com/my/settings/security` — sent Fuime users to a different company's site to secure their account | `app/views/user/session_mailer/new_login.html.erb` |
| Removed "see how we do X on HQ!" promo captions (8 sites) | Linked into Hack Club's live production orgs. No Fuime equivalent exists, so removed rather than repointed | `app/views/events/*`, `app/views/invoices/index.html.erb`, `app/views/my/cards.html.erb` |

### Reverted mid-pass — do not redo

The blanket `HCB → Fuime` pass rewrote text where "HCB" named the *upstream
project* or Hack Club's *legal entity*. Both were correct before and false
after. Restored verbatim:

- **Attribution** (Rule 7, AGPL): `app/views/application/_footer.html.erb`,
  `app/views/layouts/_head.html.erb`, `app/views/layouts/mailer/_footer.html.erb`
  had become "Fuime is a fork of **Fuime** by Hack Club". These three lines name
  the upstream project and must never be rebranded.
- **Legal disclosure** (12 mailers): "fiscally sponsored by The Hack Foundation
  (d.b.a. **Fuime**), a 501(c)(3) nonprofit (EIN: 81-2908499)" asserted Fuime is
  a d.b.a. of Hack Club's charity and claimed their EIN. Restored to
  "d.b.a. Hack Club".

Lesson: a find-and-replace over brand strings cannot distinguish "our product"
from "the upstream project" or "the sponsoring legal entity". Audit any such
pass for proper nouns and legal text before trusting it.

### Still outstanding (NOT done in this pass)

- **~90 `Hack Club` literals and the fiscal-sponsorship copy remain.** These
  describe a 501(c)(3) fiscal-sponsorship product Fuime is not — the FAQ at
  `app/views/contract/parties/_fs_contract_faq.html.erb`, the marketing pages
  under `app/views/marketing/`, and the contract mailers. Rewriting them is a
  product/legal decision about what Fuime actually offers, not a string swap.
- `help.hcb.hackclub.com` article links, `blog.hcb.hackclub.com`,
  `graph.hcb.hackclub.com`, and `cdn.hackclub.com/rescue` still point upstream.
- Logos/favicons not swapped; `docs/fuime/BRAND_STRINGS.md` not yet written.

### Verification

Baseline measured from a clean worktree at `16a003485` (**not** the working
tree — mounting the edited tree invalidates the comparison):

| Scope | Baseline @ `16a003485` | After this change |
|---|---|---|
| `spec/views spec/mailers spec/helpers` | 37 examples, **19 failures** | 37 examples, **18 failures** |

Failure sets diffed by example id: **zero new failures.** The one fixed example
is `spec/views/public_activity/user_session/create_spec.rb:107`, from
uncommitted work already in the tree, not from this pass.

Most baseline failures are environmental — `cannot load such file -- sassc` in
the mailer specs' `stylesheet_link_tag`. The test image is missing that gem;
this is the toolchain problem `known-failures.md` describes, still unresolved.

All 303 modified ERB templates compile through Rails' own ERB handler. Three
layouts report "Invalid yield" both before and after the change — an artifact of
compiling a layout outside a render context, confirmed against pristine copies.

## 2026-08-01 — Milestone 3 (cont.): contract flow, FAQ, and marketing copy

| Change | Why | Files |
|---|---|---|
| DocuSeal template id now `ENV["FUIME_DOCUSEAL_TEMPLATE_ID"]`, unset by default; six hardcoded per-plan ids removed | Upstream served template 487784 (and five others) from **Hack Club's** DocuSeal account — their real fiscal sponsorship agreements. The flow was live, so a teen or guardian could sign another organization's binding legal document | `app/models/event/plan.rb`, `app/models/event/plan/*.rb` |
| `contract_available?` guards; flow completes with no contract | Without a template, applications stalled in `submitted` forever and `mark_approved`/`activate_event!`/`agreement` raised `NoMethodError` on nil | `app/models/event/application.rb`, `app/models/organizer_position_invite.rb`, `app/controllers/event/applications_controller.rb` |
| Contract FAQ rewritten for Fuime | Explained 501(c)(3) sponsorship, IP assignment to Hack Club's EIN, and IRS Determination Letters — beside a live signature field | `app/views/contract/parties/_fs_contract_faq.html.erb` |
| Onboarding videos behind `FUIME_ONBOARDING_VIDEO_IDS`, empty default; step auto-skips | A mandatory step titled "Watch Fuime's onboarding videos" played Hack Club's videos about HCB's rules | `app/models/event/application.rb`, `app/views/event/applications/videos.html.erb`, `app/controllers/event/applications_controller.rb`, `app/views/contract/party_mailer/notify_signee.html.erb` |
| Cosigner email rewritten | The parent-facing email claimed 501(c)(3) status, cited Hack Club's founding and real customer orgs as Fuime's, and advertised four features Fuime blocks at the request level | `app/views/contract/party_mailer/notify_cosigner.html.erb` |
| "…but will not have access or control" → guardians *can* see activity | Directly contradicted the Fuime guardian agreement ("You can see everything… cannot be turned off by the minor"). The application form was telling teens the opposite of what their guardian signs | `app/views/event/applications/{personal_info,show,edit}.html.erb` |
| `orpheus@hackclub.com` → `parent@example.com` (7 sites) | Placeholder emails pointed at a Hack Club address | `app/views/**` |
| "fiscal sponsorship agreement" → "the Fuime agreement"; remaining display `HCB` → `Fuime` in controllers/models/helpers/services/jobs | Copy surface my first pass didn't reach (it covered views/mailers only) | ~40 files |
| Testimonials, funder team, and funder marquee emptied | Real named people (Jasmine Sun, Isaac Sevier, Richard Littauer) quoted about HCB; three Hack Club staff shown as Fuime's team; Ford/Omidyar/Hewlett/Sloan/SoftBank/Founders Fund logos under "Major funders already back organizations on Fuime" — false, and on an indexable page | `app/helpers/marketing_helper.rb`, `app/views/marketing/funders.html.erb` |
| `/for/funders*` FUIME-DISABLED (redirect for humans, 404 otherwise) | JSON-LD declared `"legalName": "The Hack Foundation"` with `taxID: 81-2908499`, telling search engines Fuime *is* Hack Club's 501(c)(3). Public, indexable, and orphaned — nothing in the app links to it | `app/controllers/marketing_controller.rb`, `spec/requests/marketing_spec.rb` |

### Ledger regression — caught pre-commit, worth reading before the next sweep

Applying the `HCB → Fuime` word replacement to `.rb` files corrupted ledger
internals, because `HCB` is not only a brand there — it is a **stored data
prefix**. The sweep rewrote:

- `TransactionGroupingEngine::Calculate::HcbCode::HCB_CODE = "HCB"` → `"Fuime"`
  — the prefix every HCB code in the database is built from. This alone
  orphaned all existing ledger data and broke 10 `statement_of_activity` specs.
- `ilike 'HCB-000%'`, `memo ~ '.*HCB-\w{5}.*'`, `CONCAT('HCB-300-', ...)` and
  ~30 similar SQL literals — scopes that would silently match **nothing**.
- `statement_descriptor: "HCB-#{short_code}"` — the text printed on a
  customer's bank statement for real Stripe payouts.
- `'%COLUMN*THE HACK HCB-SWEEP%'` — a literal bank memo string.

Every ledger-critical file was restored to HEAD and verified byte-identical:
`hcb_code.rb` (grouping engine), `canonical_transaction.rb`,
`canonical_pending_transaction.rb`, `hcb_code.rb`, `transaction.rb`,
`statement_of_activity.rb`, `ledger/item.rb`.

One instance of this bug **shipped in the previous commit** (`b9c5e2b6e`):
`app/views/admin/unknown_merchants.html.erb` linked to `hcb_code_path("Fuime-600-…")`,
a code that cannot resolve. Fixed here.

Rule for future passes: before replacing `HCB` in a `.rb` file, check whether
the literal is *compared against or written to the database*. `HCB-` followed by
digits, an interpolation, or `\w{5}` is data, never branding. Rule 3 covers more
than the pipeline classes — it covers the string constants they build codes from.

### Verification

Same scope, clean-worktree baseline at `33b11bfb8`:

| Scope | Baseline | After |
|---|---|---|
| `spec/models/event spec/views spec/mailers spec/helpers spec/requests` | 161 examples, **51 failures** | 143 examples, **8 failures** |

Failure sets diffed by example id: **zero new failures.** The example-count drop
is the 22 upstream funders-page examples replaced by 4 that pin the disabled
state (including one asserting Hack Club's EIN and legal name cannot reach a
visitor).

### Still outstanding

- **DocuSeal is wired but not set up.** It needs a Fuime DocuSeal account, the
  `DOCUSEAL` + webhook credentials, and — the real blocker — an actual Fuime
  agreement document. Drafting that is a legal task, not a code change
  (CLAUDE.md puts the merchant-of-record structure in Phase 2). Until
  `FUIME_DOCUSEAL_TEMPLATE_ID` is set, no one signs anything.
- `static_pages/branding.html.erb` still describes fiscal sponsorship, restricted
  funds, and Column backing.
- `documents/fiscal_sponsorship_letter.pdf.erb`, `verification_letter.pdf.erb`,
  and `events/termination.pdf.erb` are unreviewed legal documents.
- `help.hcb.hackclub.com` / `blog.hcb.hackclub.com` / `graph.hcb.hackclub.com`
  links, and `cdn.hackclub.com` assets (fonts, images) still load from Hack Club.
- Logos/favicons partially done; `docs/fuime/BRAND_STRINGS.md` still not written.

---

## Application flow: unblock submission and finish the rebrand (2026-08-01)

The apply flow could not be completed by the users Fuime exists for. Three
independent defects, two of them hard blockers.

### 1. Guardianship enforcement deadlocked the application flow (hard blocker)

**Files:** `app/controllers/concerns/fuime/guardianship_enforcement.rb`

`GuardianshipEnforcement` is a deny-by-default filter: any signed-in user who is
a minor (or whose age is unknown) without an *accepted* guardianship is
redirected to `/guardian/new`. `event/applications` was not on the allowlist, so
every page of the apply flow bounced.

That is a closed loop for Fuime's core user. A teen cannot apply without an
active guardianship, and the application *is* where the parent's email is
collected and the agreement is sent — so they cannot obtain one either. The
platform's primary onboarding path was unreachable for 13–17 year olds.

Allowlisted `event/applications`, `event/affiliations` (the affiliations subform),
`contracts`, and `contract/parties` (signing the agreement that produces the
guardianship). The control is **not** weakened: `events` stays blocked,
`EventPolicy` still denies writes to an unguarded minor, and `activate_event!`
still requires the signed contract. A teen can now fill in an application but
still cannot operate a business until a guardian actually signs.

### 2. `teen_led` was never persisted, so no teen could submit (hard blocker)

**Files:** `app/controllers/event/applications_controller.rb`

The intro screen's "Are you under 18?" radio is rendered by `form_with model:`,
so it posts as `event_application[teen_led]`. `create` read only the bare
`params[:teen_led]`, which was always nil — every application was created
`teen_led: false`.

Consequence: teens were silently routed down the *adult* branch of
`application_ready_to_submit?`, which additionally requires `planning_duration`,
`team_size`, `annual_budget_cents`, and `committed_amount_cents`. The teen form
never renders those four fields, so they could never be filled — the submit
button stayed disabled forever with no explanation. Reproduced and pinned in
`spec/controllers/event/applications_spec.rb`.

`create` now reads the nested field, still accepting the bare param used by the
post-sign-in `start` redirect.

### 3. The submit gate gave no reason for refusing

**Files:** `app/models/event/application.rb`, `app/views/event/applications/review.html.erb`

`may_mark_submitted?` returns only a boolean, so the review page disabled the
button and pointed at a summary that marks missing fields but omits cross-field
rules entirely. Added `Event::Application#submission_blockers`, which returns
human-readable labels for each unmet requirement including the disallowed-country
and cosigner-email-collision rules. The review page renders them as a checklist.

`application_ready_to_submit?` and `submission_blockers` now share one
`required_submission_fields` list, so the displayed checklist and the actual gate
cannot drift apart — pinned by a spec asserting the two agree.

### 4. Residual Hack Club branding in the apply flow

Rule 6 respected throughout: user-facing strings only, no class/table/route renames.

| File | Change |
|---|---|
| `applications/_summary.html.erb` | "No affiliations added for any VEX teams, FIRST teams, or Hack Club chapters" → "No affiliations added" |
| `applications/project_info.html.erb` | `https://hackclub.com` placeholder → `https://mayasartprints.com` |
| `applications/edit.html.erb` | `hackclub.com` placeholder; "Project name"/"Leosia Hacks" → business framing; nonprofit "charitable purpose" description → "What does your business do?"; "applied for fiscal sponsorship with Fuime" → "used Fuime before" |
| `applications/show.html.erb` | "fiscal sponsorship agreement" → "Fuime agreement"; fixed "your contact" → "your contract" typo |
| `application_mailer/confirmation.html.erb` | "Fuime, Hack Club's fiscal sponsorship program" → "the financial platform for teen-run businesses"; "Fuime Fiscal Sponsorship Agreement" → "Fuime agreement" |
| `application_mailer/under_review.html.erb` | same rebrand; removed P.S. linking `hackclub.com/fiscal-sponsorship/directory` |
| `application_mailer/approved.html.erb` | "activate your organization"/"Fiscal Sponsorship Agreement" → "activate your business"/"Fuime agreement" |
| `application_mailer/incomplete.html.erb` | removed "Learn more about Fuime's features" → `hackclub.com/fiscal-sponsorship` |
| `application_mailer/activated.html.erb` | removed the tag-conditional block promoting Hack Club's hackathon guide, Discord bot, and club toolbox; dropped the donation-page bullet (donations are a disabled module) |

**Also fixed a latent crash** in `activated.html.erb`: it called
`@application.contract.document` unguarded. With no DocuSeal template configured
(the current state — see "Still outstanding") `contract` is nil, so activating an
application would raise. Now guarded on `contract&.document`.

### Verification

Docker, clean-worktree baseline at `d7645cf4b` vs. working tree, same scopes,
failure sets diffed by example id:

| Scope | Baseline | After |
|---|---|---|
| `spec/models spec/controllers spec/policies spec/mailers` | 1390 examples, **38 failures** | 1409 examples, **38 failures** |
| `spec/requests spec/jobs spec/services spec/helpers spec/views` | 512 examples, **14 failures** | 512 examples, **14 failures** |

**Failure sets are identical — zero regressions.** The 38 and 14 are pre-existing
(ACH, payroll/DocuSeal, wires, G Suite, invoices, FIRST, logins). The +19 examples
are the new application specs, all passing.

New specs: `spec/controllers/event/applications_spec.rb` (7), additions to
`spec/models/event/application_spec.rb` (10) and
`spec/controllers/fuime/guardianship_enforcement_spec.rb` (2).

## 2026-08-02 — Milestone 3 (close-out): the rest of the brand surface (`fuime/m3-finish-brand-sweep`)

Closes the three items the previous M3 pass recorded as outstanding (residual
`Hack Club` literals, upstream `hcb.hackclub.com` links, missing
`BRAND_STRINGS.md`) and, in the process, four things that were worse than
branding. `docs/fuime/BRAND_STRINGS.md` is the full classification; this is the
change log.

### Documents that made claims Fuime cannot make

| Change | Why | Files |
|---|---|---|
| `fiscal_sponsorship_letter` + `verification_letter` routes removed; Documents-page tiles removed | Two downloadable PDFs on **Hack Club letterhead** — their logo, a real employee's scanned signature, EIN 81-2908499 — certifying The Hack Foundation as the business's fiscal sponsor. The verification letter also attested an account "in good standing with **Column N.A.**, a Member of the FDIC" and printed the account + routing numbers: a bank-verification document. Both were linked from every org's Documents page. The half-finished rebrand had made it worse — the contact line read `support@fuime.com` under Hack Club's letterhead, so anyone calling to verify reached Fuime about a claim only Hack Club could make | `config/routes.rb`, `app/views/documents/index.html.erb` |
| `EventPolicy#termination?` → false | Generates a legal agreement terminating "the Agreement between The Hack Foundation ('Hack Club') and \<business\>", under which "Hack Club shall… transfer the balance of assets in Hack Club's restricted Fund" — successor defaulting to The Hack Foundation. Auditor-gated and unlinked, so never teen-reachable, but the same class of document as the letters above | `app/policies/event_policy.rb` |
| `zach_signature.png` removed as prefilled countersignature | The scanned signature of Hack Club's founder was the `default_value` on the "Signature" field of Fuime's contracts, fetched from `hcb.hackclub.com`, and was drawn on the check template. Latent (DocuSeal is gated off by default) but configuring a template would have countersigned Fuime agreements on his behalf | `app/models/contract/fiscal_sponsorship.rb`, `app/models/contract/payroll_position.rb`, `app/views/increase_checks/_paper_check.html.erb` |

### Live calls to Hack Club infrastructure (Prime Directive 4)

| Change | Why | Files |
|---|---|---|
| Changelog widget renders nothing; `blog_controller#updateBadge` no-ops | The widget sat in the header of **every authenticated page** plus the admin layout, user menu and docs header. It iframed `blog.hcb.hackclub.com/embed` and fetched `/api/unreads` **with `credentials: 'include'`** on every page load — a credentialed cross-origin request to another organization's server, showing HCB's changelog under the label "See what's new with Fuime" | `app/views/application/_blog_widget.html.erb`, `app/javascript/controllers/blog_controller.js` |
| Phantom Sans `@font-face` removed; marketing headings fall back to the system stack | Hack Club's brand typeface, fetched from `assets.hackclub.com` on every marketing page load. A trademark use the AGPL does not license (Rule 7) as well as a Prime Directive 4 violation. The preconnect/preload pair went with it | `app/assets/stylesheets/components/_marketing.scss`, `app/views/marketing/funders.html.erb` |
| Default avatar now `icons/person.svg`, served locally | `profile_picture_for` defaulted to a `cdn.hackclub.com` placeholder, so nearly every authenticated page requested an image from Hack Club's CDN | `app/helpers/users_helper.rb`, `app/views/public_activity/_common.html.erb`, `app/views/reimbursement/reports/_conversation.html.erb` |
| ~40 `cdn.hackclub.com` images/backgrounds neutralised | Promo card backgrounds, the `card--sunset` pair (no callers), the seasonal "witch orpheus" sprite (also their mascot), the FIRST dashboard screenshot, the Wise and Discord logos, and 3 flavor-text images. Tailwind arbitrary-value classes compiled some of these into **all three CSS bundles**, so they shipped to pages that never rendered them | `_promos.scss`, `_cards.scss`, `_dark.scss`, `components/_marketing.scss`, `layouts/_seasonal.html.erb`, `users/first/index.html.erb`, `integrations/_discord_integration.html.erb`, `reimbursement/reports/wise_transfer_breakdown.html.erb` |
| `LoginsHelper::HACKATHONS` emptied | A `cdn.hackclub.com` photo of their 2022 "Assemble" hackathon, used as a login background, linking to a `/assemble` route that does not exist here. `sample_hackathon` has zero callers, so nothing rendered either way | `app/helpers/logins_helper.rb` |

After this pass `grep -c hackclub app/assets/builds/*.css` is **1 per bundle** —
a `github.com/hackclub/hcb` issue link in a source comment (legitimate attribution).

### URLs and copy pointing users at HCB

| Change | Why | Files |
|---|---|---|
| CSV export URL columns derive from `root_url` | The `comma` blocks hardcoded `https://hcb.hackclub.com/…`, so a Fuime user's CSV export handed them links into Hack Club's app, where their records do not exist. **Scoped strictly to the export blocks** — `HCB_CODE = "HCB"` and every ledger scope are untouched | `app/models/event.rb`, `app/models/hcb_code.rb`, `app/models/user.rb` |
| Twilio SMS + Discord notification links derive from `root_url` | A teen texting in a receipt was told to visit `hcb.hackclub.com/my/settings`; the receipt-bin confirmation linked to `hcb.hackclub.com/my/inbox`; Discord notifications rewrote relative hrefs to absolute HCB URLs. The Twilio job already `include`d `url_helpers` and used `hcb_code_url` elsewhere, so the hardcoded strings were inconsistent with the file's own convention | `app/jobs/twilio/process_webhook_job.rb`, `app/jobs/discord/process_notification_job.rb`, `app/models/announcement/templates/monthly.rb` |
| ~20 "Learn more … **on Fuime** →" links removed | Every one pointed at `help.hcb.hackclub.com` — a Fuime label on Hack Club's help centre, documenting HCB's products. Removed rather than repointed; Fuime has no help centre. Also the transfer wizard's four per-answer article links, whose "learn more" element is now hidden rather than rendering `href="undefined"` | 13 files, listed in `BRAND_STRINGS.md` |
| One-pager empty states: `screenshots:` and `support_article:` now optional | All 13 callers passed screenshots **of hcb.hackclub.com** hosted on `cdn.hackclub.com` / `user-cdn.hackclub-assets.com`. On Invoices — Fuime's own money-in feature — a teen saw a picture of a different product. The copy column now widens to fill the row when absent | `app/views/events/_one_pager.html.erb` + 13 callers |
| 29 flavor-text entries removed | Dashboard taglines that were Hack Club in-jokes ("The Hack Club Federal Reserve", "From the makers of Hack Club"), links to zephyr/assemble.hackclub.com, or `cdn.hackclub.com` images. One read "Here's a secret: **Fuime** stands for Hack Club Bonk" — a half-applied rebrand | `app/services/flavor_text_service.rb` |
| `onboarding_gallery` emptied; panel hidden when empty | 8 screenshots of real Hack Club organizations on the signup screen, each linking to that org on `hcb.hackclub.com` — reading as Fuime's own customers, and sending a teenager mid-signup to another company's product | `app/helpers/users_helper.rb`, `app/views/users/edit.html.erb` |

### The "trap page" pattern — three nav items for products Fuime does not offer

`Fuime::DisabledModules` blocks **writes only**, by design, to preserve read
access to inherited records. But the nav entries for Cards, Donations and
Google Workspace were gated on `EventPolicy` predicates checking only plan
features — and `Event::Plan::Standard`, the default for every new org via
`EventService::Create`, enables all three.

So a normal member saw three sidebar entries for products Fuime does not offer,
clicked through to fully-rendered pages, and found out only when a submission
bounced with "That feature isn't available on Fuime."

| Change | Why |
|---|---|
| `card_overview?`, `donation_overview?`, `g_suite_overview?`, `promotions?` → false | Gating at the policy closes the page *and* the nav link together, because each controller action authorizes on the predicate the nav is built from. Cards specifically is "hide, don't delete" per CLAUDE.md Milestone 5 |

The Perks page (`promotions?`) had the loosest gate in the app —
`auditor_or_reader?` — and every perk on it is a Hack Club program Fuime cannot
deliver: HCB stickers, their 1Password / StickerNinja / StickerMule / Replit /
GitHub partnerships, hackathon grants, free domains. The PVSA card told the
user "Since you run on Fuime, you can issue Presidential Volunteer Service
Awards" — eligibility that depends on 501(c)(3) status Fuime does not have.

Section headers survive: "Spend" still has Reimbursements, "Receive" still has
Invoices. `donation_overview?` is distinct from `donation_page?`, so the public
donation page is unaffected.

### Bug fix: the admin header logo covered the page

Reported mid-session with a screenshot — the Fuime wordmark rendering at full
size over the admin console.

`admin.scss` does not import `components/_header.scss`, so the `.logo {
display: block }` half of the light/dark pair never existed in that bundle —
only `.logo-dark { display: none }`. Two failures followed:

1. The admin bundle's preflight reset sets `img { max-width: 100%; height:
   auto }`. A CSS declaration **beats the presentational `height="36"`
   attribute** the logo partial sets, so the mark rendered at its intrinsic
   512×425.
2. In dark mode `_dark.scss` sets `.logo-dark { display: block }`, overriding
   the local `display: none` and showing that unsized image.

`application.css` has no such `img … height: auto` reset, which is why the logo
only broke in admin. Fixed by pinning `height: 36px; width: auto` on both
variants and adding the missing `.logo { display: block }`. The dark-mode swap
still wins on specificity (`html[data-dark=true] .logo` is 0,2,0 vs 0,1,0).

Verified against the rebuilt bundle by enumerating every `.logo` rule in
declaration order.

### Not mine: `app/controllers/event/applications_controller.rb`

This file was already modified in the working tree at the start of the session
— leftover uncommitted work from `cafd73bba`, adding a `contract&.party(:hcb)`
nil-guard consistent with the `contract_available?` gating in
`app/models/event/application.rb:288`. Correct and complementary, so it is
carried along rather than reverted, but it is not part of this change.

### Verification

Executed in Docker against a clean worktree baseline at `cafd73bba`. **Both
trees had assets built from their own source** (`yarn build && yarn build:css`)
— without that, the missing-stylesheet artifact described in
`known-failures.md` swamps every view-rendering spec and the comparison says
nothing.

| Scope | Baseline `cafd73bba` | This branch |
|---|---|---|
| `spec/models spec/controllers spec/policies spec/mailers` | 1409 examples, **38 failures** | 1416 examples, **38 failures** |
| `spec/requests spec/jobs spec/helpers spec/views` (seed 1234) | 99 examples, **4 failures** | 104 examples, **4 failures** |
| The 9 `spec/services` files that fail at baseline, + their siblings (seed 1234) | 79 examples, **10 failures** | 79 examples, **10 failures** |

**Failure sets diffed by example id in all three scopes: zero new, zero fixed.**
The +7 and +5 examples are the new specs below, all passing. The pre-existing
failures are the usual set — ACH/outgoing-ach import, G Suite mailers, invoices,
payroll/DocuSeal, wires, FIRST, logins.

New specs, executed:

| Spec | Result |
|---|---|
| `spec/requests/documents_letters_spec.rb` (new, 5) | **0 failures** |
| `spec/policies/event_policy_spec.rb` (+6, file total 24) | **0 failures** |

`documents_letters_spec` pins both letter routes as removed and asserts no route
helper matching either name exists. The policy specs pin the five disabled
predicates false **for the subject upstream would have allowed** — a manager on
an approved Standard-plan org, and an auditor for `termination?` — assert the
plan really does enable each feature so the examples cannot pass vacuously, and
check `show?` / `reimbursements?` still pass so the denial is not overbroad.

Non-suite checks:

| Check | Result |
|---|---|
| `ruby -c` on all 15 modified `.rb` files; `node --check` on both `.js` | pass |
| ERB compile, **differentially** vs each file's pristine `HEAD` version | **0 regressions** across 28 templates |
| `yarn build` + `yarn build:css` | both compile; `hackclub` refs 20 → 1 in `application.css`, 1 per bundle overall |
| Every `.logo` rule enumerated in the rebuilt `admin.css` in declaration order, specificity checked | correct in both colour schemes |
| Grep audits: no dangling letter path helpers; no callers of the disabled predicates outside nav gates; `HCB_CODE` and all ledger scopes byte-identical | pass |

#### Two measurement traps hit on the way — read before trusting a run

1. **A naive ERB checker reports 28 false failures.**
   `ERB.new(src, trim_mode: "-")` fails on 28 templates *that fail identically
   before any edit*: Rails uses its own Erubi handler with different trim
   semantics, and `action_view` will not load on this host (the Ruby version
   mismatch in SETUP_NOTES). Comparing each file to its own pristine version
   under the same checker is the sound test. Never read a raw count from it.

2. **A run can end early and still print a clean summary.** One
   `spec/services` run reported "33 examples, 3 failures" with no error and no
   DB disconnect; `--dry-run` confirmed the same selection loads **79**. Re-run
   with `--seed 1234` gave 79/10, matching baseline exactly. An example count
   that disagrees with the baseline's is the tell — **compare counts before
   comparing failures**, and pin the seed on both sides.

   Relatedly: `spec/services` alone exceeds a 10-minute timeout, and
   backgrounding `docker run` with `nohup … &` from a tool shell dies with the
   parent, leaving an empty log that reads as "0 failures". Both cost a round
   here.

---

## Approval flow: nil-contract crash + the DocuSeal path back on

Clicking **Approve** on a teen-led application 500'd (`ERR-54A66FEA`). The
approval itself succeeded — state moved to `approved`, the mailer fired — and
then the redirect raised, which is why the error page carried a green
"Application approved." flash.

| Change | Why | Files |
|---|---|---|
| `admin_approve` nil-guards the contract | It did `@application.contract.party :hcb` whenever `teen_led?`. Since `send_contract` returns nil while no template is configured, teen-led applications have no contract and this dereferenced nil. The model's own `mark_approved` callback already guards with `teen_led? && contract.present?` — the controller was the one place that missed it | `app/controllers/event/applications_controller.rb` |
| `next_step` returns a string when approved-but-not-activated | Every branch missed that state, so it returned nil and `_application_card` fell through to its hardcoded "We're reviewing your application" — displayed directly beside an **Approved** badge | `app/models/event/application.rb` |
| `docs/fuime/DOCUSEAL_SETUP.md` written | `Event::Plan#contract_docuseal_template_id` already told readers to "see docs/fuime/DOCUSEAL_SETUP.md". The file did not exist | new file |
| Three DocuSeal vars added to the env example | `FUIME_DOCUSEAL_TEMPLATE_ID`, `DOCUSEAL`, `DOCUSEAL__WEBHOOK_SECRET`, all blank | `.env.development.example` |

**No integration code was written.** The DocuSeal client, webhook receiver,
party sync, reminders, and document archival are all upstream and intact; the
only things missing were the template and the credentials. The setup doc pins
the exact role strings (`Contract Signee` / `Cosigner` / `Fuime`) and field
names the code matches literally, because a mismatch fails at send or webhook
time rather than at template creation.

**Known gap, unresolved by these changes:** with no contract configured, an
approved application has no route to activation. The Activate button lives on
the contract-party page, and the submission page's fallback branch requires
`contract.present?` (`submission.html.erb:108`). Configuring DocuSeal per the
new doc closes this. Leaving it unconfigured means approval is terminal in the
UI — `admin_activate` works but has no button.

### Verification

| Check | Result |
|---|---|
| `ruby -c` on both modified `.rb` files | pass |
| Grepped `spec/` for `next_step`, `contract_available`, `FUIME_DOCUSEAL` | no specs assert on these; nothing to update |
| Audited every `contract.` dereference in the application flow | `submission.html.erb` (52, 108) and `applications_controller#show` (46) are already guarded; no other unguarded call sites |

Not executed: the suite and the flow itself. The Gemfile pins Ruby 3.4.9; this
host has 3.4.6 / 3.4.10 / 4.0.6 and Bundler rejects the patch mismatch, and the
Docker daemon is not running. Both changes are verified by reading and syntax
check only — re-run the approval once a working environment is up.

---

## Money-in wired up: the storefront can actually take a payment

`PaymentLinkService` and `PaymentWebhookHandler` were both already written and
correct, but **nothing called the service** — the storefront's Pay button was
hardcoded `disabled` with "(Payment links coming soon)". The receiving half of
the payment flow existed; the sending half did not. This closes
PRODUCTION_READINESS §2.1.

| Change | Why | Files |
|---|---|---|
| New `Fuime::CheckoutsController` + `POST /b/:slug/pay` | The missing entry point. Public and unauthenticated (the payer is a customer, not a user), so it validates: storefront must be published, amount clamped to $1–$10,000, non-numeric input rejected rather than raising, and Stripe errors are logged but never surfaced to the payer | `app/controllers/fuime/checkouts_controller.rb`, `config/routes.rb` |
| Storefront Pay form replaces the disabled button | Amount + description, composed from existing HCB form partials and classes per spec §4. Shows the fee up front, and a test-mode hint with card 4242 while `STRIPE_MODE=test` | `app/views/fuime/storefronts/show.html.erb` |
| Payer-supplied description is bounded and sanitised | It reaches the Stripe product and then the ledger memo a teenager reads. Control characters stripped, truncated to 120 chars, so an anonymous stranger cannot write arbitrary text onto a child's ledger | `app/controllers/fuime/checkouts_controller.rb` |
| The 4% fee posts as its own ledger line | It was only ever written into Stripe metadata. The teen's ledger showed the gross, so their net was overstated — and so was the income the Tax Tracker reported to their family. Now visible, labelled, and `fronted: false` like every other Fuime line | `app/services/fuime/payment_webhook_handler.rb` |
| Refunds and chargebacks rebate the fee proportionally | Without it, a fully refunded payment left the business **net negative by the fee** — a teen would pay Fuime for being defrauded on a chargeback. Keyed `fuime_feerev_*` (distinct from the `fuime_rev_*` reversal prefix, so the two prefix-sums can't contaminate each other) and capped at the fee actually charged | `app/services/fuime/payment_webhook_handler.rb` |
| `"platform fee refunded"` added to `EXCLUDED_MEMO_PATTERNS` | The rebate is the reversal of an expense, not revenue. Counting it as income would inflate a teen's taxable income. The fee **charge** is deliberately NOT excluded — it is a genuine deductible business expense | `app/services/fuime/tax_tracker_service.rb` |

### Verification — all executed, in Docker on the pinned Ruby 3.4.9

| Suite | Result |
|---|---|
| `spec/services/fuime/payment_webhook_handler_spec.rb` | **16 examples, 0 failures** |
| `spec/services/fuime/tax_tracker_service_spec.rb` | **15 examples, 0 failures** |
| `spec/controllers/fuime/checkouts_controller_spec.rb` (new, 10) | **0 failures** |
| `spec/controllers/fuime/storefronts_controller_spec.rb` (new, 7, `render_views`) | **0 failures** |
| `spec/services/fuime/payment_flow_integration_spec.rb` (new, 3) | **0 failures** |
| `spec/controllers/event/applications_controller_spec.rb` (new, 3) | **0 failures** |
| Fuime feature suite (guardianship, services, controllers) | **81 examples, 0 failures** |

Eight webhook specs asserted exact ledger-line counts and legitimately failed
when the fee added a line. They were rewritten to assert the business's **net**
rather than a raw count — a stronger assertion, since it pins what the teen
actually keeps.

The approval-crash fix from the previous entry is now **executed-verified**: the
new regression spec was run against the reverted code and reproduces
`NoMethodError: undefined method 'party' for nil` exactly, then passes against
the fix.

### Still open

- The storefront renders `render_views`-clean, but the flow has **not** been
  clicked through against live test-mode Stripe — that needs `STRIPE__TEST__*`
  keys and `stripe listen`, which this environment doesn't have.
- Everything in PRODUCTION_READINESS §1.5 (money transmission) is untouched and
  still gates real money. Posting the fee as a ledger line does not make the
  pooled-custody model lawful; it only makes it honest on screen.

---

## The other half of the outage: approved applications never became businesses

The nil-contract guard in `admin_approve` stopped the 500, but the flow was
still dead one step later — an approved application could not be activated, so
no `Event` was ever created. Four separate defects, all downstream of the same
assumption that a contract always exists.

| Change | Why | Files |
|---|---|---|
| `activate_event!` nil-guards `contract.create_document!` | Only a signed contract yields a countersigned PDF to file. On nil this raised **inside `with_lock`**, so `Event.create!` rolled back with it — the visible symptom being "approval worked but no business appeared" | `app/models/event/application.rb` |
| Point-of-contact fallback nil-guarded, with an explicit error | `point_of_contact.presence \|\| contract.party(:hcb).user` raised on nil rather than saying what was missing | `app/models/event/application.rb` |
| `tags:` defaults to `nil`, coerced with `Array()` | The controller passes `params[:tags]`, which is **nil** when an admin selects no tags. A Ruby default only applies to an *omitted* argument, never an explicit nil, so `tags.filter` raised `undefined method 'filter' for nil`. This one bit even when a contract existed | `app/models/event/application.rb` |
| Inline Activate form on the submission page | The only Activate control in the app lived on the contract-party page (`submission.html.erb:108` required `contract.present?`). With no contract there was no page and no button — `admin_activate` was reachable only by hand-crafting a POST | `app/views/event/applications/submission.html.erb` |

The tags bug is worth singling out: it was not specific to the no-contract path
and would have failed any activation where the admin picked no tags.

### Verification

| Check | Result |
|---|---|
| `spec/controllers/event/applications_controller_spec.rb` (5, incl. `Event.count` change) | **0 failures** |
| `spec/controllers/guardianships_render_spec.rb` (new, 6, `render_views`) | **0 failures** |
| `submission.html.erb` ERB compile | OK |

The guardianship specs are new coverage for demo steps 2–3: the invite and
accept screens had thorough model and policy specs but **nothing that rendered
them**, the same blind spot the storefront had.

### Note on the reported symptom

The dashboard card reading "We're reviewing your application" beside an
**Approved** badge was reproduced from the deployed Render app, which does not
carry any of this work. The `next_step` fix addresses it; it needs deploying,
not further debugging.

---

## Security keys could not be registered by anyone

Reported as "I can't register a security key as an admin." It was not
admin-specific: **every** request to `WebauthnCredentialsController` raised
before reaching an action, so no user could register a key at all.

| Change | Why | Files |
|---|---|---|
| Removed two `skip_*_action ... only: [:auth_options]` callbacks | The controller has no `auth_options` action — it lives on `UsersController` as `webauthn_options`. Rails 7.1 raises `AbstractController::ActionNotFound` when a callback names an action the controller does not define, so the whole controller was dead. All three actions require a signed-in user and authorize, so the skips had nothing to do anyway | `app/controllers/webauthn_credentials_controller.rb` |
| Normalise `params[:type]` before the enum | The form radio posts `cross_platform`; the Stimulus controller overwrites it with `cross-platform`, the hyphenated spelling the WebAuthn API requires for `authenticator_attachment`. Passing that to the enum raised `'cross-platform' is not a valid authenticator_type`, so **roaming keys (YubiKey, phone) failed while platform keys worked** | `app/controllers/webauthn_credentials_controller.rb` |
| New `UserPolicy#manage_webauthn_credentials?` (self-only) | Both actions authorized on `edit?`, which is `auditor? \|\| record == user`. An auditor could mint registration options for another user and **attach their own security key to that user's login** — a persistent authentication backdoor. Registering a credential is an auth change, not a read; `edit?` is correct for read-oriented settings views and too broad here | `app/policies/user_policy.rb`, `app/controllers/webauthn_credentials_controller.rb` |

`WebauthnCredentialPolicy#destroy?` (`admin? || record.user == user`) was
reviewed and left alone — deleting a key is recoverable and admins legitimately
need it for account recovery.

### Verification

`spec/controllers/webauthn_credentials_controller_spec.rb` (new, 5) — **0
failures**. Two of the five pin the auditor privilege boundary and fail against
the old policy. `logins_controller`, `users_controller`, and
`sudo_mode_handler` re-run: the only failures are the 3 pre-existing
`logins_controller` ones in the baseline's 34 (stale copy asserting "Your HCB
account has been locked").

Not verified: a physical key against a browser. The fake client covers the
protocol, not the hardware.

## Crash test — 500s found by crawling every route as every persona

Method: seeded a teen/guardian/adult/unguarded-minor/admin scenario with an
approved business, signed in as each through the app's own `sign_in`, and
requested all 314 reachable GET routes per persona, recording every 5xx.
All of these were live on `main`, i.e. on the deployed app.

| Change | Why | Files |
|--------|-----|-------|
| Guardianship filter exempts admins and auditors | `minor_or_unknown_age?` treats a nil birthday as a minor, so every staff account (no birthday on file) was redirected to `/guardian/new` on **every** page, including the admin console. `EventPolicy` already exempted staff; the request filter did not. | `app/controllers/concerns/fuime/guardianship_enforcement.rb` |
| `include RolesHelper` in ApplicationHelper | `include_all_helpers = false`, so `role_label` (added by the brand sweep) was undefined in the 5 views that call it — `/:business/team`, `/:business/invites/new` and `/roles` all 500'd. | `app/helpers/application_helper.rb` |
| `edit_address` authorizes before redirecting | Redirect-then-`authorize` meant a non-owner got redirect → NotAuthorized → second redirect = `AbstractController::DoubleRenderError`. | `app/controllers/users_controller.rb` |
| `email_updates` rescues redirect and `skip_authorization` | An expired email-change link 500'd: `#verify` set a flash but never redirected and has no template (`MissingExactTemplate`), and `find_by!` raises before `authorize`, so Pundit's `verify_authorized` fired too. | `app/controllers/users/email_updates_controller.rb` |
| `SponsorPolicy#record_event` guards class-vs-instance | `index?` authorizes the Sponsor **class**, which has no `#event`; `record.event` raised NoMethodError so any non-admin got a 500 instead of a denial. | `app/policies/sponsor_policy.rb` |
| Added `SponsorsController#new` | The action did not exist though the route and the index's "New Sponsor" link did, so Rails rendered the view with `@sponsor` nil → 500 for everyone, admins included. | `app/controllers/sponsors_controller.rb` |
| `wise_transfers` added to disabled modules | Wise is outbound international transfer — the same category as `wires`, and the only member of it missing, so Fuime could still originate one. It also 500'd on a live Wise API call rather than being refused. | `app/controllers/concerns/fuime/disabled_modules.rb` |
| Storefront attribution says "HCB by Hack Club" | The brand sweep replaced "HCB" inside the attribution itself, leaving the public-facing "Fuime is forked from Fuime by Hack Club" — nonsense, and it stopped the attribution naming what it attributes (Rule 7). | `app/views/fuime/storefronts/show.html.erb` |

Regression specs: `spec/controllers/fuime/crash_regressions_spec.rb` (new) and
two admin/auditor cases in `spec/controllers/fuime/guardianship_enforcement_spec.rb`.
Each was confirmed to fail before its fix.

**Not fixed, deliberately** — these 500 only when requested with no params,
which no view does (`/receipts/link_modal`, `/:id/comments/new`,
`/admin_task_size`); or they are island-mode artifacts with no credentials
configured (`/discord/unlink_user`), or a deliberate test endpoint (`/timeout`).

**Measurement trap:** `bin/dev` runs Rails under foreman with the JS/CSS
watchers. Under sustained crawling the CSS watcher OOMs
(`Reached heap limit`), foreman SIGTERMs the whole group, and Rails dies with
it — 244 of 314 URLs then return connection-refused, which looks like a mass
regression. Crawl against `bundle exec rails server` with prebuilt assets. A
killed foreman also leaves a stale `tmp/pids/server.pid` that blocks the next boot.

## Security keys, take three: a nil RP ID and an unreachable 2FA toggle (2026-08-02)

Reported as "security keys aint working", from behind the red "Admin users are
required to enable two-factor authentication" banner. Two independent bugs, both
invisible to the suite.

**1. The RP ID was `nil` in production, so every key failed.**
`webauthn-ruby` only infers the Relying Party ID from the origin when *exactly
one* origin is allowed — `AuthenticatorResponse#rp_id_from_origin` returns `nil`
for a list of two or more. The previous fix (`6161f48ef`) listed both the custom
domain and `RENDER_EXTERNAL_HOSTNAME`, hoping keys registered on the Render URL
would survive the move to a custom domain. They can't: the RP ID is baked into
the credential at registration. Listing both made the inferred RP ID `nil`,
`valid_rp_id?` returned false, and every registration *and* sign-in raised
`WebAuthn::RpIdVerificationError`. The test environment only ever has one origin
— precisely the case where inference works — so nothing caught it.

**2. The 2FA toggle was inside a card that Fuime never renders.**
`use_two_factor_authentication`'s only control lived in the SMS/"Login
preferences" card, which `6161f48ef` gated behind `phone_verification_available?`
— false for Fuime, which has no Twilio and isn't getting any. So the banner
pointed admins at a page with no way to enable 2FA, and `admins_cannot_disable_2fa`
kept nagging no matter how many keys they registered. Registering a key worked;
it just never became a second factor and was never demanded at login
(`Login#required_authentication_factors_count` reads the flag, not the keys).

| Change | Why | Files |
|--------|-----|-------|
| Set `config.rp_id` explicitly from a single canonical origin | Removes the dependency on origin-count inference that broke every key. `CanonicalHost` already 301s every other hostname, so one origin is the design, not a limitation. RP IDs are bare domains, so the host is parsed out of the origin (`TEST_URL_HOST` carries `:3000`). | `config/initializers/webauthn.rb` |
| Moved the 2FA toggle into its own "Two-factor authentication" card | A security key or TOTP is a second factor on its own; the toggle has no business depending on Twilio. Shows explanatory copy until a factor exists, since the validation would reject the change anyway. | `app/views/users/edit_security.html.erb` |
| Added `User#second_factor_available?` | The view needs the same rule `second_factor_present_for_2fa` enforces; the validation now calls it instead of duplicating the condition. | `app/models/user.rb` |
| Left the SMS card gated, minus the 2FA toggle | Rule 2 — Twilio stays disabled, not deleted. It renders again if credentials ever appear. | `app/views/users/edit_security.html.erb` |
| Fixed three stale rebrand assertions | `logins_controller_spec` still asserted "Sign in to HCB", "signed into HCB", and "Your HCB account has been locked" against copy Milestone 3 already changed. Sanctioned by Milestone 3's verification step. | `spec/controllers/logins_controller_spec.rb` |

New specs, each verified to fail against the old code:
`spec/config/webauthn_configuration_spec.rb` (5, three of which fail with the old
initializer — one reproducing `WebAuthn::RpIdVerificationError` directly),
`UsersController#edit_security` (2, both fail against the old view), and two
`User#use_two_factor_authentication` cases covering enabling 2FA with only a
security key and with only TOTP.

157 examples across `spec/config`, `webauthn_credentials_controller`,
`logins_controller`, `sudo_mode_handler`, `users_controller`,
`process_login_service`, `user`, and `login` specs: 0 failures.

**Not verified:** a physical key against the deployed app. The fake client covers
the protocol, not the hardware. **Consequence of the RP ID fix:** any key
registered on the deployed app before this change was stored under a `nil`-RP-ID
verification path or a different host and must be re-registered.

## Playground org seed: a funded sandbox to demo (2026-08-02)

Playground Mode itself is **upstream**, not new: it is HCB's `Event#demo_mode`
boolean, renamed in the UI to "Playground Mode" in 2022 with the column left
alone (which is also our Rule 6 position — do not rename it). It is per-org, not
a global app mode: the ledger, balances, receipts and comments render normally
while everything that touches money is refused (account numbers, disbursements,
invoices, check deposits, reimbursements, card actions), and demo orgs are
excluded from `Event.indexable`. Turning it off is what stamps `activated_at`.

| Change | Why | Files |
|--------|-----|-------|
| Added `script/seed_playground_org.rb` | There was no Fuime playground org and nothing in the app had a believable balance — `devhacks` (HCB's demo seed) is empty, and the two HCB seed orgs holding money are nonprofit-flavoured with $7M in them. Creates `fuime-playground`, demo_mode on, owned by the same demo teen + guardian as `seed_demo_business.rb`, and funds it with 8 teen-scale ledger lines. | `script/seed_playground_org.rb` |

Money is fed in through the ledger's front door — `RawCsvTransactionService::Create`
→ `HashedTransactionService::RawCsvTransaction::Import` →
`CanonicalTransactionService::Import::All` → `CanonicalEventMapping` — the same
path `db/seeds.rb` uses, so no pipeline internals are touched (Rule 3).

Deliberately kept apart from `script/seed_demo_business.rb`: fake rows go in the
org that cannot move money, and `mayas-cookies` keeps its real test-mode Stripe
payment. Idempotent — it will not fund an org that already has mappings.

Two things that bite when writing seeds against this pipeline:

* `RawCsvTransactionService::Create`'s `amount:` is **monetized — dollars, not
  cents**. `db/seeds.rb` passes `8992898` and thereby books an $8.9M donation.
* Resolve each canonical transaction from its raw row
  (`raw.reload.canonical_transaction`), not via `CanonicalTransaction.last` as
  the seeds do — that only holds if nothing else imported in between.

Verified on the dev database: balance $417.88, available $373.46 (the gap is
HCB's 7% plan revenue fee, posted automatically by `FeeEngine` on mapping);
`/fuime-playground` and its ledger both 200 with the Playground Mode badge, all
8 memos render in the `transactions_list` frame, and the transaction detail page
opens. A second run added nothing.

**Worth a decision, not fixed here:** a real sale is charged twice — Fuime's 4%
platform fee line from the webhook handler *and* HCB's 7% plan revenue fee from
`FeeEngine` (visible on `mayas-cookies`: a $45 payment leaves $41.85 available).


## v4 card-grant activation issued cards to unverified phone numbers (2026-08-02)

| Change | Why | Files |
|--------|-----|-------|
| `Api::V4::CardGrantsController#activate` checks the grantee's `phone_number_verified?` | Activation issues a real Stripe card to the grantee. Every sibling path enforces this — the HTML `CardGrantsController#activate`, `StripeCardsController#create`, and `Api::V4::StripeCardsController#create` — but the v4 grant activation called `create_stripe_card` directly with no check. Upstream inconsistency; Fuime is where it matters, because the people being issued cards here are minors. | `app/controllers/api/v4/card_grants_controller.rb` |

Regression coverage: two examples in
`spec/controllers/api/v4/card_grants_controller_spec.rb` (`#activate`). The
refusal case was confirmed to fail with the guard stashed and pass with it.

**Who could actually reach it, precisely** — worth recording, because the first
reading was wider than the truth:

* A non-admin grantee cannot: `api/v4/card_grants` is in
  `Fuime::DisabledModules::DISABLED_CONTROLLER_PREFIXES` and activation is a
  POST. Upstream, with no such filter, any cardholder could.
* An admin holding an ordinary API token cannot either: `ApiAdminContext#admin?`
  additionally requires the token to carry the `admin:write` scope, so Pundit
  returns 403 before the action runs.
* An admin holding an `admin:write` token could — `CardGrantPolicy#activate?`
  admits any admin for any grant — and it is exactly the admin exemption in
  `DisabledModules` (`return if current_user&.admin?`) that lets the request
  through the module filter to begin with.

**Still open, needs a decision:** that admin exemption grants *only* write
access. Its comment says it exists "so support staff can still inspect
inherited records", but inspection is already covered one line below by
`safe_request_method?`, which lets everyone GET these pages. Its whole
practical effect is letting admins POST to modules Fuime states it must not
have — issue cards, originate ACH and wires, send checks, run disbursements.
Deleting that line would make the concern match its documented intent.

## Admins made by rake could never approve a transfer (2026-08-02)

Approving a transfer requires a `Governance::Admin::Transfer::Limit` row for the
approving admin; without one `GovernanceService::Admin::Transfer::Approval`
refuses with "…does not have an admin transfer limit configured". `db/seeds.rb`
grants one to the seeded user, **nothing else in the app creates one, and there
is no UI or route for it** (`rg "Transfer::Limit" app/controllers app/views
config/routes.rb` returns nothing). So every admin created by
`fuime:make_admin` — which is how all Fuime admins are made — hit a wall with
no way out of it from the browser.

| Change | Why | Files |
|--------|-----|-------|
| `fuime:make_admin` now ensures a transfer limit | The task's whole job is producing a working admin, and it was producing one that could not approve a disbursement. Existing limits are left alone. | `lib/tasks/fuime.rake` |
| Added `fuime:set_transfer_limit[email,dollars]` | The only way to set or raise a limit was a console session. Takes **dollars**, prints the before/after and the amount already used in the current window. | `lib/tasks/fuime.rake` |

The default is $10,000 per rolling 24h (`Limit::WINDOW_DURATION`), not something
enormous: the limit is a governance control, and defaulting it high would retire
the control rather than configure it. Raise it deliberately.

Verified against the dev database: the update path ($10,000,000 → $25,000 →
back), the create path on a fresh admin, and the "already configured, left
alone" path on an existing one. Both probe accounts were deleted and the seeded
admin's limit restored to its original 1,000,000,000 cents. Rubocop clean.

## Test-mode card issuing turned back on (2026-08-02)

Requested explicitly: "yes I wanna be able to generate cards (cause its all
test mode)". This reverses part of the brand-sweep disablement. Card issuing
stays out of scope for a real Phase 0 launch — custody, KYC and the
merchant-of-record structure all gate it — but Stripe Issuing in **test mode**
spends nothing, and the demo needs to show a card.

| Change | Why | Files |
|--------|-----|-------|
| `EventPolicy#card_overview?` restored to upstream (`show? && record.approved? && record.plan.cards_enabled?`) | It was a hardcoded `false`, written to be undone by reverting one method. Without this there is no nav item, no overview page and no Create-card button — for anyone, admins included. | `app/policies/event_policy.rb` |
| `stripe_cards` and `stripe_cardholders` removed from `DisabledModules` | That list blocks writes only. Re-enabling the page while leaving the POST blocked would have rebuilt the exact trap page the list was written to close: a Create button that 302s with "That feature isn't available on Fuime." | `app/controllers/concerns/fuime/disabled_modules.rb` |
| Added `fuime:verify_phone[email,phone]` | `StripeCardholderService::Create` refuses without a verified number, and Fuime cannot send one: the Twilio SMS_VERIFY credentials are placeholders. Gated on `StripeService.live?` rather than `Rails.env`, because this fork runs test-mode Stripe *in production* — a RAILS_ENV guard would refuse on the deployed demo, the one place it is needed. | `lib/tasks/fuime.rake` |
| "Order a card" trigger and its modal now gated on `policy(@event).new_stripe_card?` | The CTA was gated on bare membership (`organizer_signed_in?(as: :member)`), but `create_stripe_card?` also requires `is_not_demo_mode?` — so on a Playground Mode org a member saw a button whose action refuses, and the modal left a live POST target behind it. The trap page this codebase keeps having to close. | `app/views/events/card_overview.html.erb` |

Verified in-process as a manager of both orgs: on `mayas-cookies` the Cards
page, the Order-a-card trigger and the modal form all render; on
`fuime-playground` the page renders with **neither** trigger nor form.

`api/v4/stripe_cards` stays disabled. The UI is what was asked for, and the API
is a separate surface with its own reachability story.

Specs: the Cards case moved out of the `FUIME-DISABLED overview pages` group in
`spec/policies/event_policy_spec.rb` into its own group, which now pins the
three upstream conditions the stub had swallowed — allowed for a manager on an
approved cards-enabled org, denied when the plan disables cards (`Terminated`
is the only such plan), denied to an outsider on a *private* org. Not "denied
to a stranger": `show?` is satisfied by transparency, so on a public org an
outsider legitimately sees the card list upstream, and asserting otherwise
failed for the right reason.

**Two walls remain, neither of them code.** Issuing must be enabled on the
Stripe test account (the local `STRIPE__TEST__SECRET_KEY` is the literal
placeholder `sk...`; `Stripe::Account.retrieve` returns AuthenticationError),
and `create_stripe_card?` requires `is_not_demo_mode?` — so cards cannot be
issued on `fuime-playground` or any other Playground Mode org.

## Playground Mode does something again (2026-08-02)

Reported as "when i toggle playground mode on orgs nothing happens" — and that
was accurate. Upstream deleted the feature's entire visible half in
`73d010de6` ("Remove playground mode & mock data", #12240, Nov 2025), which is
in our history. It left `EventsHelper#show_mock_data?` as a stub returning
`false`, so every call site in the views was dead code, and put a small "Demo
Account" badge in the org nav in its place — which later upstream nav rewrites
then dropped. The result: `demo_mode` still gated features and still refused
things, but an organizer looking at the org saw nothing at all.

| Change | Why | Files |
|--------|-----|-------|
| `show_mock_data?`, `set_mock_data!`, `mock_data_session_key` restored | The stub is what made every mock-data branch in the views unreachable. Session-scoped per event, so two orgs can be viewed differently in one session and the org record never changes. | `app/helpers/events_helper.rb` |
| `before_action :set_mock_data` + the mock ledger in `transactions_list` | `?show_mock_data=true|false` drives the banner's toggle. Nothing is persisted — the real query is discarded for that request. | `app/controllers/events_controller.rb` |
| Playground Mode banner restored | The visible half. Without it, toggling the mode changes nothing an organizer can see. | `app/views/layouts/application.html.erb` |
| "Welcome to Playground Mode" callout restored, reworded | It is the `#playground-callout` anchor the banner links to. Upstream's copy invited teams to explore a fiscal-sponsorship dashboard. | `app/views/events/transactions.html.erb` |
| Mock descriptions rewritten for a teen business | Upstream's were a nonprofit's: "💰 Fiscal sponsorship fee", donations from strangers, club discos. The fee is now "Fuime platform fee (4%)", matching what `Fuime::PaymentWebhookHandler` actually posts. | `app/services/mock_transaction_engine_service/generate_mock_transaction.rb` |

The service itself survived the upstream deletion — only its callers were
removed — so the expensive half was already on disk.

**Three bugs the restore hit, each now a spec** in
`spec/controllers/fuime/playground_mock_data_spec.rb` (7 examples):

* **Arity.** The rows are `OpenStruct`s, and the transaction partial calls
  methods that take arguments — `memo(event:)`, `receipt_optional?`,
  `association(:receipts)`. An OpenStruct field is arity 0, so each was an
  `ArgumentError`/`NoMethodError` 500 in turn. They are singleton methods now.
* **A shared cache key.** `hcb_codes/memo/_memo` caches the rendered memo under
  `"#{event}/#{hcb_code.hcb_code}/cached_memo"` when `custom_memo` is nil. A mock
  row has no `hcb_code`, so every row collided on one key and the whole ledger
  rendered the *same* memo — cached for ten minutes, across requests. The mock
  sets `custom_memo`, which takes the uncached branch.
* **The lazy frame.** The rows live in `transactions_list`, not `transactions`,
  so the mock block has to be in that action or the page renders real rows.

Verified in-process: banner and callout appear on a Playground org and on no
other; the toggle flips "Show"/"Hide" and survives navigation; with it on the
ledger frame is 9 rows and 7 distinct mock memos with no real rows; with it off
the real seeded rows return; and a second organization is unaffected while the
first has mock data on.

**Noticed, not fixed:** the transaction *type* filter still offers "Fiscal
sponsorship fee" as an option — an HCB-model string in a Fuime UI, and a
`BRAND_STRINGS.md` item rather than part of this change.

## The Playground Mode toggle led nowhere (2026-08-02)

Reported one merge after #25: "when i click show mock data nothin happens".
Correct again, and this one was mine. The banner renders on **every** page of a
Playground org, but the mock ledger only renders on transactions — and the
button linked to `{ show_mock_data: ... }`, i.e. the page you are already on
(upstream's own markup). Clicking it from the org home, which is where everyone
starts, set the session flag and changed nothing visible.

| Change | Why | Files |
|--------|-----|-------|
| The toggle links to `event_transactions_path(..., show_mock_data:)` | So clicking it lands on the one page that renders a mock ledger, from wherever it was clicked. | `app/views/layouts/application.html.erb` |
| Balance falls back when `@mock_total` is nil | Only the action that builds the mock ledger sets it; every other page left it nil, and `render_money_amount(nil)` reads as $0.00. Mock data on the ledger should not make the org look broke everywhere else. | `app/views/events/home/_balance.html.erb` |

Reproduced before fixing, in-process: clicking from `/fuime-playground` gave
200 and zero mock rows. After: the href is
`/fuime-playground/transactions?show_mock_data=true` from the home page *and*
from `/cards`; following it lands 200 with 6 mock rows in the ledger frame; the
home balance still reads the real $417.88; the off switch returns 0 mock rows.

Four new examples in `spec/controllers/fuime/playground_mock_data_spec.rb`
(11 total). One measurement note for whoever probes this next: a fresh git
worktree has no `app/assets/builds`, which is gitignored — every page 500s on
`javascript_include_tag "bundle"` and it looks like the feature is broken.
Copy the builds directory in before believing a probe.

## The admin transfer limit was gating nothing (2026-08-02)

Found while unblocking disbursement approval on the deployed app. Approval is
guarded by `Governance::Admin::Transfer::Limit`, but the money was already
spendable before anyone approved anything, so the guard decided only a state
transition.

`DisbursementService::Create` fronts **at creation** — `i_cpt.update(fronted:
@fronted)`, with callers passing `@source_event.plan.front_disbursements_enabled?`
([disbursements_controller.rb:139](../../app/controllers/disbursements_controller.rb#L139),
`api/v4/disbursements_controller.rb:23`, `wires_controller.rb:84`). Every reader
of `fronted` is incoming-scoped (`Event#fronted_incoming_balance_v2_cents`,
`#fronted_fee_balance_v2_cents`), so that one line is what makes a destination
org's money spendable. Fronting it at creation meant a destination could spend
the full amount while the transfer still sat in `reviewing`.

Observed in production: `HCB-500-2`, $1,230,004.00 from "Hack Club NoEvent"
(id 999, `Internal` plan) to "Alpha School Santa Barbara" — `aasm_state:
reviewing`, never approved, and the destination showed **$1,229,914 available**
(the $1,230,004 fronted in, less a $90 pending out).

| Change | Why | Files |
|--------|-----|-------|
| Incoming disbursement is no longer fronted at creation (`fronted: false`, unconditionally) | Made the transfer-limit approval gate real: the destination cannot spend until an admin approves. `Disbursement#mark_approved` already fronts both pending transactions, so an approved transfer behaves exactly as before. | `app/services/disbursement_service/create.rb` |
| Two specs pinning the new behaviour | Non-admin request with `fronted: true` leaves the incoming CPT unfronted and the destination's `fronted_incoming_balance_v2_cents` at 0; `approve_by_admin` then fronts it and the balance appears. | `spec/services/disbursement_service/create_spec.rb` |

The outgoing side keeps upstream's behaviour. Nothing reads its `fronted` flag,
and the outgoing amount counts against the source event's balance either way.

The `fronted:` kwarg is now only consulted for the outgoing transaction, so the
plan feature `front_disbursements` is effectively inert. Left in place rather
than ripped out of three call sites: it is upstream's shape, and this keeps the
diff to one line in one file.

**Blast radius is narrower than it first looks.** Teen ventures are on the
`Standard` plan, which already excludes `front_disbursements`, so their outgoing
transfers were never pre-fronted. This only changed transfers *sourced from* the
`Internal` / `HackClubHQ` pseudo-orgs — i.e. admin funding of demo orgs.

Specs: `spec/services/disbursement_service/` 35 examples, 0 failures.

### Not fixed, deliberately: money-in never settles

Related and left alone. `Fuime::PaymentWebhookHandler` correctly books incoming
payments `fronted: false` — but nothing ever settles them. The only settlement
sources are Plaid, Stripe Issuing, CSV and Column
([transaction_engine/nightly.rb:14-17](../../app/services/transaction_engine/nightly.rb#L14-L17));
no importer turns a Fuime Stripe payment or payout into a `CanonicalTransaction`.
So `fronted: false` means *never spendable*, not "spendable at T+2". The single
real payment taken so far ($45.00 to Sunset Cookies) only shows as balance
because it predates that fix and was written `fronted: true`.

Building the settlement feed now was rejected: §1.5's Stripe Connect route would
delete it, since funds would land in the parent's connected account rather than a
Fuime-controlled pool. Decide the structure first.

Also unresolved, and now visible: approved disbursements can never reach
`deposited` on this deployment. `Disbursement::NightlyJob` is scheduled
([schedule.yml:61](../../config/schedule.yml#L61)) and posts a Column book
transfer for every `pending` disbursement, but production has
`COLUMN__PRODUCTION__API_KEY` missing and `ColumnService::Accounts::FS_MAIN` nil,
so every attempt fails. Harmless while balances are fronted; it is error noise
and it means the state machine dead-ends at `pending`.

## Phase 1: honest pre-launch posture (2026-08-02)

Goal for the day: make the deployed app safe to put in front of real teenagers
and real parents **without** resolving the money-transmission question, which is
weeks of legal work (LAUNCH_SPEC.md §1.1). That means no real money moves — and
the app has to say so, everywhere, without being asked.

Two classes of problem were closed. Both were live on the deployed service.

### 1. Fuime was pointing its own users at Hack Club

| Change | Why | Files |
|--------|-----|-------|
| `/privacy` no longer redirects to `hackclub.com/privacy-and-terms/` | Fuime was serving another organisation's privacy policy as its own. You cannot take a single real signup in that state — it is a misrepresentation, and the policy does not describe what Fuime collects. | `config/routes.rb`, `app/views/static_pages/privacy.html.erb` |
| `/faq` no longer redirects to `help.hcb.hackclub.com` | Same class of problem: Fuime's users being sent to HCB's help site for answers about Fuime. The new page also answers the question this phase creates — "does real money move?" — and answers it from `StripeService.live?`, so it cannot go stale. | `config/routes.rb`, `app/views/static_pages/faq.html.erb` |
| New `/terms` | None existed. | `app/views/static_pages/terms.html.erb` |
| New `/guardian-agreement` | The agreement text already existed and was already versioned, but was only reachable *inside* the signing flow — so a parent could only read it by first having an account and an invite. It is now public, and renders **the same versioned partial** the signing flow renders, so the published text cannot drift from the binding one. | `app/views/static_pages/guardian_agreement.html.erb`, `app/controllers/static_pages_controller.rb` |
| `security_reporting_email`: `hcb-security@hackclub.com` → `support@fuime.com` | `/security` told Fuime's users to report Fuime vulnerabilities to Hack Club's inbox: Fuime never hears them, and Hack Club fields reports for software it does not run. | `config/constants.yml` |
| `github_url`: `hackclub/hcb` → `agathonapp/fuime` | Rendered as the footer's "Open source" link and as the target for build-commit links, so it pointed at a repo containing none of Fuime's commits. AGPL-3.0 asks for the source of the *running* program. Attribution to HCB is separate and stays (footer text, README). | `config/constants.yml` |
| Legal links in the footer, and at the point of signup | Terms nobody is shown are not notice. The footer block they would naturally have joined (`.footer-extras`) is `invisible` until hover, so they got their own always-visible line; onboarding now states what continuing agrees to. | `app/views/application/_footer.html.erb`, `app/views/users/edit.html.erb` |

The legal pages are deliberately written to describe **what the app does
today**, hedged as beta terms, rather than adapted from a template describing a
product that does not exist. They are not a substitute for counsel-drafted
documents before real money — LAUNCH_SPEC.md §1.3 is unchanged — but "accurate
and plain" is a defensible pre-launch posture and "someone else's policy" was
not.

### 2. The app looked like it moved real money, and it does not

Stripe runs in test mode in production, deliberately (PRODUCTION_READINESS.md
§1.5). That is defensible only if it is stated. It was not: a storefront asked a
stranger for a card number, and the Cards page issued a real-looking card, with
nothing on either page saying the result is simulated.

| Change | Why | Files |
|--------|-----|-------|
| App-wide test-mode banner | The cheapest honest fix, and the only one a signed-out storefront visitor is guaranteed to see. Renders in both layout branches. Vanishes by itself on `STRIPE_MODE=live`. | `app/views/application/_banner_container.html.erb` |
| `FuimeHelper#show_test_mode_banner?` | The banner rule lives in a helper rather than inline in the partial **because it is suppressed in development and test** — a view spec could otherwise never exercise it. Now unit-tested in all four environments. | `app/helpers/fuime_helper.rb`, `app/helpers/application_helper.rb` |
| Storefront states that a real card will not be charged | This is a public URL a teenager hands to actual customers. A plain "Pay" button was a promise the page could not keep, and the person let down is the teen's customer, in front of the teen. The form still works — the beta and every demo need it — the button now reads "Try a test payment", and the post-payment confirmation says no real money changed hands. | `app/views/fuime/storefronts/show.html.erb` |
| Cards page states the cards are test cards | The app-wide banner says it too, but the page that issues the card is where it needs saying — otherwise a teen tries to buy something and is declined at a checkout. | `app/views/events/card_overview.html.erb` |

Every one of these reads `StripeService.live?`, so going live removes all of
them at once with no copy to hunt down. That was the design constraint.

### Operator actions (nothing below is code)

| # | Action | Consequence if skipped |
|---|--------|------------------------|
| 1 | Set `S3__BUCKET`, `S3__REGION`, `S3__ACCESS_KEY_ID`, `S3__SECRET_ACCESS_KEY` (and `S3__ENDPOINT` if not AWS) on **both** `fuime-web` and `fuime-worker` | `render.yaml` already sets `ACTIVE_STORAGE_SERVICE=amazon`, but with no credentials behind it. Until this is done, every uploaded receipt still dies on the next deploy — silently. |
| 2 | Set `APPSIGNAL_PUSH_API_KEY` on both services, then add alerts on 500-rate and Sidekiq failures | Newly added to `render.yaml` as `sync: false`. Without it you learn about outages from a user's email; a key with no alert attached is still nobody watching. |
| 3 | Stand up a real `support@fuime.com` inbox | Every legal page now routes deletion, export, and consent-withdrawal requests there. These are COPPA obligations with a clock on them. |

### Verification

`spec/controllers spec/requests spec/policies spec/helpers`, assets built on both
sides, baseline measured in a clean worktree at `HEAD`:

| Tree | Result |
|---|---|
| `HEAD` (clean worktree, baseline) | 450 examples, **22 failures**, 14 pending |
| `HEAD` + this work | 474 examples, **22 failures**, 14 pending |

The +24 examples are exactly the 24 added here. Failure **lists** were diffed,
not just counts — an earlier session was burned by comparing counts alone (see
`known-failures.md`) — and the two lists are **identical**: no new failures, and
none of the 22 touches a surface this work changed. The 24 new specs, all green:

- `spec/requests/fuime/legal_pages_spec.rb` (12) — reachable without an account
  (a parent reading the agreement before accepting an invite has no account), no
  lingering Hack Club redirect, the published agreement is the versioned one and
  not the fallback, and all four pages stay indexable.
- `spec/helpers/fuime_helper_spec.rb` (5) — the banner rule across four
  environments, including that it disappears when Stripe goes live.
- `spec/controllers/fuime/storefronts_controller_spec.rb` (4 added) —
  test-mode and live-mode copy.
- `spec/controllers/fuime/onboarding_terms_spec.rb` (3) — **no spec anywhere
  rendered `users/edit`**, so a typo'd path helper in the new notice would have
  500'd the signup page behind a green suite. Note the fixture needs
  `full_name: nil`: `User#onboarding?` is `full_name_in_database.blank?`, and a
  populated user renders the settings branch instead.

Rubocop clean on all changed Ruby. `erb_lint` reports one `Layout/HashAlignment`
in `fuime/storefronts/show.html.erb`; it is **pre-existing** — verified by
linting the file at `HEAD`, where the same offence sits at line 84 before this
work shifted it to 106.

## Organization plans: Fuime's lineup, HCB's retired (2026-08-02)

### What was wrong

The "Available plans" panel in an organization's admin settings — and every plan
`<select>` behind it — listed all 18 `Event::Plan` subclasses. Fifteen of them
describe Hack Club programs Fuime does not run:

- **Hack Club's grant programs**: `Argosy2024`, `Argosy2025`, `Argosy2026`,
  `ArgosyFtcSim2025`, `ScGoogleGrant`, `HighSchoolHackathon` (a 2024 hackathon
  fee waiver, already marked DEPRECATED upstream).
- **Hack Club's own organizations**: `HackClubAffiliate`, `HackClubHQ`,
  `SalaryAccount` (HCB living-expense reimbursement).
- **HCB's fiscal-sponsorship fee ladder**: `Standard` at 7% plus `FivePercent`,
  `ThreePointFive`, `TwoPointNinePercent`, `TenPercent`, `FeeWaived` — labelled
  "full fiscal sponsorship (7.0%)" and so on. Fuime is not a fiscal sponsor and
  its fee is **4%** (`docs/fuime/LAUNCH_SPEC.md`).

Two strings had also been mangled by an earlier brand sweep into claims Fuime
would be making about itself: `HighSchoolHackathon` offering to waive "Fuime
fees" for high school hackathons, and `Internal` describing "the internal
workings of Fuime" in a 👻 joke inherited from HCB — visible to any admin.

An admin picking one of these got real behavior: `Argosy2025` forces the org
public and blocks incoming money; `HackClubAffiliate` grants every restricted
feature and sets a 35¢ mileage rate; `SalaryAccount` disables receipt
requirements. Wrong fee, wrong features, wrong story.

### What changed

`Event::Plan.selectable?` (class method, default `true`, inherited by
subclasses) splits the plans Fuime offers from the ones kept only so existing
rows resolve. Per **Rule 2 — disable, don't delete** — no class was removed and
no `event_plans` row was migrated; the 12 retired plans just declare
`selectable? => false`.

Fuime's lineup, all six reachable from the pickers:

| Plan | Fee | Purpose |
|---|---|---|
| `Standard` | 4.0% | Default for a venture: money in, cards, receipts, reimbursements |
| `Founders` **(new)** | 0.0% | Fee waived for early / hand-onboarded ventures |
| `SpendOnly` | 0.0% | Incoming money blocked |
| `CardsOnly` | — | Cards only, can't raise |
| `Terminated` | — | Frozen and hidden (operational state) |
| `Internal` | 0.0% | Ledger's own clearing and fee accounts (operational state) |

`Founders` is new because upstream's bare `FeeWaived` had no `label` of its own
and so rendered as an unexplained "full fiscal sponsorship (0.0%)". `FeeWaived`
stays as the base tier — `HackClubAffiliate` and friends still inherit from it —
but is no longer offered directly.

`Event::Plan.select_options(current)` builds the `<select>` pairs. It takes the
org's current plan and **re-adds it if retired**: without that, an admin opening
settings for an org on a legacy plan would see a select whose `selected:` value
matched no option, and saving any unrelated field on that form would silently
move the org onto whichever plan the browser defaulted to. The admin *filter* in
`admin/_events_filter` deliberately still lists every plan — it is how you find
the orgs sitting on a retired one.

`FALLBACK_REVENUE_FEE` went 0.07 → 0.04, and `Standard#revenue_fee` now reads it
rather than hardcoding a second copy. This is the fee `Event#revenue_fee` falls
back to when an org has no plan at all, so leaving it at 7% would have
overcharged exactly the orgs already in a broken state.

### Files touched

- `app/models/event/plan.rb` — `FALLBACK_REVENUE_FEE`, `selectable?`,
  `selectable_plans`, `legacy_plans`, `selectable_plans_by_popularity`,
  `select_options`
- `app/models/event/plan/founders.rb` — new
- `app/models/event/plan/standard.rb` — 4% fee, Fuime label and description
- `app/models/event/plan/internal.rb` — selectable, description rewritten
- `app/models/event/plan/{spend_only,cards_only}.rb` — descriptions
- 12 legacy plans — `selectable? => false` plus a one-line reason each
- `app/views/events/settings/_admin.html.erb` — panel lists the lineup and
  names the retired plans separately; both pickers use `select_options`
- `app/views/admin/event_new.html.erb`,
  `app/views/events/activation_flow.html.erb` — `select_options`
- `app/views/admin/_events_filter.html.erb` — comment only, behavior unchanged
- `spec/models/event/plan_spec.rb` — 13 added

### Retired plans keep their own label

`Standard#label` became "Fuime standard (4.0%)", and the retired fee tiers
inherit it — so `TenPercent` began rendering as "Fuime standard (10.0%)" in the
admin filter, advertising a rate Fuime does not offer. `FeeWaived`,
`FivePercent`, `TenPercent`, `ThreePointFive` and `TwoPointNinePercent` now
declare `"legacy HCB fiscal sponsorship (#{revenue_fee_label})"`. Safe to add on
`FeeWaived` specifically because all six of its subclasses already override
`label`.

### Verification

Full suite, both sides, parallel, separate databases — see
`docs/fuime/known-failures.md` for the procedure and the caveat.

| Tree | Examples | Failures |
|---|---|---|
| Plan changes reverted (baseline) | 2152 | **64** |
| Plan changes applied | 2162 | **64** |

Failure lists **byte-identical** via `comm` in both directions; the +10 examples
are the 10 added to `plan_spec`. None of the 64 is a plan, fee, disbursement,
storefront, legal-page or helper spec. Rubocop clean on all 22 plan files;
erb_lint clean on the 4 views.

`plan_spec` calls `Rails.application.eager_load!` because `available_plans` is
`descendants` and `config.eager_load` is `ENV["CI"].present?` in test — without
it, every assertion about the *set* of plans silently depends on what an earlier
spec happened to reference.

### Not done

Fee percentages are the only money-model change here. Fiscal-sponsorship copy
survives elsewhere — `app/helpers/marketing_helper.rb` FAQ answers,
`static_pages/branding.html.erb`, `events/termination.pdf.erb`,
`disbursements/_form` ("Charge fiscal sponsorship fee?"), and
`static_pages/faq.html.erb` — none of it plan-driven, all of it still claiming
501(c)(3) sponsorship. Separate pass.

`HackClubAffiliate#contract_skip_prefills` maps DocuSeal field names and reads
`"Fuime" => ["Fuime ID"]` after the brand sweep renamed what were HCB template
field names. Left alone: those names must match a template, the plan is retired,
and `contract_docuseal_template_id` is unset by default anyway.

### Storage made provider-agnostic (2026-08-02)

Asked: "doesn't Render have its own storage? I don't want to use S3."

Render does have persistent disks, and they **cannot** serve Fuime. Per Render's
docs a disk is "accessible by only a single service instance" and "You can't
access a service's disk from any other service"; attaching one also forbids
scaling past one instance and rules out zero-downtime deploys. Fuime runs two
services and `fuime-worker` demonstrably reads uploaded bytes —
`Receipt::SuggestPairingsJob` OCRs receipts through RTesseract/MiniMagick,
`ProcessColumnCheckDepositJob` calls `check_deposit.front.open`, and Active
Storage's own `AnalyzeJob` downloads every new blob. A disk on `fuime-web` is
invisible to all of it, so receipt OCR and pairing would fail silently while the
upload appeared to succeed.

The real ask — *not AWS* — costs nothing, because Rails' S3 service speaks the
S3 **protocol**, not AWS specifically.

| Change | Why | Files |
|--------|-----|-------|
| `amazon:` block takes an optional `S3__ENDPOINT` + `force_path_style` | Points Active Storage at Cloudflare R2, Backblaze B2, or MinIO with no code change. Emitted by ERB **only when set**, because `endpoint: nil` is not the same as omitting the key. | `config/storage.yml` |
| `S3__ENDPOINT` added to both services | Optional; unset means AWS. | `render.yaml` |
| §3.2 retitled "Object storage", records the disk constraint | It read "AWS S3 — REQUIRED", which is what prompted the question. | `docs/fuime/LAUNCH_SPEC.md` |

**Recommendation: Cloudflare R2** — S3-compatible, no egress fees, and cheaper
than S3 for records held seven years. `S3__REGION=auto`,
`S3__ENDPOINT=https://<account-id>.r2.cloudflarestorage.com`.

Verified in-container both ways: with `S3__ENDPOINT` unset the resolved config
has no `endpoint` key at all; with it set to an R2 host,
`ActiveStorage::Service.configure` builds an `S3Service` whose client reports
that endpoint and `force_path_style: true`. The service name stays `amazon` —
renaming it would be a migration of every deployment's env for no gain.

---

## 2026-08-03 — P0: say only what is true (legal review remediation)

Branch `fuime/p0-honest-posture`. Prompted by `docs/fuime/LEGAL_RESEARCH.md`, a
seven-workstream primary-source review of whether Fuime can operate at all in
the U.S. Its two structural findings are recorded in `CLAUDE.md` as constraints
L1–L8; this entry covers only the copy and disclosure work, which needed no
counsel and no architecture change.

The review's finding that mattered most for this pass is narrow and cheap to
fix: **Fuime was describing a product it does not have.** Three separate
surfaces asserted capabilities and relationships that do not exist in the
codebase. None of that requires a lawyer to correct — it requires saying less.

| Change | Why | Files |
|--------|-----|-------|
| Guardian invite no longer promises the parent will "verify their identity" | Fuime performs no identity verification. `Guardianship#accept!` records a checkbox, timestamp, IP and user agent — the Guardian Agreement §6 says so in writing, and the storefront badge was already downgraded to "Guardian on account" for this reason. The promise was the defect, not the missing feature. Now names what accepting actually is, and links the agreement. | `app/views/guardianships/new.html.erb` |
| Standing status disclosure added to the app footer | Fuime shows balances, a ledger and cards — the presentation that invites an assumption of a bank and deposit insurance. 12 CFR 328.102(b)(3)(ii) (binds non-banks since 2025-01-01, untouched by the 2025–26 amendments, which reached Subpart A signage only) makes the *omission* of information needed to prevent that assumption the violation. Stated unconditionally, and in the always-visible block rather than `.footer-extras`, for the same reason the legal links are. | `app/views/application/_footer.html.erb` |
| Disclosure duplicated into the public storefront | The storefront renders through the no-nav layout branch, which never renders `application/_footer`. It is also the one page where a stranger is asked for a card number, so it is where an unrebutted assumption costs most. A refactor that unifies the layouts should delete the duplicate. | `app/views/fuime/storefronts/show.html.erb` |
| "business account" → "venture" across guardian, onboarding and mailer copy | "Your business account" asserts the minor holds a deposit-style account; no bank account exists, and under the intended architecture the account is the guardian's. The phrasing also inverted ownership — "their account, with you on it" misdescribes who carries the obligations. The guardian is the signer and responsible adult; the minor operates. | `app/views/guardianship_mailer/{invite,accepted}.html.erb`, `app/views/user_mailer/onboarded.html.erb`, `app/views/event/applications/_begin.html.erb`, `app/views/guardianships/show.html.erb`, `app/controllers/concerns/fuime/guardianship_enforcement.rb` |
| FAQ no longer says an under-18 "cannot sign a contract on your own" | Not what the law says. A minor *can* sign; the contract is voidable at the **minor's** option (infancy doctrine — Cal. Fam. Code §§ 6700/6710, and *Doe v. Epic Games*, 435 F. Supp. 3d 1024 (N.D. Cal. 2020), where a minor's disaffirmance defeated an arbitration clause). That asymmetry is the entire reason the guardian structure exists, so the answer now teaches it instead of flattening it into a false absolute. | `app/views/static_pages/faq.html.erb` |
| Marketing spec pins bank-partner and insurance claims separately | `spec/requests/marketing_spec.rb` already pinned the disabled funders pages against the 501(c)(3)/EIN claims. It did not pin the *banking* claims in the same copy ("held at Fuime's banking partners, Column N.A. and The Business Bank, and are FDIC-insured through the IntraFi network"), which are the class the FDIC polices directly. Re-enabling those pages now trips on both. | `spec/requests/marketing_spec.rb` |
| New spec pins the status disclosure itself | The failure mode is silent: nobody notices a missing footer paragraph until it is quoted back at them. Asserts the load-bearing clauses (not the full paragraph, which will be edited) on `/faq`, `/terms` and a public storefront, plus the inverse — that the storefront makes no affirmative insurance claim. | `spec/requests/fuime/status_disclosure_spec.rb` (new) |

**Not changed, deliberately.** The disabled `/for/funders` marketing surface and
the fiscal-sponsorship / verification letters keep their FDIC and 501(c)(3) copy
in the tree. Both are unreachable *and* pinned by specs that go red on
re-enabling (`marketing_spec.rb`, `documents_letters_spec.rb`), which is two
locks rather than one; deleting ~1,600 lines of upstream marketing would also
cost the ability to diff against `hackclub/hcb`. CLAUDE.md Rule 2.

**Verification.** rspec could not be run: `bundle exec rspec` reports the
executable missing and the Docker daemon is down, so the container path in
`known-failures.md` was unavailable too. This is the same toolchain gap that
file already documents. Substituted for it:
`ruby -c` on every changed `.rb` (all pass); a grep sweep of `app/views`,
`app/mailers` and the Fuime helpers for `banking|neobank|checking|savings|FDIC`,
whose only remaining hits are the intended disclaimers, factual statements about
*Stripe's* partners, and the two disabled-and-pinned surfaces above. ERB was
**not** verified by `ruby -rerb` — stdlib ERB rejects the multi-line `<%# %>`
comments this codebase uses throughout, and an unedited file from `HEAD` fails
the same check, so that signal is noise. Rails uses Erubi. **The new and
amended specs have not been executed; run them in Docker before merging.**

### Same pass — the marketing site and the brief it was built from

`site/` is a separate Node service on `fuime.com` (the Rails app is on
`app.fuime.com`), and it described a **materially different product** from the
one the code implements: Stripe Connect and "we never hold your money" (no
Connect code exists), a parent ID check with "Stripe holds your ID, not fuime"
(no verification of any kind exists), and 7% + $15/mo (the app charges 4%, no
monthly fee). This was the largest single divergence in the repo.

| Change | Why | Files |
|--------|-----|-------|
| Connect / no-custody architecture restated as roadmap, not fact | It is the committed plan (CLAUDE.md L1) but is not built. Pages now say what happens today — private beta, Stripe test mode, no real money — and label the target architecture as future. | `site/index.html`, `site/parents.html`, `site/pricing.html` |
| ID-check claims removed | "One ID check at signup. That is the whole ask." and a whole card headed "Stripe holds your ID, not fuime" described a KYC flow that does not exist. Replaced with what acceptance actually is. | `site/parents.html` |
| Pricing aligned to the plan lineup, with Stripe's cut disclosed | Starter $0 / Standard 7% / Pro ~$15/mo + 4% / Founders 0%, and Stripe's ~2.9% + 30¢ named wherever a fee appears. A headline rate that hides the processing fee is the hidden-fee pattern the FTC pleaded against Dave Inc. (2024). Subscriptions bill the guardian — a minor's payment authorisation is voidable, the guardian's is not. | `site/pricing.html`, `site/index.html`, `site/style.css` |
| **`site/docs/BRIEF.md` rewritten — the root cause** | The brief is the file "every worker on this site reads first… It is the contract", and it asserted the target architecture in the present tense. The site was built faithfully *from* it, which is how the false claims got there. Fixing only the HTML would have let the next contributor regenerate them. It now separates **Shipped today** from **Roadmap, and must be labelled as such**, and carries the pricing and ownership rules. | `site/docs/BRIEF.md` |

**Verification.** Grep sweep over `site/` and `app/` for `one ID check`,
`Stripe holds your ID`, `government ID you upload`, `7% of collections`,
`verify their identity`, and present-tense `never hold your money` returns no
false claims; the only survivors are the new pricing copy and explicitly
labelled roadmap statements. The status disclosure now appears on
`site/{index,parents,pricing}.html`, the app footer, and the storefront. The
site is static HTML with no build step or test suite.

#### Known gap this pass created, deliberately left open

Aligning the site to the agreed pricing lineup (Starter / Standard 7% / Pro
$15/mo + 4% / Founders 0%) moved the site **ahead of the app**, which is the same
class of divergence this pass existed to close — just pointing the other way.
The app today ships `Event::Plan::Standard` at **4%**
(`Event::Plan::FALLBACK_REVENUE_FEE = 0.04`), a `Founders` plan at 0%, and has
**no Starter or Pro class at all**; `Fuime::PaymentLinkService::FUIME_PLATFORM_FEE_PERCENT`
is likewise `4`.

Why it was not fixed here: that constant is stamped into Stripe metadata, posted
as its own negative ledger line, and read back by the proportional
refund/chargeback reversal logic (`PaymentWebhookHandler#refund_platform_fee`).
Three interacting money paths, and **the test suite could not be run this
session** (see the verification note above). Changing fee arithmetic with no way
to execute a spec is not a trade worth making for copy parity.

Why it is survivable in the meantime: the site states "nothing is billed during
the private beta" in its metadata, its hero chip and its pricing FAQ, and the app
bills nobody — Stripe runs in test mode. The published lineup is therefore a
forward price list for a product that is not charging, not a
misdescription of what anyone is paying.

**Top P1 item, before anyone is billed:** move the plan lineup to the published
tiers — `app/models/event/plan.rb` (`FALLBACK_REVENUE_FEE`),
`app/models/event/plan/standard.rb`, new `Starter` and `Pro` classes,
`app/services/fuime/payment_link_service.rb` (`FUIME_PLATFORM_FEE_PERCENT`) —
with specs, in a container where rspec runs. Preserve the existing rule that a
retired plan stays selectable for an org already on it, so nothing silently
migrates. Subscription billing must charge the guardian, never the minor.

---

## 2026-08-03 — Guardian oversight: implementing a promise the agreement already made

Same branch. This is platform work, not copy: §3 of the guardian agreement
("You can see everything") tells the signing adult they will have visibility
into the minor's "transactions, balances, and the people on their team" and that
it **"cannot be turned off by the minor"** — and nothing implemented it.
`guardianships_as_guardian` was rendered in exactly one template, the *admin*
user page. A guardian's only authenticated surfaces were the invite, the
agreement record, revoke and resend. `EventPolicy#reader?` carried a comment
saying "a guardian needs to see the ledger they are responsible for", but it
resolved solely through `OrganizerPosition`, and accepting a guardianship creates
none — so the predicate was false for every guardian who ever signed.

### The design decision CLAUDE.md Milestone 4 asked to have recorded

Milestone 4 left this open: "Implement as a new OrganizerPosition role if the map
shows that's clean; otherwise a parallel association."

**Chosen: derive guardian read access from the `Guardianship` record, not from an
OrganizerPosition granted at acceptance.** The deciding clause is "cannot be
turned off by the minor". An organizer position is org membership, and the minor
is a *manager* of their own venture (the column defaults to `role: 100`,
manager) — so they could delete the row and switch off the single guarantee their
parent was asked to rely on when they signed. Revoking a *guardianship* is
already correctly restricted to the guardian and admins
(`GuardianshipPolicy#revoke?` excludes the minor deliberately). Deriving the
access from the guardianship makes the promise structurally true rather than
true-by-convention. It also avoids listing a parent as a team member on the
venture's own team surfaces, which they are not.

| Change | Why | Files |
|--------|-----|-------|
| `Guardianship.overseeing_event(user, event)` scope | "Is this user entitled to oversee this venture?" — active guardianships held by the user over a minor with a live position on the event. Join is scoped to `deleted_at: nil` because positions are `acts_as_paranoid`, so a removed team member's guardian loses oversight along with them. | `app/models/guardianship.rb` |
| `User#guardian_of_event?`, `#active_wards`, `#overseen_events` | `wards` spans pending and revoked guardianships, which is not what any authorization decision wants; `active_wards` is the scoped version. | `app/models/user.rb` |
| `EventPolicy#reader?` also grants `guardian_reader?` | The mechanism the existing comment described but did not have. | `app/policies/event_policy.rb` |
| `GET /guardian` → `guardianships#index` + view | The guardian's overview: wards, their ventures, settled balances, links into the ledger — and, in the other direction, a teen's view of their own invite so chasing an unresponsive parent no longer requires keeping the email. `:index` on the existing resource rather than a new route, because `:show` is token-addressed and the two never collide. | `config/routes.rb`, `app/controllers/guardianships_controller.rb`, `app/views/guardianships/index.html.erb` |
| Nav entry, shown only to users with a guardianship either way | An adult running their own venture sees no stray parental furniture. | `app/views/application/_user_menu.html.erb` |

**Read-only by construction.** `member?` and `manager?` do not consult
`guardian_reader?`, so a guardian can see a venture and act on nothing in it —
oversight is not participation, and a guardian who wants to intervene revokes.
Verified by auditing all 27 `reader?` call sites in `EventPolicy`: every
reader-gated predicate is a view (`show?`, `team?`, `balance_by_date?`,
`reimbursements?`, …). The one that reads write-adjacent, `new_transfer?`, is the
*form*; the write is `create_transfer?`, which requires `admin_or_manager?` — and
`disbursements` writes are independently blocked by `Fuime::DisabledModules`.
The guardianship-enforcement filter already exempts anyone who
`permitted_to_operate_business?`, so an adult guardian is not bounced, while a
not-yet-onboarded stub guardian can still reach `/guardian` because
`guardianships` is on its allowlist.

Balances shown are `settled_balance_cents` only. Fuime posts incoming payments as
**unfronted** pending transactions (`fronted: false`), so a figure that counted
them would tell a parent money is available that their teen cannot spend.

**Verification.** Still no runnable suite (see the note above — no rspec
executable, Docker daemon down). `ruby -c` passes on all eight changed Ruby
files. Two new spec files were written and **have not been executed**:
`spec/policies/event_policy_guardian_spec.rb` (the §3 contract: active grants
read, pending does not, revocation takes effect immediately, an unrelated adult
gets nothing, and the two examples pinning that the minor cannot turn it off) and
`spec/controllers/guardianships_controller_index_spec.rb` (controller-spec style
with `SessionSupport` + `render_views`, matching this repo's convention for
authenticated coverage). **Run both before merging.**

---

## 2026-08-03 — Stripe Connect: ending the pooled-account model

Same branch. This is the change CLAUDE.md L1 exists to require. Money-in no longer
lands in Fuime's own Stripe balance; each venture gets a **connected account the
guardian owns**, Stripe holds and settles the funds, and Fuime takes its cut as a
platform fee. Fuime is out of the flow of funds, which is what removes the
money-transmission exposure (18 U.S.C. § 1960) and the Stripe ToS violation the
pooled model carried.

### The account configuration, and why every field is forced

```ruby
controller: {
  losses:                 { payments: "stripe" },
  fees:                   { payer: "account" },
  requirement_collection: "stripe",
  stripe_dashboard:       { type: "none" }
}
```

`losses.payments = stripe` is the choice; the rest follows from it. Stripe
documents `requirement_collection = application` as **incompatible** with
`losses.payments = stripe`, so choosing "Stripe eats negative balances" forces
"Stripe collects the KYC" — which is also a privacy win: the guardian's SSN and
identity documents go to Stripe and never enter Fuime's database.
`stripe_dashboard.type = none` keeps the guardian inside Fuime. This combination
is permitted and is Stripe's own recommended default for platforms new to
embedding payments.

**The unavoidable consequence, documented in the flow's copy rather than hidden:**
because requirement collection is Stripe's, onboarding must use embedded
components, and the guardian hits one Stripe-owned authentication popup inside the
otherwise-embedded form. The flag that would remove it
(`disable_stripe_user_authentication`) requires `requirement_collection =
application`, i.e. owning every chargeback. The trade is obviously right for a
pre-launch company serving minors, so the popup is accepted and the guardian is
warned about it in advance — a surprise Stripe window in a flow about a child's
money reads as a phishing attempt.

| Change | Why | Files |
|--------|-----|-------|
| `stripe_connected_accounts` table + `StripeConnectedAccount` | One per venture (`event_id` UNIQUE — that index *is* the anti-commingling guarantee; sharing an account across ventures would recombine the revenue this migration exists to separate). Mirrors Stripe's fields so "can this venture be paid?" is answerable without a network call on every storefront render. | `db/migrate/20260803120000_*`, `app/models/stripe_connected_account.rb` |
| **No AASM**, despite it being this repo's state-machine gem | Stripe owns this object's state: capabilities change because a verification cleared or a document expired *at Stripe*, not because Fuime transitioned anything. A local machine would give a second authoritative-looking answer that can silently disagree, and the failure modes are the worst available — telling a family they can take payments when they cannot, or refusing payments Stripe would have accepted. Fields are mirrored verbatim; `#status` is derived. | `app/models/stripe_connected_account.rb` |
| `ready_for_payments?` ignores `requirements.currently_due` | Stripe routinely leaves requirements on an account it is still happy to charge for — a grace period, not an outage. Gating on it would take a working venture's storefront down. Surfaced separately as `#requirements_outstanding?`. | same |
| Charging and paying out are separate predicates | A venture can legitimately collect before its bank details clear. Collapsing them produces the one failure a fifteen-year-old cannot debug: money arrives, then appears stuck. | same |
| `Fuime::ConnectOnboardingService` | Creates the account, mints Account Sessions, re-syncs. Local row written **before** the Stripe call so a crash leaves a visibly-incomplete row rather than a Stripe account Fuime has no record of (mirrors `StripeCardholderService::Create`). | `app/services/fuime/connect_onboarding_service.rb` |
| **Every Stripe call passes `api_key:` explicitly** | `config/initializers/stripe.rb` sets the global `Stripe.api_key` from `Rails.env.production? ? :live : :test`, which does **not** consult `StripeService.mode`. In production with `STRIPE_MODE=test` — the current, intended posture — the global key is the LIVE one. Creating a connected account under it would produce a real live Stripe account for a child's business while every screen says "test mode". | onboarding service, payment link service |
| Checkout is now a **direct charge** on the connected account | `stripe_account:` request option + `payment_intent_data[application_fee_amount]`. Direct charges put refunds and disputes on the venture's balance, which is the only charge type coherent with Stripe carrying negative-balance liability — destination charges route every chargeback through Fuime's balance first. | `app/services/fuime/payment_link_service.rb` |
| Platform fee now reads `event.plan.revenue_fee` | The hardcoded `FUIME_PLATFORM_FEE_PERCENT = 4` never consulted the plan, so a **Founders-plan venture whose entire promise is 0% was still being charged 4%**. The constant survives, derived from `Event::Plan::FALLBACK_REVENUE_FEE`, for prose that is not venture-scoped (FAQ, Terms) and as a webhook fallback. Zero fees omit the parameter entirely — Stripe rejects a zero application fee. | payment link service, `app/views/fuime/storefronts/show.html.erb` |
| `create_payment_link` deleted | Dead code (no callers in app, lib or specs) that built Product + Price + PaymentLink on Fuime's own account. Removed rather than migrated: the first person to reach for "we already have a payment-link helper" would silently reintroduce custody. A note marks where it was. | payment link service |
| Guardian onboarding flow: status / setup / return / refresh | `return` re-asks Stripe rather than trusting the exit — leaving the flow means only that it was entered and exited, and treating it as success is the classic Connect bug. `refresh` serves JSON to the component and HTML to a human. | `app/controllers/fuime/payment_setups_controller.rb`, `app/views/fuime/payment_setups/*`, `config/routes.rb` |
| `EventPolicy#setup_payments?` — the deliberate exception | This is the one place a guardian may *write*. Justified because the thing written is not the venture but the guardian's own Stripe account: Stripe requires the under-18 account's owner to be the adult, and onboarding collects that adult's DOB/address/SSN-last-4, which a teen cannot supply and must not be asked for. So the teen who runs the business is excluded from setup — the example most likely to look like a bug without the reasoning. | `app/policies/event_policy.rb` |
| Second, Connect-scoped webhook endpoint | Stripe scopes endpoints separately for the platform and for connected accounts, each with its own signing secret, so these cannot share the payment endpoint however similar the code looks. `account.updated` is the only signal that arrives when verification completes asynchronously — without it a guardian finishes onboarding, Stripe verifies ten minutes later, and the venture's storefront stays dark with nothing to point at. | `app/controllers/fuime/webhooks_controller.rb`, `app/services/fuime/connect_webhook_handler.rb`, `render.yaml` |
| Storefront and checkout now gate on `Event#accepts_payments?` | `is_public` defaults to **true**, so it never gated anything: every activated venture rendered a working payment form with nowhere for the money to go. | `app/controllers/fuime/checkouts_controller.rb`, storefront view |
| `@stripe/connect-js` added | `loadConnectAndInitialize` ships in this package; only `@stripe/stripe-js` was present. Installed (3.4.6), lockfile updated. | `package.json`, `yarn.lock`, `app/javascript/controllers/stripe_connect_onboarding_controller.js` |

### Bug fixed on the way past

`Fuime::StorefrontsController` computed its public "Guardian on account" badge
from `point_of_contact.has_active_guardian?` — but `point_of_contact` is the
**admin who activated the venture** (`Event::Application#activate_event!` passes
the acting admin), so the badge was publishing whether a *Fuime staff member* has
a parent. There was no query anywhere for "who is the responsible adult for this
venture"; there is now (`Event#overseeing_guardians` / `#has_overseeing_guardian?`),
returning a relation because a venture can legitimately have two — two co-founders
with different parents — and picking `.first` is how you assert something about the
wrong family.

### ⚠️ Product decision this forces, for a human not an engineer

**Choosing Stripe-liability means Fuime cannot use Stripe Issuing or Treasury.**
Stripe lists this among the consequences of `losses.payments = stripe`, alongside
"you can't pause payments or payouts for your connected accounts" and "you can't
directly debit connected account balances".

This collides with a decision made in this repo *yesterday*: `stripe_cards` and
`stripe_cardholders` were **removed from the disabled-modules list on 2026-08-02**
and the cards UI re-enabled. Issuing debit cards for ventures and pushing
negative-balance losses to Stripe are **mutually exclusive**. Fuime must pick:

* **Keep Stripe-liability** (this commit): no venture debit cards, ever, under this
  configuration. Suspension must be enforced in Fuime's own layer — refuse to
  create Checkout Sessions — because Stripe will not let the platform pause a
  connected account.
* **Keep the cards roadmap**: switch to `losses.payments = application`, and Fuime
  owns every chargeback and negative balance on every teenager's business.

Nobody should discover this after building card UI. Flagged here, in
`docs/fuime/LEGAL_RESEARCH.md`, and in the handoff note.

### Verification — read this before trusting any of it

Still no runnable suite (no rspec executable, Docker daemon down — same gap
`known-failures.md` documents). `ruby -c` passes on all changed Ruby; `yarn add`
succeeded. Beyond that:

* **Nothing here has been executed against Stripe, even in test mode.** No account
  has been created, no Account Session minted, no webhook received. The parameter
  shapes come from Stripe's current documentation, not from a successful call.
* **The Stripe gem is pinned to 11.7.0** (late 2024). `Stripe::AccountSession`
  is expected to exist in it but **was not verified** — the gems are not installed,
  so the class could not be introspected. If `AccountSession` is missing, upgrade
  the gem or fall back to Account Links (which would mean giving up the embedded
  flow and accepting a redirect). **Check this first.**
* Five new/changed spec files are **unexecuted**:
  `spec/models/stripe_connected_account_spec.rb`,
  `spec/policies/event_policy_payment_setup_spec.rb`,
  `spec/policies/event_policy_guardian_spec.rb`,
  `spec/controllers/guardianships_controller_index_spec.rb`,
  `spec/requests/fuime/status_disclosure_spec.rb`.
* The **ledger semantics are not reworked**. Under direct charges the gross payment
  lands in the family's Stripe balance and Fuime sees only its application fee, so
  `Fuime::PaymentWebhookHandler`'s `CanonicalPendingTransaction` is now a *mirror of
  someone else's balance* rather than a record of funds Fuime holds — which is what
  `docs/fuime/LEGAL_RESEARCH.md` concluded it should become, but the handler's
  `record_platform_fee` still posts its own fee line and is now redundant with
  `application_fee_amount`. Next session's work.

---

## 2026-08-04 — Ledger for Connect direct charges, and payouts to the family's bank

Completes the item the previous entry left open ("the ledger semantics are not
reworked … next session's work") and adds the money-out half of the no-custody
architecture.

### Resolved from the previous session's open questions

* **`Stripe::AccountSession` DOES exist in the pinned stripe 11.7.0.** So does
  `Stripe::Payout`, `Stripe::Balance` and `Stripe::ApplicationFee`. The embedded
  onboarding flow does not need to fall back to Account Links. Verified by
  introspecting the installed gem, not by reading docs.
* **The previously unexecuted spec files now run.** `bundle exec rspec` works via
  Docker (daemon was simply down; `docker compose up -d db redis` plus
  `rails db:migrate` on RAILS_ENV=test was all that was needed).

### Bug found and fixed: the whole Connect onboarding flow was 500ing

`EventPolicy#setup_payments?` and `#payment_setup_status?` were defined BELOW the
`private` keyword. Pundit resolves a query with `public_send`, and
`Fuime::PaymentSetupsController` both calls `authorize @event, :setup_payments?`
and reads `policy(@event).setup_payments?` directly — so every request to the
payment-setup flow raised `NoMethodError`. Moved above `private`, with a comment
saying why they must stay there. `spec/policies/event_policy_payouts_spec.rb` pins
the visibility of all five Fuime predicates so it cannot regress silently.

The previous session's own specs were reporting this; they had never been run.

### New: the ledger sees direct charges (files added)

* `app/services/fuime/venture_ledger.rb` — single owner of the ledger-posting
  primitive AND of the idempotency key scheme. The key scheme is deliberately
  SHARED with the pooled path: keys identify a Stripe object, not a delivery of
  one, so if a webhook endpoint is ever misconfigured to receive both platform and
  connected-account events, a payment delivered twice posts one ledger line rather
  than two. `Fuime::PaymentWebhookHandler` was refactored to delegate its key
  construction here (keys byte-identical, behaviour unchanged).
* `app/services/fuime/connect_payment_recorder.rb` — money in for direct charges.
  Three deliberate differences from the pooled handler:
  1. the venture is resolved from `event.account`, not from `fuime_event_id`
     metadata (Stripe's statement beats Fuime's own annotation);
  2. the fee is READ from `application_fee_amount` rather than computed from the
     plan, so a posted line can never disagree with what Stripe deducted, and a
     0%-plan venture gets no phantom fee line;
  3. **the fee rebate waits for `application_fee.refunded`.** Stripe does not
     return a platform's application fee when a charge is refunded unless the
     refund asked it to, so the pooled handler's proportional rebate-on-refund
     would print a credit into a family's ledger for money still in Fuime's
     account.
* `app/services/fuime/connect_payout_recorder.rb` — money out. Debits at
  `payout.created` (that is when Stripe moves the balance, not `payout.paid`),
  credits back on `payout.failed`/`canceled`, and only ever reverses a debit it
  actually posted.

### New: payouts (teen requests, guardian approves)

* `db/migrate/20260804120000_create_payout_requests.rb`, `app/models/payout_request.rb`,
  `app/services/fuime/payout_service.rb`, `app/controllers/fuime/payouts_controller.rb`,
  `app/views/fuime/payouts/index.html.erb`, four routes, one nav item.
* The approval gate is the ownership structure from L2 made operational, not a
  parental-controls feature: the guardian owns the account and the funds, so a
  minor cannot move money out of it alone. Enforced in THREE places —
  `EventPolicy#decide_payout?`, `Fuime::PayoutService#approve!`, and a
  `PayoutRequest` validation that the approver is an overseeing guardian.
* `Fuime::ConnectOnboardingService` now creates accounts with
  `settings.payouts.schedule.interval = manual`. Without it Stripe drains the
  balance on a timer and refuses platform-created payouts, which would make the
  approval gate theatre over money that was leaving anyway.
* `Fuime::TaxTrackerService::EXCLUDED_MEMO_PATTERNS` gains `"payout"`. A payout is
  the family moving already-earned money to their own bank — neither income nor a
  deductible expense. Counting it as an expense would UNDERSTATE a teen's taxable
  income, which is the harmful direction.

### Verification

`spec/services/fuime/ spec/models/{payout_request,stripe_connected_account,guardianship,user_guardianship}_spec.rb
spec/policies/ spec/controllers/fuime/ spec/requests/fuime/` — green except the
one pre-existing `comment_policy_spec` factory failure already recorded in
`known-failures.md` ("Company name is too long"). New coverage: 22 examples for
the Connect payment recorder, 19 for the payout recorder, 24 for PayoutRequest, 21
for PayoutService, 15 for the payout policy, 16 for the payouts controller.

### Still not done

* **Nothing here has touched a real Stripe account, even in test mode.** No
  connected account created, no payout sent, no webhook received from Stripe
  itself. Every payload shape in the specs is constructed by hand from Stripe's
  documentation. `settings.payouts.schedule.interval = manual` in particular is
  the claim most worth verifying against a live test-mode account, because
  platform control of the payout schedule interacts with
  `controller.losses.payments = stripe` and that combination was not confirmed.
* **Stripe's own processing fee is not posted to the ledger.** The venture's
  balance is gross minus Stripe's fee minus Fuime's fee, but only Fuime's fee gets
  a line, so the ledger currently overstates the balance by Stripe's cut. Needs
  the charge's `balance_transaction`.
* **No refund-creation path exists**, so whether a family gets Fuime's fee back on
  a refund is currently decided by nobody. When that path is built,
  `refund_application_fee` is the switch, and choosing not to pass it means Fuime
  keeps its cut on a sale the family had to unwind.
* Under-13 support (L6) is untouched: `User#minimum_age_requirement` still refuses
  under 13, and the COPPA program it would require does not exist.

### Addendum, same session — three more pre-existing bugs the specs were already reporting

Running the *tracked* Fuime specs (which the previous session's work had broken but
never executed) surfaced these. None were caused by the payout/ledger work above.

1. **The standing "not a bank" disclosure never rendered for signed-out visitors.**
   `app/views/layouts/application.html.erb` rendered `application/_footer` in the
   app-shell branch only, not in the signed-out branch — so `/faq`, `/terms`,
   `/privacy` and the guardian agreement showed no FDIC disclosure to anyone
   without an account. A parent reading the terms before accepting an emailed
   guardian invite is exactly that reader, and 12 CFR 328.102(b)(3)(ii) makes the
   OMISSION the violation. Footer now renders on both branches;
   `Fuime::StorefrontsController` opts out with `hide_footer` because it carries its
   own payer-facing copy and stating it twice reads as boilerplate.

2. **`Fuime::CheckoutsController` and the storefront specs were written for the
   pooled model.** Both now require a venture to have a Stripe account Stripe will
   charge on (`accepts_payments?`), which is correct, but nine tracked examples
   still assumed the old always-payable behaviour. Specs updated to create a ready
   connected account, and the refusal branch — previously covered by nothing — is
   now pinned in both files. Also fixed an assertion that expected `"4%"` when the
   view renders `number_to_percentage(precision: 1)` = `"4.0%"`; it now derives the
   expected string from `event.plan.revenue_fee` so a plan change cannot leave it
   passing against the wrong number.

3. **A seed-dependent flake in the storefront spec.** `include("Pay #{event.name}")`
   asserted against rendered HTML with a Faker-generated name, so any name
   containing `'` or `&` was escaped in the output and failed on some seeds only.
   The name is now pinned to one with no escapable characters.

**Suite state after all of the above:** `spec/services/fuime/ spec/models/{payout_request,
stripe_connected_account,guardianship,user_guardianship}_spec.rb spec/policies/
spec/controllers/fuime/ spec/requests/fuime/ spec/requests/marketing_spec.rb`
= **370 examples, 1 failure**, that one being the pre-existing `comment_policy_spec`
factory issue in `known-failures.md`. Was 16 failures when this session started
measuring, before any of the above was written.

---

## 2026-08-04 (later) — Card groundwork: create-time account profiles

Founder decision: pursue a **business-expense card** on Stripe Issuing with a
**mixed `losses.payments` fleet**, so only card-cohort families pay the cost.

### Why this shape, and what was explicitly NOT built

The original ask was to issue cards without disclosing to Stripe that a minor is
the spender. That was not built, and it is also unnecessary: per
`docs/fuime/LEGAL_RESEARCH.md`, Stripe's Issuing cardholder floor is **13**, and
Celtic Bank's Authorized User Terms carry **no minimum age at all**. The guardian
accepts the Accountholder Terms, the minor accepts the Authorized User Terms, and
the arrangement is disclosed and permitted.

What Celtic actually restricts is **what the card buys**, not who holds it:
"You may not use your card for personal, family or household purposes." So a
business-expense card (inventory, supplies, software) is compliant; a card the kid
spends earnings on is a consumer product on a different rail regardless of what
Stripe is told. Concealment would not have changed which of those two Fuime is
operating.

### What shipped

`controller` is **create-only** — Stripe's Account update endpoint accepts no
controller parameters — so the profile decision is permanent per account and a
venture can never be upgraded into card support. That makes the create-time
mechanism the prerequisite for any card work, and it is what this change is.

* `Fuime::ConnectOnboardingService::PROFILES` — two named configurations.
  `:payments_only` is today's Stripe-liable posture and remains the default.
  `:cards_enabled` moves `losses.payments`, `requirement_collection` and
  `fees.payer` to `application` and requests `card_issuing`. Each of those three is
  documented at the point of definition with what it costs: Fuime absorbing every
  negative balance, guardian SSNs landing in Fuime's systems, and Fuime paying
  ~2.9% + 30¢ (which a 4% platform fee does not cover).
* `db/migrate/20260804140000_*` — `controller_profile` (Fuime's intent, written
  BEFORE the Stripe call so a retry cannot silently fall back to the default) and
  `controller` (Stripe's actual config, mirrored).
* `StripeConnectedAccount#controller_matches_requested_profile?` and
  `#ready_for_cards?` — card-capability is derived from what STRIPE reports, never
  from Fuime's intent, because the mixed fleet is an inference and Stripe returning
  a different configuration than requested is a real possibility.
* `#find_or_create_account!` raises rather than reusing an account under a
  different profile. There is no third answer when `controller` is immutable.
* `#account_session_client_secret` **raises for `:cards_enabled`**. The embedded
  onboarding component is built for `requirement_collection = stripe`; the cards
  profile makes Fuime responsible for collecting the guardian's identity details,
  which is a different surface with different obligations (L4: never store ID
  images). Serving the existing flow would collect nothing while appearing to work.

### Deliberately not built

* **No `Stripe::Issuing::Cardholder` or `Card` creation.** Open question 3 in
  LEGAL_RESEARCH ("does a teen sole-prop with a guardian representative qualify as
  a supported Issuing business use case, or will underwriting class it as
  consumer?") is unanswered, and it is the question most likely to sink the
  application. Building issuance against an unapproved use case is speculative.
* **No `requirement_collection = application` onboarding flow.** See above.
* **HCB's Issuing UI stays hidden.** Un-hiding it would expose a non-functional flow.

### Still blocking, and it is not code

The three questions in LEGAL_RESEARCH "Three questions for Stripe" must be
answered first. Question 2 (may one platform run a mixed `losses.payments` fleet?)
is the one this entire change assumes; if the answer is "the Issuing restriction is
platform-wide", `PROFILES` collapses to an all-or-nothing choice and the mixed
fleet is dead.

Separately, **funding is gated**: revenue → card spend instantly needs the Balance
Transfer API private beta. The GA fallback is payout to the family's bank then a
pull top-up into the Issuing balance, a multi-day round trip. "Sell a sticker, buy
supplies an hour later" does not work yet.

**Suite:** 390 examples, 1 failure (the pre-existing `comment_policy_spec` factory
issue). 20 new examples for the profile mechanism.

---

## 2026-08-04 (later still) — Cards: spend policy, issuance, and card spend on the ledger

Built on the profile mechanism from the previous entry. Cards are issued on the
venture's OWN connected account with `stripe_account:` on every call, so Fuime is not
the issuer and does not hold the funds behind them.

### The centrepiece: `Fuime::CardSpendPolicy`

Celtic's terms forbid using an Issuing card "for personal, family or household
purposes". That cannot be left as a sentence in an agreement a fifteen-year-old
scrolled past, so it is enforced as `spending_controls.allowed_categories`.

**Allowlist, not blocklist**, and the reasoning is the failure mode. A category missing
from an allowlist declines a legitimate purchase — annoying, recoverable, the list
grows. A category missing from a blocklist lets a minor buy something personal on a
commercial card — invisible until an audit, not recoverable. A blocklist also silently
permits every category Stripe adds after the file was written.

Every category string was copied from `app/services/breakdown_engine/categorizer.rb`,
upstream HCB code already running against Stripe's real enum, rather than typed from
memory. That mattered: `package_stores_beer_wine_and_liquor` carries an "and" that
recall would have dropped, and an invalid category fails the entire Card create call. A
spec asserts every allowed string still appears in that upstream file.

Explicitly excluded with the reason recorded: **cash equivalents** (gift cards,
stored-value loads, money orders — these convert a restricted card into unrestricted
spending money and defeat every other control), food/drink/pharmacy, and
games/entertainment. Clothing and travel are excluded as opt-in-later rather than
never, because a teen printing shirts genuinely buys blanks from a clothing store.

Also pins Stripe's **required** commercial-purpose disclosure and its **forbidden**
consumer phrasings ("Personal cards", "for anything you want"), so a copy edit cannot
quietly drop one or reintroduce the other.

### Issuance

* `venture_cardholders` / `venture_cards` — separate from HCB's `stripe_cardholders`
  and `stripe_cards`, which are PLATFORM-level Issuing funded by `topup_stripe_job.rb`
  and legal only because a 501(c)(3) owns the funds (Rule 3 forbids touching that
  pipeline anyway).
* The role split is the whole legal structure: guardian is the **Accountholder**
  (liable), minor is an **Authorized User** (holds an access device). Validated in the
  model and again in the service. A minor can never hold `accountholder`; a guardian
  can never hold `authorized_user`, because oversight is not participation.
* Terms acceptance is versioned, and an acceptance of a superseded version does not
  carry forward. It is reported to Stripe via
  `individual.card_issuing.user_terms_acceptance`, so it is a fact Stripe holds rather
  than a claim in Fuime's database.
* `Fuime::CardIssuingService#issue_card!` **cancels the card and raises** if Stripe
  does not echo the category allowlist back. An unrestricted commercial card in a
  minor's hands is worse than no card.
* Virtual cards only. A physical card mailed to a minor raises delivery and signature
  questions that are not answered.
* Default spending limit of $250/month rather than unlimited — the guardian raises it
  deliberately instead of discovering it was open.

### Card spend on the ledger

`Fuime::ConnectCardRecorder` handles `issuing_transaction.created` only.
Authorizations are deliberately NOT posted: an authorization is a hold that can expire,
reverse, or capture a different amount, and posting them would put phantom expenses on
a teenager's books. The honest cost is that the ledger lags a purchase by up to a
couple of days.

Sign comes from the transaction `type`, never from the reported `amount`. Stripe
reports captures as negative today; trusting that would mean a convention change
silently turns a teenager's expenses into income and inflates the tax figure shown to
their family.

Unlike a payout, card spend **is** a deductible expense, so it is deliberately NOT
added to `TaxTrackerService::EXCLUDED_MEMO_PATTERNS` — and a spec asserts the memo
matches none of them.

### Bug fixed along the way: `Fuime::StripeHash`

`Stripe::StripeObject#to_h` is SHALLOW in the pinned stripe 11.7.0 — nested values stay
StripeObjects, which do not implement `dig`. It therefore fails on the SECOND key, so
any code digging one level passes and gives no warning that the same pattern breaks a
level down. This had already made `StripeConnectedAccount#stripe_hash` produce a
diggable `controller` mirror only by accident of jsonb serialising it en route to the
database. Both now route through a JSON round-trip.

### Still not verified

Nothing here has run against Stripe. The three questions in LEGAL_RESEARCH remain
open, and question 3 (does a teen sole-prop with a guardian representative qualify as a
supported Issuing use case, or will underwriting class it as consumer?) can still
invalidate all of it. `Fuime::ConnectOnboardingService#account_session_client_secret`
still refuses the cards profile, because the `requirement_collection = application`
onboarding flow does not exist — so no card can actually be issued end to end yet.

**Suite:** 459 examples, 1 failure (the pre-existing `comment_policy_spec` factory
issue). 85 new examples across the spend policy, issuance, the card recorder and the
cardholder model.

---

## 2026-08-04 (evening) — Guardian requirement collection, without becoming a PII store

Completes the gap the card work left open: `:cards_enabled` sets
`requirement_collection = application`, which makes gathering the guardian's identity
details Fuime's job. `account_session_client_secret` refused that profile, so no card
could be issued end to end. This is the flow that closes it.

### The governing constraint

Taking on collection is unavoidable for cards. Becoming a store of Social Security
numbers and ID photographs is not, and L4 is explicit: "ID images: verify then delete…
Store the consent *record* (method, vendor ref, timestamp, doc-version hash, IP/UA) —
never the image." The reasons stack: COPPA's VPC methods mandate prompt deletion, BIPA
(IL) gives a **private right of action** at $1K–5K per violation over stored face-match
data, and holding ID documents pulls Fuime into state breach-notification statutes it is
otherwise entirely outside.

So the architecture is **collect and forward**: identity values arrive as method
arguments, go into a Stripe API call, and are never assigned to an ActiveRecord
attribute, written to disk, cached, or logged. The ID image goes STRAIGHT TO STRIPE via
the Files API and Fuime keeps only the returned token — which makes "verify then delete"
structurally true rather than dependent on a deletion job that might not run.

### Making the claim enforceable rather than aspirational

"We don't store PII" is a claim that decays: someone adds a column to make a screen
easier, or pastes a value into a field while debugging. Four mechanisms:

1. `guardian_verifications` is a metadata-only table. A spec enumerates its columns and
   FAILS if any name suggests identity data (ssn, dob, address, id_number, image, …), so
   adding one breaks the suite rather than shipping.
2. `fields_forwarded` is validated against an ALLOWLIST of field NAMES. A value cannot
   land there even by accident, because no value is a member of the allowed set.
3. `GuardianVerification#no_personal_data_in_attributes` scans the row's own string
   attributes for SSN-shaped and base64-blob-shaped content and refuses to save.
4. **`config/initializers/filter_parameter_logging.rb` gained `:id_number`** and the
   other identity params. `:ssn` already covered `ssn_last_4` by substring, but NOT
   `id_number` — which is Stripe's field for the FULL Social Security number, the most
   sensitive value the app handles. That gap would have put whole SSNs in production
   logs.

### Also built

* `Fuime::RequirementCollectionService` — refuses to run on the payments-only profile,
  where Stripe collects directly and gathering an SSN would be taking on breach
  liability for nothing. Snapshots what Stripe was asking for BEFORE the update, since
  afterwards Stripe has cleared whatever was satisfied. Never interpolates Stripe's
  error message, which can echo the submitted value back into logs.
* `#outstanding_descriptions` translates Stripe's dotted machine identifiers into
  sentences a parent can act on, passing unknown ones through humanised rather than
  dropping them — a requirement nobody can see is a venture that never activates.
* Controller + views at `/:event_slug/payments/verify`, guardian-only. **Redirects rather
  than re-renders on error**, because a re-rendered form puts an SSN into the HTML of an
  error page.
* The disclosure partial is **content-hashed** into `doc_version_hash`, so the consent
  record proves what was agreed to without storing a copy per guardian. Editing the copy
  changes the hash by design.
* `Fuime::PaymentSetupsController#new` now redirects cards-profile ventures here, turning
  the earlier hard refusal into a working path.
* `account.updated` now marks a `GuardianVerification` accepted once requirements clear.
  Stripe exposes no "we accepted it" flag, so an empty `currently_due` with nothing
  pending verification IS the acceptance — and until then a family is told Stripe is
  still checking rather than that they are verified.

### An API asymmetry worth knowing

Uploading a file FOR a connected account requires the `Stripe-Account` header. Updating
that same account does NOT — the id is the first argument and the platform key is used.
Getting either backwards produces errors that read like permission problems. Both are
asserted in specs.

### Also fixed

`Fuime::CardSpendPolicy.copy_violations` now normalises HTML entities. The required
disclosure contains "can't", which ERB renders as `can&#39;t`, so a page carrying it
correctly was reported as missing it — a false alarm that would train someone to ignore
the check.

### Still not verified, and still the same three questions

Nothing has run against Stripe. The three questions in LEGAL_RESEARCH remain open, and
question 3 (does a teen sole-prop with a guardian representative qualify as a supported
Issuing use case?) can still invalidate the card path entirely. What HAS changed is that
there is no longer a structural gap: a cards-profile venture now has a complete
onboarding path in code.

**Suite:** 514 examples, 1 failure (the pre-existing `comment_policy_spec` factory
issue). 55 new examples across the verification model, the collection service and the
controller.

---

## 2026-08-04 (late) — Stripe's processing fee, card screens, and a UI-conventions pass

### The ledger now reconciles

Every venture's balance was overstated by roughly 2.9% + 30¢ per sale: the gross and
Fuime's cut were posted, Stripe's own cut was not, even though it comes out of the same
balance. `Fuime::ConnectPaymentRecorder#record_processing_fee` fixes it.

**Why `fee_details` and not `balance_transaction.fee`:** on a direct charge that `fee` is
the TOTAL deducted from the connected account and INCLUDES the application fee. Posting
it alongside the existing platform-fee line would have charged families Fuime's cut
twice. Only the `stripe_fee`-typed entries are summed, and a spec asserts the two fees
never double-count.

**Why a failure here raises:** the fee needs an API call the webhook payload cannot
supply. Raising lets Stripe retry the whole webhook, and because every ledger key is
shared and idempotent, the retry re-posts nothing for the payment and simply tries the
fee again. Swallowing it would leave the balance permanently wrong with only a log line.
`nil` (could not determine) and `0` (Stripe took no fee) are treated differently — the
latter posts nothing rather than a phantom zero line.

### Card screens

`Fuime::CardsController` + `/:event_slug/cards`, with the authorization split as the
actual design rather than an afterthought:

| Action | Who | Why |
|---|---|---|
| view | teen + guardian | both need to see the card and its limit |
| issue | **guardian** | issuing creates a liability they carry |
| set limit | **guardian** | raising a limit increases what can be spent |
| **freeze** | **teen + guardian** | a lost card must be stoppable in the moment |
| unfreeze | **guardian** | restoring spend is the Accountholder's decision |
| cancel | **guardian** | permanent, unlike freezing |

Freeze-but-not-unfreeze is the whole idea: freezing can only ever REDUCE what is
spendable, so the person most likely to notice a lost card first should be able to act.
Keeping unfreeze with the guardian is what stops it becoming a route around the limit
controls. `EventPolicy#freeze_cards?` vs `#manage_cards?` encode exactly that, and a spec
states the asymmetry as a single assertion so it cannot be "simplified" away.

Freeze uses Stripe's `status: "inactive"`, deliberately NOT collapsed with `"canceled"` —
cancellation is permanent and needs a new card, so a lost card should be frozen.

The nav item only appears for ventures whose account was created with card support:
`controller` is create-only, so a payments-only venture can never have cards and a nav
link to a permanent dead end is worse than no link.

### UI conventions pass (dev-docs/code_style.md)

Audited the Fuime views against actual repo usage rather than assumption, and found four
real deviations:

* **`class: "input"` on form fields — used in ZERO other views.** HCB styles inputs
  through the `.field` wrapper. Removed from all three Fuime forms.
* **`btn--sm` is not a convention** (1 outlier file); the real class is `btn-small`.
* **Destructive buttons are `bg-error`**, not `bg-primary`. Cancel-card and decline-payout
  corrected, as were the failure badges.
* **An empty `<th>` needs an explanatory comment**, which the style guide states
  explicitly. Added to the cards table.

Also: labels now carry `class: "bold"` (the dominant convention), the new disclosure
partial declares strict locals per the guide, and headings were checked for sentence case.

`Fuime::CardSpendPolicy.copy_violations` now normalises HTML entities — the required
disclosure contains "can't", which ERB renders as `can&#39;t`, so a page carrying it
correctly was reported as missing it.

**Suite:** 559 examples, 1 failure (the pre-existing `comment_policy_spec` factory issue).

---

## 2026-08-04 (night) — Cards become reachable, and two production bugs

### The gap this closes

`Fuime::ConnectOnboardingService` accepted a `profile:` argument, but nothing ever passed
`:cards_enabled` — so the entire card stack was unreachable code. Because `controller` is
create-only at Stripe, the choice has to be made BEFORE the account exists, which means
the payment-setup entry point was the only place it could live.

`Fuime::PaymentSetupsController` now offers it, gated by
`Flipper.enabled?(:fuime_cards_2026_08_04, event)`, **off by default and deliberately not
self-serve.** A `:cards_enabled` account means Fuime absorbs every negative balance on
that venture, collects the guardian's SSN, and pays Stripe's processing fees. That is a
capitalisation and compliance decision, not a preference a family should make from a form
— and with LEGAL_RESEARCH open question 3 unanswered, broad availability could create
accounts Stripe later rejects, which (create-only) those families could not be migrated
out of. The flag makes the path reachable and testable per venture without making it
available.

Three safety properties, each with a spec:

* **`?profile=cards_enabled` is validated server-side, not merely hidden in the view.** It
  is a URL anyone can type, and it selects the one configuration where Fuime carries a
  minor's chargebacks. With the flag off it is ignored.
* **An existing account's profile always wins**, read back from the row rather than from
  params, so a stale or tampered link cannot make the service raise on a mismatch.
* **The choice disappears once an account exists**, because re-offering it would promise
  something only a full re-onboarding could deliver.

### Bug 1: the global Stripe key was LIVE in production

`config/initializers/stripe.rb` computed `Rails.env.production? ? :live : :test`, ignoring
STRIPE_MODE. Fuime runs test mode by default *including in production* (render.yaml), so
the process had a LIVE global `Stripe.api_key` while every screen said "test mode". Any
call not passing `api_key:` explicitly would have moved real money — created a real Stripe
account for a minor's business, or issued a real card. Every Fuime service does pass it
explicitly (all 14 call sites audited), which is why nothing has gone wrong, but a
convention every future caller must remember is not a control.

Now derived from `StripeService.mode`. Assigned inside `config.after_initialize` because
`StripeService` is Zeitwerk-managed and unavailable while initializers run — verified by
the `uninitialized constant StripeService` this first produced. Duplicating the
STRIPE_MODE logic inline would have recreated the two-sources-of-truth problem, and
`require_relative`-ing a reloadable app/services file puts a Zeitwerk constant outside
Zeitwerk's control.

### Bug 2: the payment-setup flow raised on every request in dev and test

`before_action :authorize_setup, only: [:new, :create, :return, :refresh]` named a
`create` action that does not exist on the controller (there are four actions and four
routes, none of them create). Rails raises `AbstractController::ActionNotFound` for that
whenever `raise_on_missing_callback_actions` is on, which is the default in development
and test. Production defaults it off, so the bug was invisible precisely where it would
have been hit least and broken locally for anyone trying to use the flow. Found because
this was the first controller spec ever written for it.

**Suite:** 573 examples, 1 failure (the pre-existing `comment_policy_spec` factory issue).
