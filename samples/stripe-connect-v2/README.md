# Stripe Connect (V2 Core Accounts) — sample integration

A runnable, heavily-commented reference for Connect using the **V2 Core Accounts API**:
onboarding, products, a storefront, direct charges with an application fee, platform
subscriptions, a billing portal, and both webhook styles.

Read [`app.rb`](app.rb) top to bottom. It is one file on purpose.

## ⚠️ Read this before copying anything into the Rails app

This is a **sample**, not Fuime's integration. The main app already ships a working
Connect integration built on the **V1** Accounts API (`Stripe::Account.create` with
`controller` properties). Four things in this sample would reverse deliberate decisions
there, and one of them is a real harm.

| Sample does | Main app does | Why the difference matters |
|---|---|---|
| `dashboard: 'full'` | `stripe_dashboard.type = none` | Fuime keeps families inside Fuime rather than handing them to a Stripe UI. Flipping this changes who supports the user and what they can self-serve. |
| Onboards "users" directly | The **guardian** is the account holder | CLAUDE.md **L2**: the guardian is the legal party, Stripe Representative, and principal obligor. A teen onboarding themselves produces a voidable agreement (infancy doctrine). This sample has no guardianship concept at all. |
| Storefront URL is `/storefront/acct_123` | Storefront is `/b/:slug` | These businesses are run by **minors**. `PRODUCTION_READINESS.md` §2.2 was specifically about the storefront leaking a minor's data; putting their Stripe account ID on a public URL is a step backwards. |
| Shows Stripe's error text verbatim | Strips it | A Stripe validation error can echo the submitted value. `Fuime::RequirementCollectionService` deliberately never interpolates it, so an SSN cannot reach a log or an error page. |

**One thing here is worth stealing.** `configuration.customer: {}` plus
`customer_account: acct_...` is how a platform bills a connected account a
subscription with no separate `cus_...` to reconcile. That is exactly the monthly
platform fee `fuime.com` advertised and the app never had (`LEGAL_RESEARCH.md` §L8).

## Why this is a separate Gemfile

The Rails app pins `stripe` to **11.7.0**, which has **no `.v2` namespace** and no
event-notification parsing. The V2 API needs a modern SDK; the latest is **19.4.0**.

Bridging eight majors inside the monolith is not a sample-sized change: HCB's ledger,
Issuing and payout code are all V1 (CLAUDE.md **Rule 3** forbids touching the ledger
engine), and diverging from upstream's pin works against **Rule 8**. So this directory
has its own `Gemfile` and cannot destabilise the shipped integration.

Also note **`controller` is create-only in V1.** Existing connected accounts cannot be
migrated to V2 semantics. Any move to V2 means re-onboarding every venture from scratch,
which is a product decision, not a refactor.

## Running it

```bash
cd samples/stripe-connect-v2
cp .env.example .env      # then fill in STRIPE_SECRET_KEY
bundle install
bundle exec ruby app.rb    # http://localhost:4242
```

Missing or live keys fail at boot with an actionable message rather than at the first
API call.

### Webhooks: two listeners, two secrets

This is the step most often gotten wrong. Thin and snapshot events have **separate
signing secrets**; crossing them makes every event a signature failure.

```bash
# THIN (v2) — account requirements and capability changes
stripe listen \
  --thin-events 'v2.core.account[requirements].updated,v2.core.account[configuration.merchant].capability_status_updated,v2.core.account[configuration.customer].capability_status_updated' \
  --forward-thin-to localhost:4242/webhooks/thin

# SNAPSHOT (v1) — subscriptions, invoices, payment methods
stripe listen --forward-to localhost:4242/webhooks/snapshot
```

Put each printed `whsec_...` into the matching variable in `.env`.

> **On this machine specifically:** the Stripe CLI is authenticated to a **"Hack Club
> Shop testing"** account (`acct_1Tmdhs…`), which is not Fuime's. Pass `--api-key` with
> Fuime's own test key explicitly. Creating Fuime connected accounts under Hack Club's
> platform would violate CLAUDE.md **Rule 4**.

## What is verified, and what is not

**Verified by introspecting stripe-ruby 19.4.0** (not translated from the JS docs):

- `v2.core.accounts.create` / `.retrieve`, `v2.core.account_links.create`,
  `v2.core.events.retrieve`, `v1.products.*`, `v1.checkout.sessions.*`,
  `v1.billing_portal.sessions.create`, `Stripe::Webhook.construct_event` — all present.
- **`parse_thin_event` does NOT exist in Ruby.** The JS SDK's `parseThinEvent` is
  `client.parse_event_notification(payload, sig, secret)` here, returning a
  `Stripe::V2::Core::EventNotification` (`id`, `type`, `created`, `livemode`, `reason`,
  `context`, `fetch_event`). Copying the JS example verbatim fails with
  `NoMethodError` on the first webhook.
- The app boots, `GET /` and `GET /storefront/:id` both return 200, and the
  missing-key and live-key guards both fire.

**Not verified:** no flow has been run against a real Connect-enabled account.
Fuime's platform account (`acct_1TznaN…`) **has not signed up for Connect**, so
`POST /v1/accounts` returns:

> `You can only create new accounts if you've signed up for Connect`

Until that is done at [dashboard.stripe.com/connect](https://dashboard.stripe.com/connect),
neither this sample nor the main app can create a connected account. Choose the
**Platform** model, not Marketplace — Marketplace makes the platform the merchant of
record and puts it in the flow of funds, which is the model `LEGAL_RESEARCH.md` §L1
rules out permanently.

## Deliberate omissions

- **No database.** An in-memory Hash with `TODO(real app)` markers pointing at
  `stripe_connected_accounts`, which is the right table.
- **Onboarding status is never cached.** Read live from the API on every render, because
  a stored "ready" flag is how a platform tells a user they can take payments after
  Stripe disabled them.
- **No fulfilment on the success page.** It says so on the page: a buyer can close the
  tab, so fulfilment belongs in a webhook.
- **No Issuing.** Cards in the main app are behind a default-off flag and the
  underwriting question is unanswered.
