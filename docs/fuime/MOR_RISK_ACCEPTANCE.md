# Merchant-of-record risk acceptance — self-assessed, no counsel review

**Status: ACTIVE. Recorded 2026-08-19 by Rushil Chopra, sole operator of Fuime LLC.**
**This document is what `FUIME_MOR_COUNSEL_MEMO` points at. It is NOT a legal opinion.**

> ## Read this first
>
> `config/initializers/fuime_safety_check.rb` check 6 refuses to boot with
> `FEATURE_MERCHANT_OF_RECORD` enabled unless `FUIME_MOR_COUNSEL_MEMO` cites something.
> The guard was written expecting a counsel memo. **There is no counsel memo.** Fuime is
> bootstrapped and no attorney has reviewed this structure.
>
> Rather than put a plausible-looking law-firm reference into a production environment
> variable — which would make the system assert a review that never happened, and mislead
> whoever reads it next — the variable cites this file. Anyone who follows the reference
> learns the true state, which is the whole point of the guard existing.
>
> **If you are reading this after a lawyer has looked at the structure, replace the env var
> with the real memo reference and move this file to a historical section.** Until then it
> stands as written.

---

## 1. What Fuime is doing

Fuime LLC (EIN obtained; no attorney of record) operates as **merchant of record**:

- A customer buys a service through Fuime. Fuime LLC is the seller.
- The money lands in Fuime's own Stripe balance (live mode as of 2026-08-19).
- Fuime keeps 5% and pays the teen operator the remainder later, as a vendor.
- Operators are 13–17 (`FUIME_MINIMUM_OPERATOR_AGE=13`, hard-clamped at 13 by COPPA/L6).

The legal theory, from `LEGAL_RESEARCH.md` and `MOR_MIGRATION_PLAN.md` §0.2, is sound in
outline: **you are not a money transmitter when you receive your own revenue.** If Fuime is
genuinely the seller — Fuime's terms of sale, Fuime's name on the receipt, Fuime bearing the
refund and chargeback obligation — then the customer pays Fuime for a product Fuime sold, and
paying the operator afterwards is Fuime paying its own vendor. No third-party funds are
transmitted. Paddle, FastSpring, Lemon Squeezy and Whop all operate this way.

## 2. What is accepted, question by question

These are `MOR_MIGRATION_PLAN.md` §7 Q1, Q2 and Q4 — the questions that document says the
memo has to answer. Nobody has answered them. Here is the founder's assessment of each,
recorded so the acceptance is specific rather than a shrug.

### Q1 — Does the structure take the collection leg outside 18 U.S.C. § 1960 and state MTL?

**Assessed risk: moderate, and materially reduced by the documents shipped alongside this
file.** The theory is well established and the architecture matches it. The weakness was never
the code — it was that until 2026-08-19 the seller-of-record claim appeared **only in
operator-facing and admin copy**. The buyer, the one party the argument is actually about, saw
nothing. That is now fixed: the storefront and payment page name Fuime LLC as seller, and the
terms carry a sale-and-refunds section placing the refund and chargeback obligation on Fuime.

**Residual risk accepted:** state money-transmitter analysis is state-by-state and has not
been done. Fuime is not registered as an MSB with FinCEN. The position rests on the
"own revenue" characterisation being correct, which has not been tested.

### Q2 — Does umbrella MoR break the independent-contractor characterisation?

**Assessed risk: HIGHEST OF THE THREE. This is the one to get reviewed first.**

`LEGAL_RESEARCH.md` §1 warns against Fuime looking like the operators' employer. Under MoR
Fuime is the seller setting terms of sale, which makes the vendor characterisation harder to
defend. If it fails, this is FLSA child-labor territory rather than a tax question — and the
operator floor is now **13**, where FLSA restrictions are far stricter than at 16.

**What protects the position, and is enforced in code rather than asserted in a document:**

