# Embedded Connect — how a family never opens stripe.com

**Status:** implemented, test mode. As of this document, the embedded management surface
has *not* been exercised against Stripe — see "Test plan" below, which is the next task.

This is the reference for Fuime's Stripe Connect integration: what kind of account each
venture gets, why, and how every Stripe surface a parent needs is rendered inside Fuime.

---

## 1. The shape of the thing

```
┌────────────────────────┐        direct charge          ┌──────────────────────────┐
│  customer              │  ───────────────────────────► │ Stripe connected account │
│  (buys from the teen)  │                                │  OWNED BY THE GUARDIAN   │
└────────────────────────┘                                └───────────┬──────────────┘
                                                                      │
                        application_fee_amount (Event#revenue_fee)     │  payout
                                    │                                 │  (manual, gated)
                                    ▼                                 ▼
                          ┌──────────────────┐              ┌────────────────────┐
                          │ Fuime's platform │              │ the family's bank  │
                          │     account      │              └────────────────────┘
                          └──────────────────┘

              Fuime NEVER holds the customer's money. It receives a fee.
```

The legal argument this preserves, and which no change here may break:

- **No money transmission.** Funds move customer → guardian's own Stripe account → the
  guardian's own bank. Fuime is not in the flow of funds and never has custody, so it is
  not transmitting money on anyone's behalf (CLAUDE.md L1).
- **The guardian is the legal party.** They are the account holder and Stripe
  Representative, the principal obligor on Stripe's terms, and the person who carries
  chargeback and tax consequences (L2). The teen operates the business; the adult owns
  the rails.
- **Fuime stores no identity documents.** `requirement_collection = stripe` on the default
  profile means SSNs and ID images go from the guardian to Stripe and never touch Fuime's
  database. Fuime keeps only consent records (L4).
- **Nothing says "bank."** The account is a payment account, described as opened and owned
  by a parent or guardian, with the standing not-a-bank disclosure (L5).

---

## 2. The account: what gets created and when

`Fuime::ConnectOnboardingService::PROFILES[:payments_only]` — the default for every
venture:

| Property | Value | Why |
|---|---|---|
| `controller.losses.payments` | `stripe` | Stripe carries negative balances. Fuime is pre-launch and its users are minors; it cannot absorb chargebacks. |
| `controller.fees.payer` | `account` | The venture pays Stripe's processing fee. |
| `controller.requirement_collection` | `stripe` | Forced by the line above — Stripe documents these as incompatible with `application`. Also the privacy win: the SSN goes to Stripe. |
| `controller.stripe_dashboard.type` | `none` | **The guardian has no Stripe login.** This is what makes §3 mandatory rather than nice. |
| `settings.payouts.schedule.interval` | `manual` | Nothing leaves until an adult approves. The payout gate is a Stripe setting, not just UI. |
| `business_type` | `individual`, or `company` for a school | A school is the account holder for its whole programme; a business-office employee must not personally back it. |

`controller` is **create-only at Stripe**. A venture can never be converted between
profiles — it would have to be onboarded again from scratch. This is why so much code
refuses rather than guesses.

### When the account is created

Two paths, both landing in the same idempotent `find_or_create_account!`:

1. **Eagerly, on guardianship activation.** `Guardianship#accept!` enqueues
   `Fuime::ProvisionConnectAccountJob`, which provisions an account for each venture the
   minor already holds a position on. It declines far more often than it acts — school
   ventures, ventures that inherit a school's account, and any venture with more or fewer
   than exactly one overseeing guardian are all skipped, because a wrongly-owned account
   cannot be fixed after the fact.
2. **Lazily, on the first visit to `/:slug/payments/setup`.** This covers ventures created
   *after* the guardianship activated, and is the path a guardian takes anyway.

Both are safe to race: the Stripe create carries an idempotency key
(`fuime-connect-account-<event_id>-<profile>`), so a duplicate call returns the same
account rather than creating an orphan.

Prefill: Fuime hands Stripe the guardian's name, email, date of birth and (only if
verified and already E.164) phone, so the parent confirms rather than retypes. Every field
is individually guarded — a malformed prefill fails the whole account create, which is
strictly worse than a parent typing their own phone number.

---

## 3. The embedded surfaces

Because `stripe_dashboard.type = none`, there is nowhere else for a guardian to go. Every
routine Dashboard errand therefore has an in-Fuime equivalent:

