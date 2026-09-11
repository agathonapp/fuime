# Payout destination spec — founder lock 2026-09-11

**Status:** locked (product + compliance)  
**Owner:** Banking Ops + Compliance  
**Related:** `MOR_RISK_ACCEPTANCE.md` §3 recommendation; `MOR_MIGRATION_PLAN.md` §4.3 / §7 Q3

## Lock

| Field | Rule |
|---|---|
| Legal payee / clawback obligor | **Guardian** |
| Day-to-day operator | Teen |
| Destination bank account | Parent, joint, **or** teen — not restricted to parent routing numbers |
| First-payout gate | Guardian must **approve** the destination before the first payout |
| Verification | Plaid Auth (or equivalent) on the destination; Plaid does not move money |
| Originator | Still open: Slash / Mercury / Stripe (see §4.3 diligence) |
| Tax / TIN | **Not locked** — needs counsel + product decision |

## Product implications

1. Onboarding: collect guardian as obligor; collect destination separately; require guardian approval step.
2. Do not require the destination account holder name to match the guardian if the bank accepts the account and guardian approved — but record who owns it when known.
3. Operator UI: "amount owed to you, paid to the approved account on ___" — never imply a bank deposit held by Fuime.
4. Clawback / dispute: net against future payables; guardian remains the contractual obligor when payables are insufficient.
5. Specs should assert: no payout without an approved destination + linked guardian obligor.

## Explicit non-goals

- Spendable Fuime balance
- Cards issued against payables
- P2P between operators
- Paying without guardian approval of destination
