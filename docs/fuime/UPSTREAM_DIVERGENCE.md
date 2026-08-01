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
