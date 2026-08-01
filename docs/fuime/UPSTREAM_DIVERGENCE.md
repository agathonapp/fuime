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