- Operators set their own prices. There is no Fuime-set or Fuime-suggested rate anywhere, and
  `spec/views/fuime/payables_copy_spec.rb` greps rendered HTML to keep it that way.
- Fuime never routes a customer to an operator. The directory is a listing, not a dispatch
  (`MOR_MIGRATION_PLAN.md` §8.3 D2).
- No acceptance-rate, response-time or completion metric that Fuime enforces or ranks on.
- Ordering is neutral — recency or category, never a quality score.

**Do not add anything that sets rates, assigns work, or ranks operators on performance.**
Those are the exact facts an examiner looks for, and each one is cheap to add by accident.

**Residual risk accepted in full.** No attorney has assessed whether the above is sufficient,
and the drop from a 16 floor to 13 was made without review.

### Q4 — Will Stripe permit one account as MoR for N third-party operators?

**Assessed risk: business rather than legal.** This is adjacent to Stripe's restriction on
"payment facilitation and aggregation on behalf of third-party sellers." Stripe has not been
asked. Worst case is an account freeze, which would be recoverable but would land mid-event.

**Residual risk accepted.** Do not misdescribe the model to Stripe if they ask.

## 3. Deliberately NOT relied on: the Founders School precedent

The founder noted that a school runs a business simulation where the school holds student
sales revenue and pays out parents, and that this appears to work.

**That is not authority for Fuime's position, and this document does not lean on it.** A
school holding money for its own enrolled students inside an educational program has an
enrollment contract with those families and an educational framing; Fuime is a for-profit
platform selling to the public on behalf of many unrelated families under terms of service.
"Appears to work" also means "has not been challenged," which is not the same as compliant.

**One idea from it IS worth adopting, and is recorded here as an open recommendation:
that program pays the PARENT, not the minor.** Paying an adult defuses much of both Q2 and
the contract-voidability problem (L2 — a minor's contract is voidable, and under 14 arguably
void), because the party receiving money can actually contract. Fuime currently pays the
operator, and PR #70 deliberately removed the guardian requirement from *selling* while
keeping it at *payout*. Making the guardian the payee — not merely the approver — is the
single cheapest risk reduction available and should be considered before payouts open the
week of 2026-08-24.

## 4. Measures actually in place

| Control | Where |
|---|---|
| Services **and digital** — no physical goods, so no product liability. **Sales-tax nexus on digital is now accepted, see §7** | `Fuime::OperatorEligibility#category_blocker`, fails closed on blank |
| Human vetting of every operator before they may sell | `Event#operator_vetting_status` |
| Human approval of every payout run | `Fuime::PayoutBatchService`, `mark_paid!` is a human assertion |
| 7-day hold + 10% rolling reserve over a 90-day window | `Fuime::PayableAssessment` |
| Under-13 refused at signup | `User` validation, per L6 |
| No "bank/banking/FDIC" vocabulary | L5, enforced by a spec sweeping mailers and helpers |
| Standing "not a bank" disclosure on every page | `app/views/application/_footer.html.erb` |
| Fuime named as seller to the buyer | storefront, payment page, terms §8 — **new 2026-08-19** |
| Fuime named as seller to the OPERATOR, in plain language | offers page and payouts page — **new 2026-08-19**. Covers: you set your own price, Fuime is the legal seller, 14-day refunds, a refund debits your payable, chargebacks are Fuime's, payment problems go to support@fuime.com |
| Refund window | **14 days, confirmed by the founder 2026-08-19.** Stated in terms §8 and in the operator disclosure. No code reads it |

## 5. What would change this document

1. **An hour with a payments/fintech attorney on Q2.** Roughly $300–600, often available
   within days. Cheaper routes: state bar lawyer-referral service, or a small-business law
   clinic at a nearby law school (frequently free, and used to exactly this).
2. **Stripe's own answer on Q4** — a support conversation, not a legal spend.
3. **Making the guardian the payee** (§3 above).

