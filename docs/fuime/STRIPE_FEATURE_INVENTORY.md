# Fuime Stripe feature inventory (live surfaces + repo)

**Date:** 2026-09-11  
**Scope:** No money movement, no partner emails, no live-mode flips.  
**Evidence:** public HTTP probes on `app.fuime.com` / `fuime.com` + `github.com/agathonapp/fuime` main.  
**Caveat:** `FEATURE_MERCHANT_OF_RECORD` not read from Render; inferred from MoR redirects/docs + live Checkout on platform account.

Statuses: **wired** | **leftover** | **broken** | **unknown**

---

## Summary table

| Surface | Status | Evidence |
|---|---|---|
| **Checkout (money-in)** | **wired** (live) | Unauth POST `/b/fuime-hq/pay` → 302 `checkout.stripe.com/c/pay/cs_live_…` (prior Banking Ops probe; no card entered). MoR path charges platform account. |
| **Connect onboarding** (`/b/:slug/payments`, `/payments/setup`, manage) | **leftover** (redirected under MoR) | Routes still exist. `PaymentSetupsController` `retired_under_merchant_of_record` → redirect to `payout_method` with MoR notice when `Fuime::Features.merchant_of_record?`. Unauth → login. Nav Payments item hidden under MoR (PR #68 comment in controller). Controllers/services still encode **guardian-as-Connect-owner**. |
| **PayoutMethod / Plaid bank connect** | **wired** (product) / **unknown** (live Plaid env) | Routes: `/b/:slug/payout-method`. Unauth → login. MoR destination for payables. `render.yaml` still documents `PLAID_ENV=sandbox` and refuses collect under live Stripe until production Plaid — **production Plaid readiness unknown** without env read. |
| **Payouts page vs `mark_paid!`** | **wired** (manual AP) | `/admin/payout_batches` + `Fuime::PayoutBatch#mark_paid!` = current money-out. Operator `/b/:slug/payouts` exists (auth). Automated Connect Transfer path **not** live yet (originator day-1 plan accepted; not shipped). |
| **Issuing / cards** | **leftover / blocked live** | Routes `/b/:slug/cards`. `Fuime::Features.card_issuing_permitted?` → false when live Stripe and `FEATURE_SPONSOR_BANKING` off. Flipper `fuime_cards_2026_08_04` for Connect cards profile still in payment setups code (MoR-redirected). |
| **Webhooks** | **wired** (endpoint present) / **unknown** (handler E2E) | `POST /fuime/webhooks/stripe` and `/fuime/webhooks/stripe/connect` → **403** without signature (alive). MoR docs historically: webhook→ledger not fully proven end-to-end. |
| **Customer portal / billing** | **wired** (platform) | `/my/billing` auth-gated. Family plan / billing on platform Stripe account (not Connect). Exact Customer Portal deep-link behavior **unknown** without login. |
| **Stripe Dashboard / Connect Express UI for operators** | **leftover** | Connect manage components still in codebase; unreachable under MoR redirect. |

---

## Guardian-owned Connect assumptions still in product

| Location | What it still says / does | Risk |
|---|---|---|
| `PaymentSetupsController` comments + `acting_guardian` | "guardian owns the money rails"; guardian = Connect account owner | Logic **retired under MoR** via redirect, but code path remains if flag off |
| Storefront `fuime-hq` (public) | "venture’s account is owned by a parent or guardian"; meta "parent as legal signer" | **Copy leftover** — contradicts MoR + day-1 Connect Transfers (guardian payout-only KYC, not seller) |
| Sold-by line | "Sold by Fuime LLC" | Wrong legal seller (should be Ninth Street Labs, LLC) — separate from Connect |
| Marketing / `fuime.com` | Still claims test mode / Connect / "money never touches us" | Compliance claim audit **BLOCK** (known) |
| Payouts → payments deep links | Historically linked into Connect setup; controller comment says payouts page walked people into guardian Connect copy | Should land on payout-method under MoR; verify no stale links bypass redirect |

---

## Classification notes

### Checkout — wired
- Live mode proven by `cs_live_` session id.
- Do **not** cite SETUP_NOTES / render.yaml alone for mode.

### Connect onboarding — leftover (safe if MoR flag on)
- Reachable URL exists but **redirects** to payout-method when MoR env is true.
- If `FEATURE_MERCHANT_OF_RECORD` were false in a deploy, guardian Connect UI would come back — treat flag as load-bearing.
- **Unknown without Render:** confirm `FEATURE_MERCHANT_OF_RECORD=true` in production (recommended if HoS needs flag proof beyond Checkout).

### Plaid / PayoutMethod — wired product, env caution
- Correct MoR destination UI.
- Sandbox Plaid under live Stripe would refuse collect per SETUP_NOTES — confirm `PLAID_ENV` / keys before demoing bank link in prod.

### Payouts / mark_paid! — wired interim
- Human AP until Stripe Connect Transfers originator ships.
- Subject to 1099-NEC hold (Compliance) before NEC-triggering `mark_paid!`.

### Cards — leftover / blocked
- Correctly refused under live keys without sponsor banking.

### Webhooks — present, E2E unknown
- Endpoints reject unsigned requests (good).
- Ledger posting from MoR PaymentIntents: treat as **unknown** until a signed test event or admin reconciliation confirms.

### Billing / portal — wired platform billing
- Not operator Connect billing.

---

## Recommended next checks (optional, needs auth or env)

1. Render / prod env: `FEATURE_MERCHANT_OF_RECORD`, `PLAID_ENV`, webhook secret present.
2. Logged-in smoke: payout-method Plaid Link opens; payments URL redirects; no guardian Connect copy in nav.
3. Signed webhook replay or Stripe dashboard recent events → ledger line for a `cs_live_` session.
4. Copy PR: storefront guardian Connect + Fuime LLC sold-by (Compliance / HoS).

---

## Escalate
- Money movement, live-mode changes, partner ToS → Head of Staff.
- Claim/copy MoR language → Compliance and Risk.
