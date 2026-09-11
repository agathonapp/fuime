# Stripe feature audit — is Stripe fully set up?

**2026-09-11.** Read-only audit of `origin/main` at
[`84b9c2540`](https://github.com/agathonapp/fuime/commit/84b9c2540)
(`Demo sandbox: one command, living checklist, Become` — PR #98).
No product code changed. No Stripe Dashboard was opened. No money was
moved.

**Trust this for:** what the *code and deploy config* say Stripe does
on the app that would be deployed from this commit.

**Do not trust this for:** whether the live Stripe account actually has
the webhook events ticked, whether `FUIME_STRIPE_WEBHOOK_SECRET` matches
the endpoint, or whether a counsel memo is on file. Those live in the
Dashboard / Render dashboard and are marked **unknown** below.

**Related docs, and where they lie:**

| Doc | Still true? | Drift |
|---|---|---|
| `render.yaml` (`STRIPE_MODE=live`, `FEATURE_MERCHANT_OF_RECORD=true`, `PLAID_ENV=sandbox`) | **The deploy contract** | This audit treats that as "as deployed" |
| `MOR_WEBHOOK_PASS.md` | **Current for money-in** | §Production checklist item 4 still says `STRIPE_MODE=test` |
| `EMBEDDED_CONNECT.md` | **Current for leftover Connect** | Production is MoR; Connect screens are retired in the UI |
| `STRIPE_PASS.md` (2026-08-05) | **History of Connect exercise** | Proven against connected accounts, not MoR |
| `TEEN_GROWTH_GAPS.md` | **Mostly current on funnel** | Pricing-site row is stale after G3; G1/G5 landed after its snapshot |
| `CLAUDE.md` CURRENT POSITION / L1 prose | **Contradicted by deploy config** | Still describes guardian-owned Connect as the shipping model |
| `config/initializers/stripe.rb` header | **Stale** | Still says `render.yaml` sets `STRIPE_MODE=test` |

Status tags used in the matrix:

| Tag | Meaning |
|---|---|
| **MoR primary** | The path production is supposed to use (`FEATURE_MERCHANT_OF_RECORD=true`) |
| **wired** | Code path exists, is reached from a real UI/API, and has specs |
| **leftover Connect** | Built for guardian-owned connected accounts; still in the tree; not the production money model |
| **gated off** | Explicitly refused by a flag, `DisabledModules`, or `collectable?` |
| **broken** | Reachable (or linked) and does the wrong thing, or cannot complete |
| **unknown** | Requires Stripe Dashboard / secret store state this audit did not inspect |

---

## 0. One-screen answer

**No. Stripe is set up enough to take a card as Fuime LLC. It is not
set up enough to pay a family, or to describe that honestly.**

Production (`render.yaml`) is **live Stripe + merchant-of-record**. A
vetted public services venture can open a Checkout Session on Fuime's
platform account. `Fuime::PaymentWebhookHandler` can post the sale.
`Fuime::ConnectSettlementSweep` (same class, platform balance) can
promote pending lines once Stripe marks funds available.

Everything after that is incomplete or leftover:

- There is **no ACH / Transfer originator**. `PayoutBatchService#mark_paid!`
  writes a ledger debit. It does not send money.
- Bank collection is **gated off** because `PLAID_ENV=sandbox` and
  `STRIPE_MODE=live` (`Fuime::PlaidLinkService.collectable?`). The
  "Payout account" nav item is hidden for the same reason.
- The **Payouts** page still offers Connect's "Ask my guardian" form.
  Under MoR that form calls `PayoutService`, which requires a connected
  account that MoR never creates.
- Accepting a guardianship still enqueues
  `Fuime::ProvisionConnectAccountJob`, which has **no MoR gate** and
  would create a live connected account on a product that retired that
  screen.
- fuime.com and several in-app sentences still describe a
  **parent-owned Stripe account**.

Cards are off. Demo sandbox is hidden. Family-plan Billing on the
platform account looks wired. Webhook *registration* in the Dashboard
is unknown.

---

## 1. Deployed posture (from the repo, not the Dashboard)

From `render.yaml` (web and worker):

| Knob | Declared value | Effect in code |
|---|---|---|
| `STRIPE_MODE` | `live` | `StripeService.live?` is true; live keys required at boot |
| `FEATURE_MERCHANT_OF_RECORD` | `"true"` | Platform Checkout; Connect payment-setup UI retired |
| `FEATURE_SPONSOR_BANKING` | **absent** | Off. No custody, no live Issuing |
| `PLAID_ENV` | `sandbox` | `PlaidLinkService.collectable?` is **false** while Stripe is live |
| `FUIME_STRIPE_WEBHOOK_SECRET` | `sync: false` | Must be set or boot fails under MoR |
| `FUIME_STRIPE_CONNECT_WEBHOOK_SECRET` | `sync: false` | Warning only if missing (no connected accounts under MoR) |
| `FUIME_MOR_COUNSEL_MEMO` | `sync: false` | Boot refuses MoR without a non-empty value |

Safety rails: `config/initializers/fuime_safety_check.rb` (production /
staging only). Live keys without `STRIPE_MODE=live` refuse to boot, and
the reverse. MoR without a counsel-memo env refuses to boot. A missing
platform webhook secret is an **error** under MoR (money in Fuime's
balance with no payable), a warning under Connect.

`StripeService` (`app/services/stripe_service.rb`) is the mode source.
`config/initializers/stripe.rb` now sets the global `Stripe.api_key`
from `StripeService.mode`. Fuime services still pass `api_key:`
explicitly.

Demo sandbox (`Fuime::DemoSandbox.enabled?` in
`app/services/fuime/demo_sandbox.rb`): **false whenever Stripe is
live**, including production. Routes comment in `config/routes.rb`
matches. PR #98 did not leave a live-mode playground.

---

## 2. Feature matrix

### Money-in

| Surface | Path / class | Status | Notes |
|---|---|---|---|
| Storefront Pay / offer checkout | `Fuime::CheckoutsController` → `PaymentLinkService#create_checkout_session` | **MoR primary / wired** | Under MoR, no `stripe_account:`, no `application_fee_amount`. Receipt says "sold by Fuime". |
| Hosted payment page | `GET /pay/:event_slug/:offer` → `Fuime::PaymentPagesController` | **wired** | Same checkout service. |
| Discover shop | `Fuime::DiscoverController` | **wired** | Lists payable published offers. |
| Payment-links API | `POST /api/fuime/v1/payment_links` | **wired** | Creates an unlisted `Fuime::Offer`, not a Stripe Payment Link. Checkout is still Fuime Checkout. |
| Eligibility to sell | `Event#accepts_payments?` / `selling_blockers` | **MoR primary / wired** | Under MoR, does **not** require a connected account (that used to make every venture unsellable). Still requires vetting + launch-scope. |
| Platform webhook → ledger | `POST /fuime/webhooks/stripe` → `PaymentWebhookHandler` | **MoR primary / wired** | Posts from `payment_intent.succeeded` **or** `checkout.session.completed` / `async_payment_succeeded`, keyed on PaymentIntent id. |
| Missed-payment sweep | `Fuime::MissedMorPaymentSweep` | **wired, not scheduled** | Rake `fuime:mor_webhook_pass:backfill` only. Not in `config/schedule.yml`. |
| Settlement | `Fuime::ConnectSettlementSweep` / `ConnectSettlementSweepJob` | **MoR primary / wired** | Name is leftover. Under MoR it reads the **platform** balance. Cron every 30 minutes. |
| Connect direct-charge recorder | `ConnectPaymentRecorder` via `/fuime/webhooks/stripe/connect` | **leftover Connect** | Still the Connect money-in path. Shared ledger keys with the platform handler. |
| Pooled simulator | `PaymentWebhookHandler` when MoR is off and event is live | **gated off** | Refuses live events unless MoR is on. |
| Upstream invoices / donations | `DisabledModules` (`invoices`, donations, …) | **gated off** | An HCB invoice payment would miss the MoR payable. |
| Refund / dispute lines | `PaymentWebhookHandler` `charge.refunded` / `charge.dispute.created` | **wired** | Posts reversals + proportional fee rebate. Exercise against live MoR: **unknown**. |

### Money-out

| Surface | Path / class | Status | Notes |
|---|---|---|---|
| Weekly payout run | `PayoutBatchService` + `GeneratePayoutBatchJob` (Wed 14:00 UTC) | **MoR primary / wired (ledger only)** | `generate!` requires MoR. Admin reviews at `/admin/payout_batches`. |
| `mark_paid!` | `PayoutBatchService#mark_paid!` | **wired / broken as a rail** | Debits the operator ledger. **Does not call Stripe, Plaid, or ACH.** No originator (`MOR_MIGRATION_PLAN` §4.3). |
| Plaid bank connect | `Fuime::PayoutMethodsController` + `PlaidLinkService` | **gated off (as deployed)** | `collectable?` is false when Plaid is sandbox and Stripe is live. Button refused; nav hidden. |
| Payout-account page | `GET /:slug/payout-method` | **wired, confusing** | Reachable by URL. Shows "Payouts open a little later" when not collectable. |
| Connect Stripe payout | `PayoutService#approve_stripe_payout!` → `Stripe::Payout.create` on the connected account | **leftover Connect / broken under MoR** | `ensure_payouts_possible!` requires `payment_account`. Under MoR that is nil forever. |
| Teen "Ask my guardian" | `Fuime::PayoutsController#create` + `app/views/fuime/payouts/index.html.erb` | **leftover Connect / broken under MoR** | Form still renders when `request_payout?`. Submit fails: "hasn't finished payment setup yet." |
| Guardian approve-and-send | `#approve` | **leftover Connect / broken under MoR** | Would try a connected-account payout. |
| School mark-paid | `PayoutService#settle!` / `#mark_paid!` on a personal transfer | **leftover Connect** | School-shared Stripe account. Nav hidden unless `shares_payment_account?`. |
| Connect Transfers | `Stripe::Transfer` | **gated off / unused** | `SchoolFundingService` documents that Transfers are never used (L1). Specs assert they are not created. |
| Connect payout webhooks | `ConnectPayoutRecorder` (`payout.created/paid/failed/canceled`) | **leftover Connect** | Ledger follows Stripe payout objects on a connected account. |
| Guardian as payout gate (MoR) | `Event#payout_setup_blockers` + `PayableAssessment` | **MoR primary / wired** | No verified destination, or an unguarded minor, skips the weekly run. Not the same as Connect's approve-and-send. |

### Connect onboarding

| Surface | Path / class | Status | Notes |
|---|---|---|---|
| Payments nav | `events_helper.rb` `:payments` | **gated off under MoR** | Hidden when `merchant_of_record?`. |
| Payment setup / embedded onboarding | `/:slug/payments`, `/setup`, `/manage`, `/session`, `/refresh` | **leftover Connect** | `PaymentSetupsController#retired_under_merchant_of_record` redirects to payout-method. |
| Requirement collection (cards KYC) | `/:slug/payments/verify` | **leftover Connect** | **Not** retired at the controller. No cards profile → redirect to payment setup → MoR redirect to payout-method. |
| `ConnectOnboardingService` | `app/services/fuime/connect_onboarding_service.rb` | **leftover Connect** | No MoR guard. Still creates `payments_only` / `cards_enabled` accounts. |
| Eager provision | `Guardianship#accept!` → `ProvisionConnectAccountJob` | **leftover Connect / broken under live MoR** | **No MoR gate.** On live keys this creates a real connected account for a product that no longer shows the screen. |
| Embedded JS | `stripe_connect_onboarding_controller.js`, `stripe_connect_component_controller.js` | **leftover Connect** | Unreachable via nav under MoR. |
| Guardian as connected-account owner | `PaymentSetupsController#acting_guardian` | **leftover Connect** | Correct for Connect. Not reachable as a happy path under MoR. |

### Billing

| Surface | Path / class | Status | Notes |
|---|---|---|---|
| Family plan page | `GET /my/billing` | **wired** | Pro is `$19.99/mo + 7%` (same take-rate as Free). |
| Subscribe | `POST /my/billing/subscribe` → `SubscriptionService#checkout_session` | **wired** | Platform Stripe Billing. Adult / staff only. |
| Double-subscribe guard | `BillingController#subscribe` | **wired** | Active → refuse. `stripe_backed?` (past_due / unpaid / incomplete) → portal, not a second Checkout. |
| Billing portal | `POST /my/billing/portal` | **wired** | Stripe-hosted. `turbo: false` so the cross-origin 302 is followed. |
| Subscription webhooks | `SubscriptionWebhookHandler` (`customer.subscription.created/updated/deleted`) | **wired** | Dispatched from the **platform** endpoint. |
| Admin comps / cancel-in-Stripe | admin subscriptions | **wired** | Comp has no Stripe customer; portal is hidden. |

### Cards / Issuing

| Surface | Path / class | Status | Notes |
|---|---|---|---|
| Live Issuing | `Fuime::Features.card_issuing_permitted?` | **gated off** | `sponsor_banking? \|\| !StripeService.live?`. Live + no sponsor bank → false. |
| Fuime cards nav | `events_helper.rb` `:cards` (Fuime) | **gated off** | Also requires `payment_account&.cards_profile?` (nil under MoR). |
| HCB cards overview nav | `event_cards_overview_path` | **gated off** | Hidden unless `card_issuing_permitted?`. |
| Controllers | `DisabledModules::CARD_ISSUING_CONTROLLER_PREFIXES` | **gated off** | Blocks state-changing requests to `stripe_cards`, `fuime/cards`, etc. GETs still render for inherited rows. |
| `CardIssuingService` | connected-account Issuing | **leftover Connect** | Issues on the venture's own Stripe account. Needs `cards_enabled` profile + Flipper `fuime_cards_2026_08_04`. |
| Cards-profile onboarding | `?profile=cards_enabled` | **gated off** | Server-side Flipper check. Moves losses to Fuime. |
| Upstream `/stripe/webhook` Issuing handlers | `StripeController` | **leftover / gated** | HCB Issuing authorizations. Wrong funding rail for Fuime (platform Issuing balance). |

### Webhooks

| Endpoint | Secret env | Handler | Status |
|---|---|---|---|
| `POST /fuime/webhooks/stripe` | `FUIME_STRIPE_WEBHOOK_SECRET` | `PaymentWebhookHandler`, `SubscriptionWebhookHandler`, `application_fee.refunded` → `ConnectPaymentRecorder` | **MoR primary / wired** |
| `POST /fuime/webhooks/stripe/connect` | `FUIME_STRIPE_CONNECT_WEBHOOK_SECRET` | `ConnectWebhookHandler` → payment / payout / funding / card recorders + `account.updated` | **leftover Connect** |
| `POST /stripe/webhook` | `StripeService.construct_webhook_event` (HCB secret shape) | `StripeController` (Issuing, HCB invoices, disputes, …) | **leftover** |
| `POST /webhooks/stripe` | — | — | **404** (`MOR_WEBHOOK_PASS.md`) |

Unsigned events are accepted **only** in development when Stripe is not
live (`WebhooksController#allow_unsigned_webhooks?`).

**Events the code handles vs what must be registered** — Dashboard
subscription is **unknown**. The code will 200-and-ignore unknown
types. A Dashboard that only ticks Checkout events used to drop every
sale; G10 closed that in the handler, but a Dashboard that ticks
neither success event still drops sales.

Platform handler (`PaymentWebhookHandler::HANDLED_TYPES`):

- `payment_intent.succeeded`
- `checkout.session.completed`
- `checkout.session.async_payment_succeeded`
- `charge.refunded`
- `charge.dispute.created`

Also dispatched on the same endpoint:

- `customer.subscription.created` / `updated` / `deleted`
- `application_fee.refunded` (Connect fee rebate; rare under MoR because MoR Checkout has no application fee)

Connect dispatcher also accepts (leftover):

- `account.updated`, `account.application.deauthorized`
- Connect payment / payout / top-up / `issuing_transaction.created`

### Live vs test / demo

| Surface | Status |
|---|---|
| `StripeService.mode` / `live?` | **wired** |
| Boot safety (live keys, MoR memo, webhook secret) | **wired** |
| Demo sandbox roster / Become | **gated off when live** (`DemoSandbox.enabled?`) |
| Learn "test mode" footnote | **wired** — hidden when `StripeService.live?` |
| Marketing site "today, test mode, no real money" | **broken copy** — contradicts `STRIPE_MODE=live` |

### Leftover parent-owned-Stripe copy (main as deployed)

These still assume a guardian-owned connected account, or "live launch
hasn't happened," even though production is live MoR:

| Place | What it still says |
|---|---|
| `site/index.html` (~1087) | "At live launch, into a Stripe account you own" / "Today it is test mode" |
| `site/start.html` (meta + body) | "paid into a Stripe account your parent owns" |
| `site/pricing.html` (~601–612) | Test mode into an account Fuime controls; live launch = parent-owned Stripe |
| `site/parents.html` (FAQ + body, many) | Parent-owned Stripe; "today, nowhere / test mode" |
| `app/views/learn/lessons/_what_fuime_takes.html.erb` | Money-in is MoR-aware; **money-out always** says a guardian must approve a payout |
| `app/views/fuime/payouts/index.html.erb` footer | "Payouts are sent by Stripe from the venture's own account to the bank account the parent or guardian connected" |
| Same file, request form | "Ask my guardian" / "It goes to their bank account" |
| `app/views/fuime/payment_setups/*.html.erb` | Full Connect onboarding copy (redirected under MoR, still in the tree) |
| `app/views/admin/payout_batches.html.erb` | "Operators are paid on the Connect path" when MoR is off (not shown in production) |

Buyer-facing MoR copy that **is** correct:
`app/views/fuime/_seller_of_record.html.erb` ("Sold by Fuime LLC").

---

## 3. The eight required areas

### 3.1 Money-in

`PaymentLinkService` (`app/services/fuime/payment_link_service.rb`)
branches on `Fuime::Features.merchant_of_record?`.

- **MoR:** `create_mor_checkout_session` — platform account, billing
  address required, metadata `fuime_event_id` + `fuime_fee_cents` on
  both the session and `payment_intent_data`. Fee is a **ledger
  payable**, not a Stripe application fee.
- **Connect:** `create_checkout_session` — `stripe_account:` on
  `event.payment_account`, `application_fee_amount` when the plan fee
  is positive.

`CheckoutsController` is the public entry. It does not know about
Connect vs MoR; it calls `create_checkout_session`. Signed-in minors
are refused (guests may pay).

`PaymentWebhookHandler` is the **primary** money-in recorder under MoR
(its own header says so). Under Connect it is the test-mode pooled
simulator and refuses live events. `ConnectPaymentRecorder` is the
Connect sibling (direct charges, observed application fee + Stripe
processing fee).

`MissedMorPaymentSweep` lists succeeded **platform** PaymentIntents
with `fuime_event_id` and no invoice, and replays them through the
handler. It is not on the Sidekiq cron. A missed first sale stays
missed until someone runs the rake task.

### 3.2 Money-out

Two products share one "Payouts" nav item.

**Connect (leftover):** teen requests → guardian approves →
`Stripe::Payout.create` on the connected account →
`ConnectPayoutRecorder` books the debit. School path: approve then
human `settle!`.

**MoR (production):** nobody asks. `GeneratePayoutBatchJob` builds a
draft from `PayableAssessment` (hold / reserve / min / max in
`PayoutPolicy`). An admin approves. `mark_paid!` posts a **settled**
ledger debit. Sending dollars to a bank is unbuilt: Plaid stores an
Item token and account id so a future originator can call
`/processor/token/create`. `/auth/get` is never called (L4).

Guardian approval under MoR is **structural** (a payout run skips an
unguarded minor), not a per-request "Approve and send" button.

Plaid Auth is implemented (`PlaidLinkService`,
`app/javascript/controllers/plaid_link_controller.js`). As deployed it
will not collect: sandbox Plaid + live Stripe is the combination that
would store a fictional `verified` destination indistinguishable from
a real one after `PLAID_ENV` is promoted.

### 3.3 Connect onboarding — still reachable under MoR?

**From the nav: no.** Payments is hidden.

**From a URL: the controller redirects** every action to
`/:slug/payout-method` (`PaymentSetupsController#retired_under_merchant_of_record`).
Specs: `spec/requests/fuime_connect_screens_retired_spec.rb`.

**From a job: yes, and that is the leak.** `Guardianship#accept!`
always enqueues `ProvisionConnectAccountJob`. The job and
`ConnectOnboardingService` do not read `merchant_of_record?`. On live
keys that is a live `Account.create`.

`/:slug/payments/verify` is not in the retired `before_action`. A
venture without a `cards_enabled` account is bounced to payment setup,
which then redirects to payout-method. A cards-profile account that
already exists (Flipper + leftover provision) would still render KYC.

Embedded components (`account-onboarding`, `account-management`,
`payouts` with standard/instant payouts **off**) are leftover. They
are the right design for Connect and the wrong product for MoR.

### 3.4 Billing

Family plan is platform Stripe Billing. Price lookup key
`fuime_monthly_<cents>` from `Event::Plan::Pro#monthly_fee_cents`
(1999). The 2026-08-21 double-subscribe hole is closed in
`BillingController#subscribe`. Minors see status and are told to ask
a parent; subscribe/portal refuse them. Staff count as adults so the
console can buy the plan it sells.

### 3.5 Cards / Issuing

Gated. `FEATURE_SPONSOR_BANKING` is off. Stripe is live, so
`card_issuing_permitted?` is false. Fuime cards routes 404/redirect on
write. The Fuime "Cards" nav needs a `cards_profile?` connected
account that MoR never creates.

A swipe on inherited HCB Issuing would still debit the **platform**
Issuing balance (`DisabledModules` header). That is uncollateralised
credit, not a family card.

### 3.6 Webhooks

Two Fuime endpoints, two secrets, plus leftover `/stripe/webhook`.
Production must have the platform endpoint at
`https://app.fuime.com/fuime/webhooks/stripe` with the G10 event set
and the signing secret on **web and worker**. This audit did not
confirm that in the Dashboard (`STRIPE_PASS.md` records a 2026-08-05
repoint; treat as historical).

Connect endpoint can stay registered; under MoR it should be quiet.
A missing Connect secret is a boot **warning**, not an error.

### 3.7 Live vs test

`render.yaml` is live. Demo sandbox is hidden. Safety check logs
"REAL money" on every production boot. Local/dev default remains
test (`StripeService.mode` → `:test` if unset).

### 3.8 UI that still assumes a parent-owned Stripe account

See the leftover-copy table. Worst user-facing: fuime.com (parents
and teens), the Payouts page form + footer, and Learn "Getting it
out". In-app Connect **screens** were retired (PR #68 + follow-ups);
the **sentences** on Payouts and the marketing site were not.

---

## 4. Top 10 broken or confusing user-facing flows

Priority is "a founder or parent hits this while trying to use the
product as deployed," not "code smell."

1. **Cannot connect a bank on production.** Stripe is live, Plaid is
   sandbox, `collectable?` is false. The adult who wants to be paid
   is told "Payouts open a little later." Nav item is hidden, so many
   never even find the page. Files:
   `app/services/fuime/plaid_link_service.rb`,
   `app/helpers/events_helper.rb` (`:payout_method`),
   `app/views/fuime/payout_methods/show.html.erb`.

2. **Payouts page still runs the Connect "Ask my guardian" flow.**
   Earnings (MoR, correct) sit above a request form that calls
   `PayoutService` and fails without a connected account. Footer
   still says Stripe pays from "the venture's own account." Files:
   `app/views/fuime/payouts/index.html.erb`,
   `app/services/fuime/payout_service.rb`,
   `app/controllers/fuime/payouts_controller.rb`.

3. **fuime.com describes the wrong money model.** Parent-owned Stripe,
   "today test mode / no real money," "at live launch…" — while
   production is live MoR. L8: the site must describe the product
   that exists. Files: `site/index.html`, `site/start.html`,
   `site/pricing.html`, `site/parents.html`.

4. **`mark_paid!` does not pay anyone.** An admin can generate,
   approve, and mark a run paid. The operator's ledger goes down.
   No bank is credited. Families who connected a bank (in a
   collectable environment) would still wait. Files:
   `app/services/fuime/payout_batch_service.rb`,
   `app/views/admin/payout_batch.html.erb`.

5. **"Set where your money goes" is a dead end as deployed.** The
   MoR payouts warning links to payout-method (`payouts/index.html.erb`),
   which then says payouts are not open yet. Two screens, zero
   action.

6. **Accepting a guardian invite can create a live Connect account
   nobody will use.** `Guardianship#accept!` →
   `ProvisionConnectAccountJob` → `ConnectOnboardingService` with
   live keys. The family is then in a split-brain: MoR Checkout on
   Fuime's account, plus an unused Stripe account in the parent's
   name. Files: `app/models/guardianship.rb`,
   `app/jobs/fuime/provision_connect_account_job.rb`.

7. **Learn still teaches Connect money-out.** After a correct MoR
   money-in paragraph, "Getting it out" says a guardian must approve
   each payout to their Stripe-linked bank. File:
   `app/views/learn/lessons/_what_fuime_takes.html.erb`.

8. **A missed first sale has no automatic recovery.** G10 made the
   handler accept either success event, but
   `MissedMorPaymentSweep` is rake-only. If the Dashboard omits both
   events, or a delivery fails after retries, the venture page stays
   empty. That is the churn failure `MOR_WEBHOOK_PASS.md` names.

9. **Signed-in minor buyers cannot check out.** Correct for L2
   (checkout is a contract) and a confusing storefront: a classmate
   logged into Fuime is refused; a guest is not.
   `Fuime::CheckoutsController#refuse_minor_buyer`.

10. **Cards look like a product in leftover HCB surfaces and docs;
    they cannot issue on live Stripe.** Fuime cards nav is hidden
    (good). Inherited `stripe_cards` GET pages and admin Issuing
    tools still exist. Selling "business cards" in onboarding would
    be a lie.

---

## 5. Recommended next 5 engineering fixes

Ordered by "stop lying / stop creating unused live Stripe objects /
then make money-out real."

1. **Retire leftover Connect money-out UI under MoR.** On
   `PayoutsController#index` / `#create` / `#approve`, do not render
   or accept teen-request / guardian-send. Keep the payables figure,
   the weekly-cadence sentence, and the destination / guardian
   blockers. Rewrite the footer. Same treatment as payment-setup
   retirement (`fuime_connect_screens_retired_spec.rb`).

2. **Stop provisioning Connect accounts under MoR.** Gate
   `ProvisionConnectAccountJob` and `ConnectOnboardingService#find_or_create_account!`
   on `!Fuime::Features.merchant_of_record?`. Leave the code
   (Rule 2). Add a request/job spec that a guardianship accept does
   not call Stripe Account create when MoR is on.

3. **Make the bank path honest, then pick an originator.** Either
   (a) keep `PLAID_ENV=sandbox` and stop linking to payout-method
   until `collectable?`, or (b) set `PLAID_ENV=production` and show
   the nav when you are ready to store real Items. In parallel,
   choose the §4.3 originator and have `mark_paid!` (or a successor)
   actually send. Collecting banks with no rail is L8 again.

4. **Rewrite fuime.com + Learn money copy to MoR.** Customer pays
   Fuime LLC; Fuime pays the family on a cadence to a bank the
   parent connects; Fuime is not a bank; no "parent-owned Stripe
   account" and no "still test mode." Pin with the existing
   marketing specs (`spec/fuime_marketing_pricing_spec.rb` pattern).

5. **Schedule `MissedMorPaymentSweep` and treat Dashboard event
   registration as an ops checklist, not a code guess.** Add a cron
   next to `ConnectSettlementSweepJob`. Do not invent Dashboard
   state in the repo — confirm the platform endpoint's event list
   in Stripe and record the date in `MOR_WEBHOOK_PASS.md`.

---

## 6. What this audit did not do

- Did not call Stripe, Plaid, or Render.
- Did not read Dashboard webhook event ticks, signing secrets, or
  Connect platform settings.
- Did not run `bundle exec rspec` (docs-only change).
- Did not merge or assume anything from an open PR #99 — this is
  `main` at PR #98.
- Did not change product behavior.

If a later session exercises Stripe, start with
`docs/fuime/MOR_WEBHOOK_PASS.md` for money-in and this file for
"what is leftover."