When (1) happens, replace `FUIME_MOR_COUNSEL_MEMO` with the real reference.

## 6. Acceptance

The founder has read the above, understands that Q2 in particular is unreviewed and carries
FLSA child-labor exposure at a 13-year floor, and is proceeding for Founders Weekend
(2026-08-21) on that basis. Recorded 2026-08-19.

**Confirmed by the founder on 2026-08-19, in order:** the 14-day refund window; that the
arrangement must be disclosed to the teen seller in plain language, not only in the terms
(built the same day); and the instruction to enable `FEATURE_MERCHANT_OF_RECORD` in production
so the platform can be tested end to end. `FUIME_MOR_COUNSEL_MEMO` was set to cite this file
at the same time.

**Declined, deliberately:** a Whop-style spendable "Fuime balance". `WHOP_EVALUATION.md` §3
establishes that Whop's balance is a **USDT stablecoin position in a self-custodial wallet**,
not dollars — which would put a crypto-custody problem under a product for minors and make
"deposit", "insured" and "your money is safe" affirmatively false rather than merely
unlicensed (L5). Fuime keeps a **payable** — an amount owed, paid on a stated date — which is
ordinary vendor debt and needs no licence. The line that must not be crossed: indefinite
holding, spending directly from the figure, transfers between users, or issuing a card against
it. Any of those is stored value whatever the label says.

**The next thing to do is still one hour with a payments attorney on Q2**, not more code.

---

## 7. Scope change 2026-08-20: digital products are now allowed

**Decided by the founder, recorded here because it moves a risk rather than removing one.**

`ELIGIBLE_CATEGORIES` was `%w[services]`; it is now `%w[services digital]`. The driver is that
the archetypal Founders Weekend business is a teenager who vibecodes a site and sells access to
it — the example given was a real one, an AI drill-plan tool billing $9.99/month that had made
$200. Under services-only that founder could not have published at all.

**What this does not cost.** Two of the three reasons physical goods are excluded never applied
to digital: there is no product liability on a file, and no shipping.

**What it does cost, precisely.** Roughly 30 states tax digital goods and SaaS. Under
merchant-of-record that nexus accrues against **Fuime's single entity**, not against fifty
individual teenagers — which is the whole reason the original note deferred this to §8.5 phase 8.
Fuime is not registered to collect or remit anywhere.

**Why this is recoverable rather than a one-way door, and this is the part that made it
reasonable to say yes:** the data needed to compute that nexus is **already being captured.**
`Fuime::PaymentLinkService` sets `billing_address_collection: "required"` on every MoR checkout
for exactly this reason — nexus is measured on history and history cannot be backfilled. So what
is outstanding is registration and remittance, which can be built later *from stored data*.
Opening the category incurs a reporting obligation to catch up on; it does not destroy the
evidence needed to catch up.

**Action this creates, and it has a clock:** economic-nexus thresholds are commonly $100K in
sales or 200 transactions per state per year. At fifty operators that is not immediate, but it is
also not far away, and the obligation attaches from the transaction that crosses it rather than
from the day somebody notices. **Build the nexus report off `billing_address` before volume, not
after.**

## 8. Not enabled by §7: monthly subscriptions

The same conversation asked for operator subscriptions. **They do not exist and were not added.**
`Fuime::Offer` has no recurring concept and `Fuime::PaymentLinkService` uses `mode: "payment"`;
`Fuime::SubscriptionService` is Fuime's *own* family-plan billing on the platform account, not a
facility for operators to bill their customers. So an operator can sell **one-time** access to a
digital product and cannot yet bill monthly for it.

Not attempted the night before a real-money launch, deliberately. Recurring billing means invoice
webhooks reaching the ledger, dunning on a failed card, proration, cancellation, and each of those
touching a teenager's earnings figure. A half-built subscription that charges a stranger's card
every month and does not post to the ledger is a worse outcome than not offering subscriptions.
Scoped as the first post-Founders-Weekend feature.

