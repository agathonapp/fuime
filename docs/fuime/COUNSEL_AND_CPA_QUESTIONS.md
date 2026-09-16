# Questions for counsel and for the CPA

**2026-09-16, written ahead of a public waitlist launch.** Two separate conversations
with two separate people. Do not merge them — the lawyer's answers change what the
product may do; the CPA's answers change what gets recorded and filed, and a few of
them are already accruing whether or not anyone asks.

**Bring to both:** `MOR_RISK_ACCEPTANCE.md` (what was accepted, unreviewed, and why),
`COUNSEL_BRIEF_Q2_IC_FLSA.md` (already written as a 1-hour briefing memo — send it
before the call, it does most of the setup), and one sentence of product: *a for-profit
platform where 13–17-year-olds sell services and digital products; Fuime LLC is the
merchant of record; money lands in Fuime's Stripe balance and operators are paid later
as vendors; a guardian is required to approve a payout but not to sell.*

**The three facts that shape every answer below:**

1. Fuime is the **seller of record**, not a payment conduit. That is the whole
   money-transmission defence (`MOR_RISK_ACCEPTANCE.md` §2 Q1).
2. The operator floor is **13** (`FUIME_MINIMUM_OPERATOR_AGE`, hard-clamped), and age
   is a self-attested checkbox — no DOB verification, no ID.
3. Until now every operator was hand-picked at a cohort weekend. **A public launch
   removes that filter**, and several answers below were sized against a room of people
   Rushil knew by name.

---

## Part 1 — Counsel (payments / fintech, ideally with an employment-law read)

Ordered by what a wrong answer costs. If the hour runs out, stop at Q3.

### Q1. Independent contractor or employee? (the one that matters most)

Full brief: `COUNSEL_BRIEF_Q2_IC_FLSA.md`. Ask specifically:

- Under umbrella MoR — Fuime is the legal seller, sets terms of sale, bears refunds and
  chargebacks — are operators properly **vendors**, or does this read as employment?
- **Split the answer at 16.** FLSA non-hazardous rules are far looser at 16–17 than at
  13–15. If the answer differs, we raise the floor back to 16 in one env var.
- Which of our existing controls are actually load-bearing? Today: operators set their
  own prices, the directory lists but never assigns or matches, no acceptance-rate or
  completion metrics, neutral ordering. **What must we never add?**
- Does a public launch change this, versus a curated cohort? (More operators, none of
  them known to us.)
- If this fails, is the exposure back taxes and penalties, or child-labor enforcement?

### Q2. Who is the contracting party, and is anything we hold enforceable?

- A teen clicks the operator sale terms and starts selling; the **guardian is only
  required at payout**. Is a minor's clickwrap enough to make Fuime the seller of
  record as against *the buyer*, given the teen's own agreement is voidable (infancy
  doctrine)?
- Should the guardian be required **before first sale** rather than before first payout?
  That is a product change we can make in a day; we need to know if it's necessary.
- **Negative payable / clawback**: a chargeback lands after we've paid an operator. The
  debt is owed by a minor. Who do we actually collect from — the guardian as
  countersigned obligor, or does Fuime absorb it? `MOR_RISK_ACCEPTANCE.md` §3 recommends
  the guardian; nobody has drafted it.
- **Should the guardian be the payee rather than the teen?** This is the cheapest single
  risk reduction available (it defuses part of Q1 and most of voidability) and it is
  currently unbuilt. Payouts are being wired this week, so the answer is timely.

### Q3. Money transmission — confirm or break the "own revenue" theory

- Does Fuime-as-seller-of-record take the collection leg outside 18 U.S.C. § 1960 and
  state MTL? Our position: we receive **our own revenue** and later pay a vendor, the
  way Paddle and Lemon Squeezy do.
- Which states, if any, would look at a **7-day hold plus a 10% rolling reserve over 90
  days** and call the retained amount stored value rather than an ordinary trade payable?
  The reserve is the part that looks least like AP.
- Do we need to register as an MSB with FinCEN? We have not.
- What is the trigger that would change the answer — volume, hold length, an operator
  being able to spend from the figure? (We already refuse a spendable balance, P2P, and
  cards against a payable.)

### Q4. The public launch specifically

- **Age attestation.** Under-13 is refused, but only by a checkbox. At public scale, is
  self-attestation a defensible COPPA posture, or do we need an age-assurance step?
- **Advertising.** L7 bans targeted advertising and profiling of minors (CT, TX SCOPE,
  NY CDPA). Confirm: paid acquisition targets parents only, transactional-only email to
  minors, no algorithmic feed. Does a public launch add anything here?
