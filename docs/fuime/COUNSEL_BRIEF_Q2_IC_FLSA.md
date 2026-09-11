# Counsel brief — Q2 Independent contractor vs employee / FLSA (minors)

**Prepared for:** payments / fintech counsel (1-hour scope)  
**Company:** Fuime LLC  
**Date:** 2026-09-11  
**Prepared by:** Head of Staff (ops), for Rushil Chopra  
**Not legal advice.** Briefing memo only.

---

## 1. Ask (what we need from the hour)

Primary question (**MOR_MIGRATION_PLAN §7 Q2**):

> Under an umbrella merchant-of-record (MoR) model where Fuime LLC is the legal seller and teens operate storefronts on the platform, are those teens properly characterized as **independent contractors / vendors**, or does the structure create **employment** (or analogous) risk under FLSA and state child-labor / wage rules — especially with an operator floor of **13**?

Deliverables we want from the call:
1. Go / no-go / modify on MoR + vendor characterization at ages **13–15** and **16–17** (split if answers differ).
2. Which product facts are load-bearing (must keep / must never add).
3. Whether guardian-as-legal-obligor + flexible bank destination is enough for clawback / contract enforceability.
4. Recommended next spend (memo vs. wait-and-see) and any cheap papering (agreement clauses).

Secondary (only if time): light read on Q1 (MTL / "own revenue") and Q4 (Stripe MoR for N operators) — not the focus of this hour.

---

## 2. Product in one paragraph

Fuime is a for-profit platform for **teen-run businesses** (services + digital goods). Customers buy through Fuime. **Fuime LLC is merchant of record**: Fuime's name on the sale, Fuime bears refunds/chargebacks, money settles to Fuime's Stripe balance, Fuime pays operators later as vendors (weekly batches, holds/reserves). Teens set their own prices and serve their own customers. A parent/guardian is linked for consent and is the **legal obligor** on operator debts / clawbacks. Destination bank account for payouts may be parent, joint, or teen, but **guardian must approve the destination before first payout**. Fuime does **not** hold customer deposits, issue cards against payables, or offer a spendable balance.

Forked from Hack Club HCB (nonprofit fiscal sponsor model). That protection does **not** transfer; MoR is the chosen for-profit structure. Risk acceptance without counsel is recorded in `docs/fuime/MOR_RISK_ACCEPTANCE.md` (active as of 2026-08-19).

---

## 3. Facts that protect the IC / vendor story (enforced in product)

| Control | Intent |
|---|---|
| Operators set their own prices; no Fuime-set or suggested rates | Avoid control / rate-setting |
| Directory is listing-not-dispatch; Fuime never assigns buyers | Avoid routing work |
| No acceptance-rate / response-time / completion metrics Fuime enforces or ranks on | Avoid performance management |
| Neutral ordering (recency / category), not quality score | Same |
| Human vetting before sell; human approval of payout runs | Risk ops, not employment |
| Services + digital only (no physical goods) | Liability / sales-tax scope |
| Payable (amount owed on a date), not stored value | Avoid money-transmitter / stored-value |
| Standing "not a bank" disclosures; forbidden bank vocabulary | Marketing law (L5) |

**Do-not-build list (product will refuse these unless counsel says otherwise):** set rates, assign/match work, rank on performance, spendable balance, cards against payables, P2P between users.

---

## 4. Facts that cut against us / open risk

1. **Fuime is the seller of record** and sets terms of sale — classic IC analysis often looks for who controls the commercial relationship.
2. **Operator floor is 13** (`FUIME_MINIMUM_OPERATOR_AGE=13`), clamped by COPPA. FLSA / state child-labor rules are stricter under 16 than 16–17. Drop from a 16 floor to 13 was made without counsel review.
3. MoR was enabled in production against a **self-assessed** risk acceptance file, not a law-firm memo.
4. Tax / TIN for 1099-NEC and assignment-of-income (whose income is it when guardian is legal payee but teen earned it) is **not yet locked**.
5. Clawbacks against minors are historically weak; we mitigate by making **guardian the obligor**, with destination flexible.

---

## 5. Payout / party model (founder lock 2026-09-11)

| Role | Who |
|---|---|
| Day-to-day operator | Teen |
| Legal obligor / clawback party | Guardian |
| Destination bank account | Parent, joint, or teen — **guardian-approved** before first payout |
| Tax identity / TIN | **Open — need counsel input** |

Question for counsel: does "guardian legal payee + teen earned the income" create nominee / assignment-of-income issues we should paper now?

---

## 6. Documents already in repo (read if useful)

- `docs/fuime/MOR_MIGRATION_PLAN.md` — plan of record; §0.2 MoR theory; §7 Q1–Q4; §8 launch shape
- `docs/fuime/MOR_RISK_ACCEPTANCE.md` — active self-acceptance; Q2 called highest risk
- `docs/fuime/LEGAL_RESEARCH.md` — AI research brief (not advice); §1 minors running businesses / FLSA danger zones
- `docs/fuime/WHOP_EVALUATION.md` — substrate decision: stay on Stripe

---

## 7. Specific yes/no we need

1. At **16–17**, is current MoR + vendor + listing-not-dispatch posture defensible enough to continue live volume?
2. At **13–15**, same — or must we raise the sell floor to 16 pending more work?
3. Must payouts go only to guardian-owned accounts, or is guardian-approved teen/joint destination OK if guardian remains obligor?
4. Any mandatory agreement clauses (guardian guaranty, ratification, FLSA acknowledgements) we should add before next payout batch?
5. Rough risk ranking: proceed / proceed with papering / pause live MoR until memo.

---

## 8. Out of scope for this hour (flag only)

- Full 50-state MTL survey (Q1)
- Stripe ToS negotiation (Q4) — we will ask Stripe separately
- Sales-tax nexus registration build (data already captured)
- Becoming a bank / sponsor-bank FBO

---

## 9. Contact / next step after call

Replace `FUIME_MOR_COUNSEL_MEMO` env cite from `MOR_RISK_ACCEPTANCE.md` with the real memo reference when one exists. Until then the boot guard intentionally points at the self-assessment.
