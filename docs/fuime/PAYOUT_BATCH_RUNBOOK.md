# Fuime MoR payout batch runbook

**Owner:** Banking Ops (run) · Compliance (policy) · Head of Staff (escalation)  
**Repo:** `github.com/agathonapp/fuime`  
**Status:** Day-1 operator runbook. Originator not yet wired — `mark_paid!` is the live path.  
**Related:** `docs/fuime/MOR_RISK_ACCEPTANCE.md`, `PAYOUT_DESTINATION_SPEC.md`, `MOR_MIGRATION_PLAN.md` §7 Q3

---

## Architecture lock (do not re-decide mid-run)

| Leg | Rule |
|---|---|
| Money-in | **MoR on Fuime platform Stripe account.** Charges settle to Fuime. No Connect for operators-as-MoR. `FEATURE_MERCHANT_OF_RECORD` live under self-assessed `MOR_RISK_ACCEPTANCE` / `FUIME_MOR_COUNSEL_MEMO`. |
| Money-out | Ordinary AP (vendor payable). Not a bank balance, not stored value. |
| Day-1 originator (accepted, not wired) | Stripe Connect **Transfers + Payouts** to guardian external banks via Plaid Auth tokens. |
| Connect account owner | **Adult guardian only.** Teen is **never** the Connect account owner / Representative. |
| Selling vs payout KYC | Selling stays MoR on the platform account. Guardian SSN / identity collection is **PAYOUT-ONLY onboarding** — never gate selling on it. |
| Mercury | Backup only, after written ToS clearance. Not day-1. |
| Slash | Deprioritized. Do not plan runs around it. |
| Kill list | Spendable Fuime balance · P2P · cards against payable · crypto wallets · BaaS/FDIC claims · `FEATURE_SPONSOR_BANKING` |

**Hard ops rules for this runbook**

- No partner emails (Stripe / Mercury / Slash / Plaid sales or support threads) as part of a batch run.
- No live money-movement command recipes here. When the Stripe originator ships, a separate originator playbook will cover API/console steps under Head of Staff sign-off.
- Do not invent 1099 / TIN identity. Tax party = **TBD with Compliance**.
- Escalate any money movement or live-mode flip to **Head of Staff**.

---

## 1. Preconditions / go-no-go checklist

Run this before generating a batch. Any NO = stop.

| # | Check | How | Go? |
|---|---|---|---|
| 1 | MoR flag + memo cite present | `FEATURE_MERCHANT_OF_RECORD` on; `FUIME_MOR_COUNSEL_MEMO` cites `MOR_RISK_ACCEPTANCE` (or real counsel memo if replaced) | |
| 2 | Boot safety | App boots past `config/initializers/fuime_safety_check.rb` (check 6) | |
| 3 | Not sponsor banking | `FEATURE_SPONSOR_BANKING` **off** / unused | |
| 4 | Stripe mode known | Confirm `StripeService.mode` (or equivalent). Live-mode flips → Head of Staff | |
| 5 | Platform balance covers proposed gross outflows + reserve | Stripe platform balance vs batch total (UNKNOWN exact dashboard path — use Finance Stripe login) | |
| 6 | Open chargebacks / refunds queue reviewed | UNKNOWN tooling name — review open disputes that would debit payables | |
| 7 | Policy freeze available | `Fuime::PayoutPolicy` snapshot will be frozen on the batch | |
| 8 | Operator eligibility | Vetted (`Event#operator_vetting_status` or current equivalent); age ≥ `FUIME_MINIMUM_OPERATOR_AGE` | |
| 9 | Guardian linked as legal obligor | Every line has a guardian obligor record | |
| 10 | Destination approved + Plaid-verified | See §4 | |
| 11 | Tax/TIN | Do **not** block on inventing 1099 identity. If Compliance has issued interim guidance, follow it; else proceed with payable bookkeeping only and flag tax UNKNOWN | |
| 12 | Escalation contact reachable | Head of Staff available for stop / clawback / live-mode | |

