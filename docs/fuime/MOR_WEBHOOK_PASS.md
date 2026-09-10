# MoR webhook pass — first sale on the ledger

**2026-09-10. G10.** Production money-in is merchant-of-record
(`FEATURE_MERCHANT_OF_RECORD=true` in `render.yaml`), not Connect. A customer
pays Fuime; `Fuime::PaymentWebhookHandler` writes the venture's pending ledger
lines; `Fuime::ConnectSettlementSweep` (same class, platform Stripe account)
promotes them to `CanonicalTransaction` once Stripe marks the balance
transaction `available`.

Connect (`/fuime/webhooks/stripe/connect`, `ConnectPaymentRecorder`) is a
different product. Do not run a second `stripe listen` for it unless you are
exercising Connect on purpose.

If a founder takes a payment and the venture page stays empty, they churn and
tell the group chat. This file is the verification that that cannot happen
unnoticed.

---

## What must be true

| Piece | Value |
|---|---|
| Endpoint | `POST /fuime/webhooks/stripe` (not `/webhooks/stripe` — that 404s) |
| Signing secret env | `FUIME_STRIPE_WEBHOOK_SECRET` |
| Events | `payment_intent.succeeded`, `checkout.session.completed`, `checkout.session.async_payment_succeeded`, `charge.refunded`, `charge.dispute.created` |
| Handler | `Fuime::PaymentWebhookHandler` |
| Ledger key | PaymentIntent id (`fuime_<pi_…>`), never the Checkout Session id |
| Metadata | `fuime_event_id` + `fuime_fee_cents` on **both** the session and `payment_intent_data` (`PaymentLinkService`) |

Either success event is enough. Both together post once. A Dashboard that only
ticks Checkout events used to drop every sale — the handler ignored
`checkout.session.completed` to avoid a double-post, and if `payment_intent.succeeded`
was not registered nothing landed. That is the gap this pass closes.

---

## 1. Specs (no Stripe account)

```bash
bundle exec rspec \
  spec/services/fuime/payment_webhook_handler_spec.rb \
  spec/services/fuime/missed_mor_payment_sweep_spec.rb \
  spec/requests/fuime_mor_checkout_ledger_spec.rb \
  spec/requests/fuime_stripe_webhook_endpoint_spec.rb
```

Expect: signed `checkout.session.completed` and `payment_intent.succeeded` each
produce gross + fee pending lines; replay and the twin event do not double-post;
an unpaid / subscription session is ignored; a missed succeeded PI is backfilled.

---

## 2. `stripe listen` (test mode, Fuime's account)

The CLI must be logged into **Fuime's** test account. A previous pass forwarded
events from Hack Club Shop (`acct_1Tmdhs…`) while the app key was
`acct_1TznaN2Uz4P3wrXO` — every handler no-op'd and looked healthy.

```bash
stripe config --list          # account must match StripeService
stripe login                  # only if it does not

# App running at localhost:3000 (docker compose up web).
stripe listen \
  --forward-to localhost:3000/fuime/webhooks/stripe \
  --events payment_intent.succeeded,checkout.session.completed,checkout.session.async_payment_succeeded,charge.refunded,charge.dispute.created
```

`stripe listen` prints a `whsec_…`. Either:

- leave `FUIME_STRIPE_WEBHOOK_SECRET` **blank** in development — the controller
  accepts unsigned events only when `Rails.env.development?` and Stripe is not
  live — **or**
- paste that `whsec_` into `FUIME_STRIPE_WEBHOOK_SECRET` and restart.

A local unsigned 200 does **not** prove production. Production must have the
endpoint secret Stripe shows **once** at endpoint creation.

Print the same commands from the app:

```bash
rake fuime:mor_webhook_pass:listen
```

---

## 3. Drive a sale

### A. Through the storefront (the real path)

1. Venture can sell (`accepts_payments?`): vetted, public, category allowlisted.
   Under MoR there is no per-venture connected account.
2. Open `/pay/<slug>/<offer>` (or `/b/<slug>` → Buy) as a **guest**.
3. Pay with `4242 4242 4242 4242`, any future expiry, any CVC.
4. CLI should show `200` for `checkout.session.completed` and
   `payment_intent.succeeded`.
5. Venture home: two pending lines (gross + "Fuime platform fee"), and
   "more from recent sales" on the balance. Payable stays $0 until settlement —
   Fuime does not front unsettled money.

### B. Headless (no browser)

```bash
SLUG=mor-webhook-pass rake fuime:mor_webhook_pass:setup
SLUG=mor-webhook-pass rake fuime:mor_webhook_pass:charge
```

`charge` confirms a platform PaymentIntent with `pm_card_visa`, feeds the real
`payment_intent.succeeded` event into `PaymentWebhookHandler`, asserts the
pending lines, and replays the same event to prove idempotency.

---

## 4. Settle to a CanonicalTransaction

Pending incoming is excluded from `Event#balance_v2_cents` on purpose
(`fronted: false`). The number a teenager treats as "I made money" moves when
the sweep runs:

```bash
SLUG=mor-webhook-pass rake fuime:mor_webhook_pass:settle
```

In production `Fuime::ConnectSettlementSweepJob` does this on a schedule. Under
MoR it asks **Fuime's** platform balance, not a connected account.

Pass: `canonical_pending_settled_mappings` exists, `PayablesLedger#gross_sales_cents`
equals the sale, the venture page shows the amount owed.

---

## 5. If listen was down

```bash
HOURS=24 rake fuime:mor_webhook_pass:backfill
```

`Fuime::MissedMorPaymentSweep` lists succeeded platform PaymentIntents with
`fuime_event_id` and no invoice, and runs them through the same handler.
Already-posted sales are skipped.

---

## Production checklist

1. Stripe Dashboard → Developers → Webhooks → platform endpoint
   `https://app.fuime.com/fuime/webhooks/stripe`.
2. Events listed in the table above. Losing `payment_intent.succeeded` used to
   be fatal; losing both success events still is.
3. Signing secret in `FUIME_STRIPE_WEBHOOK_SECRET` on web **and** worker
   (a 400 from a secret mismatch looks like "Stripe is down").
4. `STRIPE_MODE=test` until live keys are an explicit, reviewed change.
5. After the first real test-mode storefront pay: confirm the two pending lines,
   run or wait for the sweep, confirm `gross_sales_cents`.

Do not use `EMBEDDED_CONNECT.md` §7 for this. Its `stripe listen` URLs
(`/webhooks/stripe`) and env names (`STRIPE_WEBHOOK_SECRET`) are the Connect-era
plan and will 404 / skip verification.