| Route | Component(s) | Who can see it |
|---|---|---|
| `GET /:slug/payments` | `notification-banner` | Status page: whole team. Banner: guardian only. |
| `GET /:slug/payments/setup` | `account-onboarding` | Guardian only |
| `GET /:slug/payments/manage` | `notification-banner`, `account-management`, `payouts`, `documents` | Guardian only |
| `GET /:slug/payments/session` | *(JSON — mints an Account Session)* | Guardian only |
| `GET /:slug/payments/refresh` | *(JSON — onboarding Account Session)* | Guardian only |

"Guardian only" is `EventPolicy#setup_payments?`, which resolves to the guardian on a
family venture and to a manager (the business office) on a school one. **The teen must
never see `account-management` or `payouts`** — they expose the account holder's identity
details and bank account.

### Feature flags that are deliberately OFF

In `Fuime::ConnectOnboardingService::MANAGEMENT_COMPONENTS`, on the `payouts` component:

- **`standard_payouts: false` / `instant_payouts: false`** — otherwise the guardian gets a
  "Pay out now" button. Stripe would permit it (they own the account), but it would route
  money around Fuime's `PayoutRequest` flow, which is the only thing making "the teen
  asks, the adult decides" an audited record rather than a story.
- **`edit_payout_schedule: false`** — a guardian switching to an automatic daily schedule
  would drain the balance on a timer, making the approval gate decorative while every
  screen in Fuime kept describing a gate that no longer existed.

So the `payouts` component is read-only plus bank-account management. Money moves only
through `/:slug/payouts`.

### The one unavoidable Stripe-branded moment

The guardian hits a Stripe-owned authentication popup inside the otherwise-embedded
onboarding form. It cannot be disabled: `disable_stripe_user_authentication` requires
`requirement_collection = application`, which would mean Fuime owning every chargeback and
collecting SSNs. The trade is correct, and `new.html.erb` warns the guardian in advance so
it reads as a security step rather than a glitch.

---

## 4. Frontend integration

Two Stimulus controllers, one shared theme.

- **`common/stripeConnectAppearance.js`** — the single source of the appearance object.
  Reads colors, font and radius off the live page (`getComputedStyle`), so the components
  follow whichever theme the user is in rather than a hardcoded palette that goes stale.
- **`stripe_connect_onboarding_controller.js`** — the single-shot onboarding form. Gets its
  first client secret rendered inline (one less round trip on the highest-drop-off screen)
  and refetches from `/payments/refresh` afterwards. `setOnExit` navigates to
  `/payments/return`.
- **`stripe_connect_component_controller.js`** — the general case. Wraps a *region* of the
  page; each `data-stripe-connect-component-target="mount"` inside it names the component
  it wants via `data-component`. One controller instance = one `ConnectInstance` = **one
  Account Session shared by every component on the page.** Instantiating per component
  would mint a session per box.

```erb
<div data-controller="stripe-connect-component"
     data-stripe-connect-component-publishable-key-value="<%= @publishable_key %>"
     data-stripe-connect-component-session-url-value="<%= fuime_payment_setup_session_path(event_slug: @event.slug) %>">
  <div data-stripe-connect-component-target="mount" data-component="notification-banner" hidden></div>
  <div data-stripe-connect-component-target="mount" data-component="account-management"></div>
  <p data-stripe-connect-component-target="fallback">Loading your payment tools…</p>
</div>
```

Two behaviours worth knowing:

- The **fallback** target stays visible until components mount and is replaced with an
  explanatory message on failure. A blank rectangle gives a parent no way to tell "still
  loading" from "broken", on the page standing between their kid and getting paid.
- The **notification banner collapses itself** via `setOnNotificationsChange` when Stripe
  reports zero notifications, so a healthy account shows nothing rather than a titled
  empty box.

Client secrets on the management page are **always fetched, never rendered inline** —
Account Sessions expire, and a management page sits open for a long time.

---

## 5. Staying in step with Stripe

Finishing the embedded form means the form was *exited*, not that the account works.
Stripe verifies asynchronously. Three mechanisms, in order of importance:

1. **`account.updated` webhooks** → `Fuime::ConnectWebhookHandler#handle_account_updated`,
   on the **connected-account endpoint** (`/webhooks/connect`), which is the one that
   carries a top-level `account` field. This is the only signal that arrives when
   verification clears ten minutes later, and without it a venture's storefront stays dark
   with nobody able to explain why. It also flips `GuardianVerification#accepted_at` when
   requirements finally empty.