**NO-GO if:** kill-list product on, guardian missing, destination unapproved, policy cannot freeze, or anyone proposes teen as Connect owner.

---

## 2. Weekly batch generation steps

Cadence: **weekly** (day UNKNOWN — pick and stick; document in batch notes).

1. Confirm go-no-go (§1) passed; record date, operator count estimate, Stripe mode in the batch ticket.
2. Generate candidate payables via `Fuime::PayoutBatchService` (console/admin entrypoint UNKNOWN — use the service, not ad-hoc SQL).
3. Freeze holds/caps from `Fuime::PayoutPolicy` onto the batch at generation time (do not recompute mid-approval with drifting numbers). Assessment helpers may also touch `Fuime::PayableAssessment` — treat policy freeze as source of truth for the run.
4. Exclude lines that fail §3 or §4; remainder stays payable / rolls.
5. Export review sheet: operator, guardian, destination last4 / method id, gross earned, hold, reserve, cap trim, net proposed, notes.
6. Attach policy freeze snapshot + review sheet to the run record.
7. Hand to human approver (§5). Do not mark paid yet.

---

## 3. Hold / reserve / cap assessment

Frozen per batch via `Fuime::PayoutPolicy`:

| Control | Value | Behavior |
|---|---|---|
| Hold | **7 days** | Sale not payable until hold clears |
| Rolling reserve | **10%** over **90-day** window | Withheld from payable; release per policy window |
| Cap | **$2,500 / operator / run** | Excess **rolls** to later runs — do not invent side channels |
| Floor | **$10** | Below floor → skip / roll; do not pay dust |

Ops checks on the review sheet:

- [ ] Every line’s hold age ≥ 7 days (or correctly excluded).
- [ ] Reserve math matches frozen policy (spot-check 2–3 high-volume operators).
- [ ] No operator net > $2,500 in this run; remainder visible as rolled.
- [ ] No line < $10 proposed for payment.
- [ ] Refunds/chargebacks already applied to payable before net (Fuime bears buyer refunds; payable is debited — do not “make the teen whole” outside ledger).

If policy constants in code disagree with this table, **stop** and escalate — do not silently prefer one.

---

## 4. Guardian destination + approval verification

Per destination lock (`PAYOUT_DESTINATION_SPEC`):

| Field | Rule |
|---|---|
| Legal payee / clawback obligor | **Guardian** |
| Day-to-day operator | Teen |
| Destination account | Parent, joint, **or** teen bank — not parent-only |
| First-payout gate | Guardian **must approve** destination before first payout |
| Verification | Plaid Auth (or equivalent) on destination; Plaid does not move money |
| Method model | Prefer `LegalEntity::PayoutMethod::BankAccount` (or current Fuime wrapper) linked to guardian legal entity |

Per line, verify:

1. Guardian obligor present and linked to the venture/operator.
2. Destination method exists, Plaid-verified, not revoked.
3. Guardian approval timestamp **before** this (or first) payout.
4. Review sheet shows method id / last4 — never paste full account/routing into Slack/email.
5. Copy on any operator-facing note: “amount owed, paid to the approved account on ___” — never imply Fuime holds a deposit.

### FLAG — PAYOUT-ONLY onboarding (identity / KYC)

These steps collect **guardian** identity for **money-out / Connect payout rail only**. They are **not** selling onboarding and **not** MoR checkout KYC.

| Step | FLAG |
|---|---|
| Collect guardian legal name / DOB for Connect Custom account | **PAYOUT-ONLY onboarding** |
| Collect guardian SSN (or last-4 / full as Stripe requires) | **PAYOUT-ONLY onboarding** — teen SSN is never the Connect identity |
| Stripe Identity / KYC refresh on guardian | **PAYOUT-ONLY onboarding** |
| Create/update Stripe Connect account with guardian as owner/Representative | **PAYOUT-ONLY** · teen ≠ owner |
| Attach Plaid Auth token → external bank on Connect account | **PAYOUT-ONLY** |
| Enable payouts on that Connect account | **PAYOUT-ONLY** · still no live transfer instructions in this runbook |