- **Marketing copy.** We forbid bank/banking/FDIC/deposit vocabulary and carry a standing
  "not a bank" disclosure on every page. A recent internal review found that disclosure
  renders at roughly **1.7:1 contrast** — is a disclosure that fails accessibility
  guidance still "clear and conspicuous"? (Cheap to fix; want the standard.)
- **What we sell for other people.** Fuime is the seller of record for whatever a vetted
  teen lists. What diligence standard applies to us, and what categories should be
  refused outright? Today: services and digital only, human vetting before selling.
- **Terms, Privacy, Guardian Agreement** are Fuime-written, not counsel-drafted. The
  versioning plumbing is real (version + IP + UA + timestamp recorded at signature).
  What is the minimum set to have reviewed before strangers sign them, and what does
  that cost?

### Q5. Housekeeping worth five minutes

- Is a single-member LLC enough, and does the §1960 exposure reach the member personally?
- What insurance should be bound before a public launch — E&O, cyber, general liability?
- If a state regulator or Stripe calls, what is the one-page description of the model we
  should have ready, and who says it?

---

## Part 2 — CPA

Two of these have already started accruing. Lead with them.

### C1. Gross or net? (this one changes the tax return and the P&L)

Under MoR, customer money lands in Fuime's own Stripe balance and Stripe will issue
Fuime a **1099-K for the full GMV**, not for the 5%.

- Do we book **gross revenue with operator payouts as cost of revenue**, or **net 5%**?
- Which is correct given Fuime is the legal seller — and does the answer differ for the
  tax return versus how we describe revenue to an investor?
- If gross: Fuime's stated revenue is ~20× the economic reality. What do we need in the
  books so that reads correctly?

### C2. Sales tax nexus on digital goods — the one with a clock

Digital products were allowed from 2026-08-20. Roughly 30 states tax digital goods and
SaaS, and under MoR that nexus accrues against **Fuime's single entity**, not against
fifty individual teenagers. Fuime is registered nowhere.

- Does Fuime qualify as a **marketplace facilitator** in these states, and does that
  change who collects and remits?
- Economic-nexus thresholds are commonly $100K or 200 transactions per state per year.
  At what point in a public launch do we cross one, and does the obligation attach from
  the crossing transaction or from registration?
- **We are already capturing the data**: billing address is required on every checkout
  and stored per sale (`fuime_sales` has country, state, postal code, amount, date).
  What report do you want off it, and how often?
- What does catching up look like if we cross a threshold before registering?

### C3. 1099s to operators, and whose income this is

- Operators are paid as vendors. Threshold, form (**1099-NEC**), and timing?
- **Who is the payee** — the minor or the guardian? We are deciding this right now for
  the payout build. If we pay the guardian for work the teen performed, whose income is
  it, and does assignment-of-income doctrine bite?
- **W-9 from a minor**: can a 13-year-old furnish one? Does the guardian sign? What do we
  do about **backup withholding** when no TIN is furnished — we currently have no TIN
  collection at all in the payout path.
- Does the teen's income go on **Schedule C with self-employment tax at $400** of net
  earnings? The app's `/taxes` page asserts exactly this to families and it has never
  been reviewed by anyone qualified (`LAUNCH_SPEC.md` §1.6 has wanted your sign-off since
  August). **Please read that page and tell us what is wrong.**
- Kiddie tax — does it reach earned income here, or only unearned?

### C4. How to keep the books so this is not a mess in April

- The **payable subledger**: what a teen is owed, per operator, with holds and the 10%
  rolling reserve applied. Is the reserve a liability on our books?
- Refunds and chargebacks: Fuime bears them as merchant of record and debits the
  operator's payable. What is the right treatment, and does it change if we eat one?
- **Unclaimed payables** — an operator stops responding and never links a bank account.
  At what point is that escheat / unclaimed property, and in which state?
- Stripe's processing fee is **Fuime's cost**, not passed to the operator (that is a
  pricing promise, 5% + 50¢ all-in). Confirm the expense treatment.
- Estimated taxes and the filing calendar for a single-member LLC with an EIN.

### C5. What to bring

Read-only access to the Stripe account, the `/taxes` page, `MOR_RISK_ACCEPTANCE.md` §7
(the digital-goods scope change and what it costs), and a sample of five sales showing
gross → 5% → net payable.

---

## What this document is not

It is not advice and it is not a decision. Every answer that comes back should be
written into `MOR_RISK_ACCEPTANCE.md` — replacing the self-assessment for that question —
and, where it settles a §7 question, `FUIME_MOR_COUNSEL_MEMO` should stop pointing at a
founder's own risk acceptance and start pointing at the memo.
