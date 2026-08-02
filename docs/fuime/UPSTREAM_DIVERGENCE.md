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