Selling (MoR charges on platform) must continue without waiting on the above. If product UI conflates the two, file a bug — do not block storefront publish on payout KYC.

Tax / TIN for 1099: **UNKNOWN / Compliance** — do not invent whose TIN is collected during payout KYC.

---

## 5. Human approval of the run

Every run requires a human assertion before any `mark_paid!` or future originator call.

Approver checklist:

- [ ] §1 go-no-go signed in the ticket.
- [ ] Review sheet totals match `Fuime::PayoutBatchService` output.
- [ ] §3 hold/reserve/cap frozen values accepted.
- [ ] §4 destination + guardian approval verified for every included line.
- [ ] Kill-list items absent from the run design.
- [ ] No teen listed as Connect owner on any future-originator prep row.
- [ ] Approver name + timestamp recorded on the batch.

**Approver role:** UNKNOWN formal title — default Banking Ops lead; if absent, Head of Staff.  
**Dual control:** preferred but UNKNOWN whether coded — if not in product, second human on the ticket.

Rejection: remove bad lines, regenerate or amend batch, do not partial-pay silently outside the service.

---

## 6. Execution paths

### 6A. CURRENT PATH — `mark_paid!` (stand-in until originator wired)

**Label: CURRENT / LIVE STAND-IN**

1. After §5 approval, execute AP out-of-band by the approved means (manual bank send / book transfer — **details UNKNOWN; not specified here**). Record external payment reference (bank confirmation id).
2. In app, call `mark_paid!` (via `Fuime::PayoutBatchService` or payable model — exact receiver UNKNOWN) **only** after money has left (or concurrently with documented AP proof).
3. `mark_paid!` is a **human assertion** that the vendor payable was settled — not proof Stripe moved funds.
4. Store: batch id, payment reference, approver, amount, destination method id.
5. If AP fails after `mark_paid!`, treat as incident → §7 clawback / correction; do not “fix” by issuing a second payment without Compliance.

Do **not** paste live credentials, account numbers, or partner-portal clickpaths into the ticket.

### 6B. FUTURE PATH — Stripe Connect Transfers + Payouts (accepted day-1 design, not wired)

**Label: FUTURE / NOT WIRED — no live money-movement instructions**

Design constraints (for when Engineering ships the originator):

1. Platform MoR charge stays on Fuime’s Stripe account (unchanged).
2. Guardian has a Connect **Custom** (or API-connected) account where **guardian is the individual owner** — never the teen.
3. Plaid Auth token funds the external bank on that Connect account (**PAYOUT-ONLY** KYC complete first — §4).
4. Batch execution (high level only): Transfer from platform balance → guardian Connect account → Payout to external bank. Exact API sequence, idempotency keys, and webhook handlers = UNKNOWN until originator PR + Head of Staff live-mode approval.
5. Ledger: originator success webhooks should drive paid state; keep `mark_paid!` as manual override/break-glass only if product preserves it.
6. Enabling this path in production = **money movement / live-mode flip → escalate to Head of Staff** before first real Transfer.

**Mercury:** backup note only — usable only after written ToS clearance. Not in weekly happy path.  
**Slash:** deprioritized — do not staff or sequence runs on it.

---

## 7. Failure / clawback notes

Point to **Compliance** and `MOR_MIGRATION_PLAN.md` §7 **Q3**. Do not invent legal certainty.