2. **`/payments/return`** re-fetches the account from Stripe rather than trusting the exit.
3. **`account.application.deauthorized`** marks the mirror unusable without deleting the
   row — the venture's payment history refers to it.

`StripeConnectedAccount` is a **mirror, not a state machine** (no AASM, deliberately).
Stripe owns this object's state; a local machine would give a second authoritative-looking
answer that can silently disagree, and the failure mode is the worst available: telling a
family they can take payments when they cannot.

What unlocks what:

| Predicate | Unlocks |
|---|---|
| `ready_for_payments?` | the storefront, checkout, `Fuime::PaymentLinkService` |
| `ready_for_payouts?` | payout approval actually reaching a bank |
| `requirements_outstanding?` | a *warning* — never a block. Stripe grants grace periods, and refusing payments Stripe would have accepted breaks working ventures. |

---

## 6. The pooled path

`Fuime::PaymentWebhookHandler` is a **test-mode simulator and nothing else.** It records
payments that landed in Fuime's own platform balance, which is the model L1 retires. It now
refuses any event with `livemode: true`, keyed on the event rather than on
`StripeService.mode` — the event is the authoritative statement about money that actually
moved, and consulting our own config would agree with the misconfiguration.

Production money-in is `Fuime::ConnectPaymentRecorder`, on the connect endpoint.

---

## 7. Test plan (`stripe listen`, test mode)

Nothing here has been run against Stripe. Do this before trusting any of it.

**Setup**

```bash
# test-mode keys only; see docs/fuime/SETUP_NOTES.md
stripe login
stripe listen --forward-to localhost:3000/webhooks/stripe          # platform events
stripe listen --forward-connect-to localhost:3000/webhooks/connect # connected-account events
```

Put the `whsec_…` each command prints into `STRIPE_WEBHOOK_SECRET` and
`STRIPE_CONNECT_WEBHOOK_SECRET` respectively. **Both listeners are required** — running only
the first means `account.updated` never arrives and every account appears stuck in
"verifying" forever, which will look like a bug in this code and is not.

**Walk it**

1. **Provisioning.** Have a teen invite a guardian; accept as the guardian. Confirm
   `Fuime::ProvisionConnectAccountJob` ran and a `StripeConnectedAccount` row has a
   `stripe_id`. Confirm the account exists in the Stripe test dashboard with
   `controller.stripe_dashboard.type = none` and a manual payout schedule.
2. **Prefill.** Open `/:slug/payments/setup` as the guardian. The name, email and date of
   birth should already be filled in.
3. **Onboarding.** Complete it with Stripe's test values (SSN `000-00-0000`, test bank
   `110000000` / `000123456789`). Exit. `/payments/return` should re-ask Stripe rather than
   claim success.
4. **Webhook.** Watch the connect listener for `account.updated`. Confirm the row's
   `charges_enabled` flips and the log line
   `[Fuime] connected account … payments ENABLED` appears.
5. **Management.** Open `/:slug/payments/manage`. All four components should render, themed
   to Fuime. Confirm the `payouts` component shows **no** "pay out" button and **no**
   schedule editor. Change the bank account from `account-management` and confirm a fresh
   `account.updated` arrives.
6. **Session refresh.** Leave `/manage` open past the Account Session expiry, interact
   again, and confirm `/payments/session` is re-called rather than the page erroring.
7. **Authorization.** Sign in as the *teen* and request `/:slug/payments/manage` and
   `/:slug/payments/session`. Both must refuse. This is the check that matters most —
   these surfaces carry the guardian's identity details.
8. **A payment.** Take a test payment through the storefront. Confirm the charge lands on
   the **connected** account, that `application_fee_amount` equals `Event#revenue_fee`, and
   that the ledger line appears via `Fuime::ConnectPaymentRecorder`. Replay the event
   (`stripe events resend <id>`) and confirm no double-post.
9. **Payout gate.** As the teen, request a payout; confirm the teen cannot approve it. As
   the guardian, approve it and confirm `payout.paid` records.
10. **Simulator refusal.** Confirm `Fuime::PaymentWebhookHandler` ignores an event with
    `livemode: true` (unit test, not a live call).

**Known-unverified.** Every parameter shape in `MANAGEMENT_COMPONENTS` is
documentation-derived. `documents` and the `payouts` feature flags in particular have never
been sent to Stripe. If `Stripe::AccountSession.create` rejects one, the failure will be a
400 naming the offending key — remove it from the constant rather than working around it in
the view.