| Situation | Ops action | Legal posture |
|---|---|---|
| Buyer refund / chargeback after payable accrued | Debit operator payable / net against future payables per product rules | Fuime owes the buyer; operator payable drops |
| Overpayment / duplicate `mark_paid!` | Stop further pays to that operator; open incident; notify Head of Staff + Compliance | Recovery path UNKNOWN — Compliance |
| Destination wrong but guardian-approved | Treat as guardian-directed; still open Compliance ticket | Obligor = guardian per destination lock |
| Guardian disputes clawback | Escalate Compliance; freeze future payouts to that obligor | Enforceability of clawbacks vs minors historically weak — **why guardian is obligor**; counsel answer still open (Q3) |
| Stripe dispute / account risk on platform | Head of Staff; pause batch generation | Not a teen Connect issue on MoR money-in |
| Suspected fraud / mule destination | Kill line; Compliance; do not tip off via partner email threads from this runbook | — |

**Do not:** promise families FDIC, “funds safe with Fuime,” or guaranteed clawback success.  
**Do:** keep payable language (“amount owed on a date”).

---

## 8. Reconciliation checklist

After the run (same day or next business day):

- [ ] Batch status = paid / closed in app for included lines only.
- [ ] Sum(`mark_paid!` amounts) == sum(AP payment references) ± documented fees (fee handling UNKNOWN — note explicitly).
- [ ] Rolled amounts (cap / floor / hold) still visible as unpaid payables — not dropped.
- [ ] Reserve balances still reconcile to `Fuime::PayoutPolicy` window.
- [ ] Stripe platform balance movement (if any) explained; under CURRENT path, platform balance may be unchanged if AP paid from operating account — record which cash account funded AP (**UNKNOWN default account**).
- [ ] No orphan paid flags without payment reference.
- [ ] No payment reference without paid flag.
- [ ] Destination method ids on paid lines still match §4 sheet (detect swaps).
- [ ] File batch packet: go-no-go, review sheet, policy freeze, approvals, payment refs, recon sign-off.
- [ ] Tax lot / 1099 export: **skip inventing** — hand Compliance a payable extract if they ask.

---

## 9. Escalation matrix

| Trigger | Escalate to | Stop batch? |
|---|---|---|
| Any live money movement beyond approved CURRENT AP path | **Head of Staff** | Yes until approved |
| Live-mode Stripe flip / originator enable | **Head of Staff** | Yes |
| Proposal to make teen Connect owner / Representative | **Head of Staff** + Compliance | Yes |
| `FEATURE_SPONSOR_BANKING` or BaaS/FDIC copy suggested | Compliance + Head of Staff | Yes |
| Policy constant mismatch vs this runbook | Engineering + Banking Ops; Head of Staff if pay amounts affected | Yes |
| Chargeback spike / platform account warning | Head of Staff | Pause new runs |
| Clawback / guardian dispute / overpay | Compliance (Q3); Head of Staff if > UNKNOWN $ threshold | Freeze that obligor |
| Tax/TIN / 1099 questions from families | Compliance only — do not answer from ops lore | Soft block messaging |
| Plaid or bank verification failure blocking many lines | Banking Ops; Compliance if systemic | Pay only clear lines |
| Partner outreach (Stripe/Mercury/Slash) needed | Head of Staff — **no partner emails from runners** | N/A |

---

## Quick reference — classes & env

| Name | Role |
|---|---|
| `FEATURE_MERCHANT_OF_RECORD` | MoR money-in |
| `FUIME_MOR_COUNSEL_MEMO` | Boot guard cite (self-assessed until real memo) |
| `MOR_RISK_ACCEPTANCE` | Active self-assessment |
| `Fuime::PayoutPolicy` | Hold / reserve / cap / floor; freeze per batch |
| `Fuime::PayableAssessment` | Assessment helper (see MOR docs) |
| `Fuime::PayoutBatchService` | Batch generation / run orchestration |
| `mark_paid!` | Human-paid assertion (CURRENT path) |
| `LegalEntity::PayoutMethod::BankAccount` | Destination method type |
| `FUIME_MINIMUM_OPERATOR_AGE` | Age floor (13) |
| `FEATURE_SPONSOR_BANKING` | **Must stay off** for this flow |

---

*End of runbook. Amendments require Head of Staff + Compliance ack when they change money movement, party model, or policy numbers.*
