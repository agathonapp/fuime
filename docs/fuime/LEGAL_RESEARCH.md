# Fuime — Legal & Regulatory Research (U.S.)

**Date:** August 3, 2026 · **Method:** 7 parallel research workstreams over primary sources
(statutes, regs, regulator orders, platform ToS), plus a codebase audit and an independent
adversarial verification pass of the 16 most load-bearing citations (16/16 verified, none refuted).
**Status:** AI-produced research to brief counsel — NOT legal advice. Items marked ⚖️ need a lawyer.

---

## Executive summary

**Fuime is legally viable — but not in the architecture this repo currently implements, and
not with the "no SSN" parent flow.** The viable shape is:

> **Parent/guardian is the legal account holder everywhere; the kid is the operator.**
> Payments run through a **guardian-owned Stripe (Connect Standard) account per venture** —
> Stripe holds and settles the money, Fuime never touches it, and Fuime keeps its 4% as a
> Connect application fee. Fuime is the software layer: ledger, books, storefront,
> guardianship record, receipts, education.

The five hard constraints that force this shape:

1. **The pooled-account model is money transmission.** Accepting customers' payments into
   Fuime's own Stripe account, holding ledger balances, and paying out on request is the
   textbook definition of money transmission (31 CFR 1010.100(ff)(5)). Unlicensed operation
   is a federal felony — up to 5 years (18 U.S.C. § 1960) — plus ~49 state licenses we don't
   have. It also violates Stripe's ToS (aggregation/processing for third parties is a
   restricted business outside Connect). HCB escapes this ONLY because it is a 501(c)(3)
   fiscal sponsor (Model A): donations become Hack Club's own charitable assets, so there is
   no "customer money." A for-profit copying the plumbing inherits none of that protection.
   **"Column + Stripe like Hack Club" does not transfer**: Column banks Hack Club because the
   funds are Hack Club's own; a for-profit Fuime holding customers' money at Column would be
   a BaaS/FBO program requiring a compliance program, audits, ~9–18 months, and full
   SSN-based KYC of every parent — realistically unavailable to a pre-launch startup
   post-Synapse. `docs/fuime/PRODUCTION_READINESS.md` already says this; the research confirms it.

2. **"No SSN" is impossible for live money.** Bank CIP (31 CFR 1020.220) requires a
   taxpayer ID (SSN/ITIN) for every U.S.-person account holder — a passport/birth-certificate
   photo only satisfies the separate *verification* step. Stripe itself requires the
   guardian's **SSN last-4** (full SSN at $500K lifetime volume) before an under-18 account
   can charge or receive payouts. Zero-SSN is achievable only for a pure-software tier that
   never touches funds. Signature + ID photo IS a valid pattern for our own consent layer
   (see COPPA below) — but the ID image must be verified and then **deleted**, not stored.

3. **Serving under-13s = full COPPA.** The amended COPPA Rule (90 FR, eff. June 23, 2025;
   full compliance Apr 22, 2026) applies in full: verifiable parental consent (VPC) via an
   enumerated method before collecting a child's data, separate opt-in for third-party
   disclosure, written retention + security programs, penalties to $53,088/violation.
   Government-ID matching is an approved VPC method **only** with database check or
   selfie face-match AND prompt deletion of the images (16 CFR 312.5(b)). Also: **Stripe's
   floor is 13 even with a guardian** — an under-13's venture can only run on an account
   that is 100% the parent's. Etsy/Venmo/Cash App teen tiers are all 13+; there is NO
   mainstream merchant path for an under-13 except "parent is the merchant."

4. **Never say "bank/banking/FDIC."** With no bank behind us, "business banking for teens"
   violates state statutes (Cal. Fin. Code § 562; 205 ILCS 5/46 — Class A misdemeanor;
   Tex. Fin. Code § 31.005; N.Y. Banking Law § 132; Fla. § 655.922). California's DFPI
   forced Chime off "bank(ing)" in 2021 and issued a fresh order in May 2026; even Hack Club
   had to rename "Hack Club Bank" → "HCB" (Aug 2023). FDIC Part 328 Subpart B (in force
   since Jan 1, 2025, NOT rolled back) prohibits implied-insurance claims by non-banks. The
   "fintech, not a bank; banking services by X Bank, Member FDIC" footer is only lawful once
   a real partner bank exists.

5. **The teen's own signature never reliably binds; the parent's does.** Minors' contracts
   are voidable (infancy doctrine; Cal. Fam. Code §§ 6700/6710). Courts enforce terms when
   the parent is the party (*Heidbreder v. Epic Games*, 438 F. Supp. 3d 591 (E.D.N.C. 2020);
   *Garcia/Colvin v. Roblox* 2024) and void them when only the minor clicked (*Doe v. Epic
   Games*, 435 F. Supp. 3d 1024 (N.D. Cal. 2020); *I.B. v. Facebook*, 905 F. Supp. 2d 989
   (N.D. Cal. 2012)). So: guardian = principal obligor on fees, chargebacks, arbitration,
   indemnity; teen co-clicks; ratification-on-majority clause; under-13s click nothing.

**Good news:** a minor CAN operate a sole proprietorship (no age gate on the status); teens
owe self-employment tax at $400+ net (their own rate, not kiddie tax); the 1099-K threshold
is back to $20K/200 (OBBBA, 2025); several states (TX/UT/CO) exempt occasional minor-run
businesses from local licensing; CTA/BOI reporting is currently moot for U.S. entities
(FinCEN interim rule, Mar 2025); and the niche is genuinely empty — **no U.S. "teen business
account" product exists**. Every incumbent (Greenlight, Step, Cash App, Etsy, Whatnot,
Fiverr) converges on "parent owns the account, kid operates" — Fuime's opportunity is to
productize that pattern honestly, with real books and a real guardianship record, instead of
the ad-hoc borrowed-login families use today.

---

## Findings by topic (with primary sources)

### 1. Can minors run a business?
- Sole proprietorship: yes, no age gate on the *status*; the constraint is contract
  voidability. DBA/licenses: guardian should file/co-sign.
- Entity formation: IL (805 ILCS 5/2.05), MN (302A.105), OR (ORS 60.044), CO (7-102-101,
  7-80-203) require 18+ organizers/incorporators; TX requires contract capacity (BOC 3.004);
  **Delaware has no age requirement** (8 Del. C. § 101; 6 Del. C. § 18-201). Pattern:
  adult organizer + minor member. Registered agents must be adults everywhere.
- EIN: IRS issues to minors; IRM 21.7.13 cross-references the **parent's SSN**.
- Taxes: SE tax + filing at $400 net SE income, at the child's own rate; kiddie tax hits
  unearned income only (IRS Topic 553).
- FLSA child-labor rules don't reach genuine self-employment (DOL FS #13/#43; CRS R44548).
  Danger zones: Fuime looking like the teens' *employer* (never set prices/schedule work),
  and ventures hiring other minors (full child-labor law attaches). ⚖️

### 2. Minors and bank accounts
- Some states statutorily bind minors' *consumer* deposit accounts (Tex. Fin. Code § 34.305;
  N.Y. Banking Law §§ 134/239; Cal. Fin. Code § 850) — none extend to business accounts.
- UTMA is the wrong tool (irrevocable gift, custodian control, fiduciary limits).
- Market structures: Greenlight/Step/Current/Chase/BusyKid = adult owns, kid is authorized
  user; Capital One MONEY = true joint; **Fidelity Youth** = the only teen-OWNED account
  (brokerage; Fidelity self-insures the disaffirmance risk; parent must open it).
- **No teen business bank account exists in the U.S. market.** Banks require adult signers
  on business accounts (capacity + policy).
- Pooled-funds cautionary tales: Synapse collapse 2024 ($65–96M shortfall, FDIC insurance
  never triggered because no bank failed), Copper's 24-hour shutdown, Yotta/DFPI $1M
  settlement (May 2026) for "FDIC insured / can't lose" claims, OCF dissolution 2024
  (5% fee couldn't fund compliance).

### 3. Money transmission (the pooled model)
- 31 CFR 1010.100(ff)(5) definition; payment-processor exemption (FIN-2013-R002) likely
  unavailable once funds sit in Fuime's own balance; agent-of-payee exemptions (Cal. Fin.
  Code § 2010(l); ~31 MTMA states) cover at most the collection leg, never held balances or
  discretionary payouts. 18 U.S.C. § 1960 = criminal. ⚖️ if we ever intermediate collection.
- Stripe ToS independently prohibits the pooled model (restricted businesses: "payment
  facilitation and aggregation… on behalf of third-party sellers" outside Connect).
- Escape hatches: **Stripe Connect** (recommended), partner-bank FBO (Phase 3+, 9–18 months,
  mid-six-figures, post-Synapse diligence), or become a bank (Increase bought one, 2025-26).

### 4. KYC / the SSN question
- CIP: 31 CFR 1020.220 — TIN mandatory for U.S. persons. June 2025 interagency exemption
  order lets banks source the full SSN from third parties when the customer gives last-4 —
  the SSN is still collected. For minors, the *customer* is whoever opens the account
  (2005 Interagency CIP FAQ) — i.e., the parent, with the parent's SSN.
- Stripe: 13+ floor; under-18 needs an adult Representative who accepts the SSA and provides
  DOB + SSN last-4 (SSA § 1.2(b); Stripe support docs). ⚖️ whose TIN gets the 1099-K on a
  minor+Representative account.
- CDD/CTA: legal-entity accounts trigger beneficial-ownership certification (31 CFR
  1010.230, SSNs again); CTA BOI reporting currently exempts U.S. domestic companies
  (FinCEN interim final rule, 90 FR 13688, Mar 2025) — monitor.

### 5. Under-18 privacy, consent, contracts
- COPPA (under-13): full stack as summarized above. Fuime with under-13 members is
  child-directed/mixed-audience — no "actual knowledge" escape. Neutral age screen becomes a
  *router*, not a gate. The kid's own venture can itself be a COPPA operator (no small-biz
  exemption) — ⚖️ Fuime co-operator exposure for hosted storefronts.
- Teen state laws (13–17): CT bans targeted ads/sale of minors' data outright (SB 1295);
  TX SCOPE data provisions survive (parental tools required); MD Kids Code in effect
  (DPIAs due); NY Child Data Protection Act (eff. June 2025) requires teen informed consent
  or strictly-necessary processing; CA AADC partially revived (9th Cir., Mar 2026);
  FL HB 3 enforceable pending litigation (avoid addictive-feed features). COPPA 2.0/KIDS
  Act passed Senate/House separately in 2026 — build to "COPPA to 17" now.
- ToS enforceability: parent as contracting party + teen co-click + ratification clause;
  arbitration survives in commercial disputes (*Shea* (Fla. 2005)), not always for minors'
  tort claims (*Hojnowski* (N.J. 2006)). Under-13s: parent is sole counterparty.
- ESIGN: parent e-signature valid (15 U.S.C. § 7001); do the § 7001(c) consumer-consent
  choreography before e-delivering required disclosures.
- **ID images: verify then delete.** COPPA VPC methods require prompt deletion; BIPA
  (IL) reaches face-matching with $1K–5K/violation private right of action; ID documents
  trigger breach statutes. Store the consent *record* (method, vendor ref, timestamp,
  doc-version hash, IP/UA) — never the image. Suggest protected-consumer credit freezes to
  parents at onboarding (free under FCRA since 2018).
- Marketing: no ad-targeting of minors (Meta prohibits financial-services ads to minors;
  Google disables under-18 personalization; CT law) — acquisition targets *parents*.
  Transactional-only notifications to minors, none 12–6 a.m. (NY SAFE, eff. Jan 2027).

### 6. Operating on other platforms (what we tell users)
- Stripe 13+ w/ guardian Representative (unique — the hook Fuime builds on); PayPal/Square/
  Shopify/Amazon/eBay/Upwork 18+ (parent owns account); Etsy/Whatnot/Fiverr 13–17 via
  parent-owned account with disclosed supervision; Roblox DevEx 13+ w/ parent; YouTube
  monetization via parent's AdSense; Cash App sponsored accounts 13–17 (and 6–12 P2P only).
- Under-13: **no mainstream merchant path exists** except parent-as-merchant.
- Taxes: income belongs to the kid who earned it regardless of whose account (assignment-of-
  income); 1099-K issues to the account holder's TIN (parent) — nominee reporting fixes it ⚖️;
  all income taxable below the $20K/200 1099-K threshold.
- Sales tax: minors often can't register (CA precludes it; TX/NV parent applies) — the
  guardian registers. ⚖️ whether a future MoR structure makes Fuime the collector.
- Never imply: "you own this account," "your business is a legal entity," "no taxes under
  $20K," "our guardianship unlocks PayPal/Square" (it doesn't).

### 7. What Fuime may say (marketing law)
- Verdicts: **"business banking for teens" / "banking layer" — do not use** (pre-bank:
  statutory violation; post-bank: counsel-sign-off only). "Business accounts…" — only with
  immediate "ledger/platform account, parent-owned, not a bank account" qualification.
  **"Financial tools for teen builders" / "entrepreneurship finance tools for teens" — safe,
  recommended.** "Parent-backed" → say "parent-owned, teen-operated."
- Forbidden vocabulary pre-bank: bank, banking, neobank, checking, savings, deposits,
  insured, FDIC, "your money is safe/guaranteed," bank-ish domains.
- Recommended standing disclosure (pre-bank):
  > "Fuime is a financial technology company, not a bank. Fuime does not hold deposits and
  > does not offer FDIC-insured products. Payments are processed by Stripe. Venture accounts
  > are opened and owned by a parent or legal guardian; young founders operate them with
  > guardian oversight."
- The audience is minors: disclaimers must be teen-legible; influencer/founder content needs
  conspicuous ad labels (FTC stealth-advertising staff perspective, 2023).

### 8. Code/claims audit (what must change in THIS repo)
Verified against the codebase Aug 3, 2026:
- **fuime.com (site/) describes a product that doesn't exist**: claims Stripe Connect
  ("we never hold your money"), a parent ID check via Stripe, 7% + $15/mo — while the app
  implements a pooled account, no Connect, no KYC, 4%, no monthly fee. This is the single
  biggest misrepresentation risk we control today. Fix the site or ship Connect.
- **Guardianship collects no signature, no ID, no verification** — one checkbox + IP/UA
  (guardianship.rb, guardianships_controller.rb). The agreement text admits it. A teen can
  self-approve with a second email address. Acceptable for a test-mode beta only if the copy
  says so; `guardianships/new.html.erb:33` ("verify their identity") currently overclaims.
- **Legacy HCB marketing copy still in tree** claims FDIC insurance via "Fuime's banking
  partners, Column N.A." and 501(c)(3) status (marketing_helper.rb:317, marketing/_footer,
  marketing/funders.html.erb) — unreachable only via one `before_action`. Delete or neuter.
- FAQ line "under 18 you cannot open a business bank account or sign a contract on your own"
  is close to right but imprecise (minors *can* sign; contracts are voidable) — tune copy.
- "business account" phrasing in guardian surfaces (guardianships/new, show, mailer) needs
  the not-a-bank qualifier nearby.
- Under-13 signup is currently refused at validation (user.rb:822) — consistent with a
  13+ launch; supporting under-13s is a deliberate later decision with the COPPA stack.
- Money-in never settles (`fronted: false`, no CanonicalTransaction) — correct honest
  posture for test mode; keep.

---

## Recommended path (sequenced)

**P0 — honesty fixes (this week, no counsel needed)**
1. Rewrite fuime.com to describe the actual product (or clearly label the Connect
   architecture as "coming"); align pricing (4%, no monthly fee) across site/app.
2. Remove/neuter the FDIC/Column/501(c)(3) marketing partials and the "verify their
   identity" overclaim; sweep "bank(ing)" from all user-facing copy.
3. Adopt the standing disclosure block (above) in the site + app footers.

**P1 — the legal architecture (Milestone 6 becomes a Connect spike)**
4. Rebuild money-in on **Stripe Connect Standard**: one guardian-owned connected account
   per venture (guardian = Representative, Stripe does KYC incl. SSN last-4), direct
   charges + 4% `application_fee_amount`, payouts to the family's own bank. Keep the pooled
   pipeline as the test-mode/Playground simulator only.
5. Restructure ToS: guardian as principal obligor (fees, chargebacks, indemnity,
   arbitration with tort carve-out ⚖️), teen co-click, ratification-at-18 clause,
   ESIGN § 7001(c) flow.

**P2 — guardianship verification worth the name**
6. Parent verification via a COPPA-grade method (ID + database check, or ID + selfie
   face-match via BIPA-compliant vendor; or credit-card micro-transaction) — store the
   consent record, delete the images. This upgrades the storefront badge back to
   "Parent-verified."

**P3 — expansions (each needs counsel first ⚖️)**
7. Under-13 support: full COPPA program + parent-owned-merchant model.
8. Cards (bank-issued, parent as CIP'd customer), partner-bank FBO, "graduation at 18"
   account transfer (Cash App/Step precedent).

## Open questions for counsel (consolidated)
1. Guardian-as-principal ToS: does the parent's signature block the *minor's* disaffirmance
   or only give recourse against the parent? Choice of law; AL/NE/MS majority-age outliers.
2. Stripe minor+Representative accounts: whose TIN gets the 1099-K; Treasury/Issuing
   eligibility for guardian-owned sole props.
3. Agent-of-payee scope state-by-state if Fuime ever intermediates collection.
4. Fuime co-operator COPPA exposure for hosted child-directed venture storefronts.
5. GLBA "significantly engaged" trigger timing; Reg P notices at real-money launch.
6. CA/IL tolerance for disclaimered "banking" vocabulary once a partner bank exists.
7. FDIC custodial-recordkeeping rule (RIN 3064-AG07) current status if FBO ever pursued.
8. Sales-tax registration + marketplace-facilitator status under a Connect model.
9. Arbitration carve-outs for minors' tort claims (Hojnowski line).
10. Nominee-1099 mechanics guidance we can safely give families (unauthorized-practice line).

---

## Addendum, 2026-08-03 — Cards: what is actually available

Researched against Stripe's live docs after the founder asked for teen debit cards.
Every claim below is doc-verified unless marked otherwise.

### The blocker is not what anyone expected

**Age is not the constraint.** Stripe documents the Issuing cardholder floor as
**13**, not 18: `individual.dob` on Cardholder create reads "Cardholders must be
older than 13 years old." Celtic Bank's Authorized User Terms contain no
minimum-age clause at all. The guardianship split maps cleanly: the guardian, as
account representative, accepts the Issuing **Accountholder** Terms; the teen
accepts the **Authorized User** Terms.

**Connect Issuing is real and GA.** It needs the `card_issuing` and `transfers`
capabilities and — importantly — **does not require Stripe Treasury**, which is a
much higher, sales-gated bar.

**The actual blocker is what an Issuing card legally is.** It is a
business-purpose **commercial charge card**, and the terms are explicit:

> "You may only use your card for business or commercial purchases on behalf of
> your Accountholder. **You may not use your card for personal, family or
> household purposes**." — Celtic Authorized User Terms

> "The Program is only available for business purposes… You represent and warrant
> that you are a commercial enterprise." … "your Card Account **is a commercial
> account and does not provide all consumer protections**." — Celtic Spend Card
> Accountholder Terms §3.1, §6.2

Stripe's supported-use-cases page adds that consumer use cases are unsupported and
that card spend "may not be funded partially or entirely by an individual's
personal funds."

**So: an Issuing card lets a teen buy inventory, software and supplies. It does
not let them spend their earnings on themselves, and a parent cannot top it up
from personal checking.** If the product vision is "the teen gets a card and
spends what they earned," that is a consumer product on a different rail, and no
amount of accepted liability changes it.

### What cards would cost, if pursued anyway

Issuing requires `losses.payments = application`, which by Stripe's own
incompatibility rules drags two more properties with it:

| Property | Today | Required for Issuing | Consequence |
|---|---|---|---|
| `losses.payments` | `stripe` | `application` | **Fuime absorbs every negative balance** on every teenager's business |
| `requirement_collection` | `stripe` | `application` | **Guardian SSNs and ID documents land in Fuime's systems** — reversing the privacy position |
| `fees.payer` | `account` | `application` | **Fuime pays all Stripe processing (~2.9% + 30¢)** — a pricing-model change, not a config change |

**And `controller` is create-only.** The Account *update* endpoint accepts no
`controller` parameters, and Stripe states plainly: "If this isn't the case, you
must create new accounts to use Issuing or Treasury for platforms." So existing
families cannot be migrated — they must be re-onboarded. This is why the decision
matters *before* there are users.

**Funding is also gated.** Revenue → card spend instantly requires the Balance
Transfer API **private beta** (`source_balance[type]=payments` →
`destination_balance[type]=issuing`). The GA fallback is payout to the venture's
external bank, then a pull top-up back into the Issuing balance — a multi-day
round trip.

### The option worth asking Stripe about

`controller` is a **per-account** property, so in principle Fuime could keep
`losses.payments = stripe` as the default and create *only* card-cohort ventures
with `application`. The re-onboarding cost is then paid once, by the families who
want a card, instead of by everyone. **[INFERENCE — not a documented pattern]**;
it also depends on whether the Stripe-liability Issuing prohibition is
platform-wide or per-account, which the docs leave ambiguous.

### Three questions for Stripe, before any card code is written
1. Is the "platform can't use Issuing" restriction under Stripe-liability
   **platform-wide or per-connected-account**?
2. May one platform run a **mixed `losses.payments` fleet**?
3. Does a **teen sole-proprietor venture with a guardian representative** qualify
   as a supported Issuing business use case, or will underwriting class it as
   consumer? (Treasury is explicitly closed to consumer purposes; the same
   judgement likely applies here, and it is the question most likely to sink an
   application.)

### Market check
No teen card product issues cards off a merchant-acquiring account. Greenlight
(Community Federal Savings Bank), Step (Evolve), and Cash App (Sutton/Bancorp) are
all **separate consumer deposit or prepaid programs where the parent is the legal
account holder and the child holds an access device**. Running one requires a
BSA/AML program and sponsor-bank underwriting — a different company from the one
Fuime is currently building.

### Market structure — settled, with a 1.0 correlation

Every mainstream teen card is an **issuer-side consumer product** (prepaid, deposit,
or in Step's case a *secured credit line*), never issued off a merchant-acquiring
account. Verified against the actual cardholder agreements:

| Product | Bank | Legal owner | Child's status |
|---|---|---|---|
| Greenlight | Community Federal Savings Bank | **Parent** ("Primary Accountholder") | "Secondary Cardholder" on a sub-account — **no minimum age** |
| Step | Evolve | **Parent/sponsor (18+)** | "Authorized User"; the card is legally a *credit* card, not debit |
| Cash App Families | Sutton Bank | **Sponsor** — "you, and not the Sponsored Person are the legal owner" | Sponsored Person, 13+ (6+ for Child) |
| Current | Choice Financial | **Parent** | "Authorized User… conduct transactions **on your behalf**" |
| Acorns Early (ex-GoHenry) | nbkc / CFSB | **Parent** | "Child Account Cardholder" on a sub-account |
| Venmo Teen | Bancorp | **Parent** — "All funds held in a Teen Account are owned by you, not the Teen User" | Authorized user |
| **Capital One MONEY** | Capital One, N.A. | **BOTH — joint tenants** | **Actual co-owner** |

**The correlation is 1.0: the only product where the child genuinely owns the money
is the one whose provider IS the chartered bank.** Capital One has no program
manager, no middleware, no pooled FBO account, so it can put a minor on the title.
Every fintech in the set routes around minor contractual incapacity by making the
adult the sole owner. That is not timidity — it is the only structure that works.

**The single most instructive datapoint** is Cash App ToS §XI.3:

> "Sponsored Accounts are not eligible to switch to a Cash App Business Account,
> and **Sponsored Persons may not open a Cash App Business Account**."

Block owns both an issuing business (Cash App Card) and one of America's largest
acquirers (Square), and it **explicitly bars minors from the acquiring side**.
Treat that as a considered compliance conclusion by a party with every incentive
and capability to decide otherwise.

**Which makes Stripe the outlier Fuime depends on.** SSA §1.2(b) permits a 13+
user to hold an account provided an adult Representative is added, both are bound,
and the Representative "agrees to be responsible and liable for User's actions."
Square requires 18. Stripe wrote Fuime's guardianship model into a live agreement;
that, not any teen card product, is the precedent to stand on.

### The BaaS path is effectively closed at Fuime's stage (2026)

Not "hard" — closed. Every sponsor bank historically serving this niche is
remediating a consent order, and the orders are structural:

* **Evolve** (Step's bank) — Fed cease & desist, 14 Jun 2024: "Effective
  immediately, the Bank shall not **without the prior written approval of the
  Supervisors**: (i) establish any new fintech partners… or (ii) offer new
  products… to an existing fintech partner." A stressed sponsor bank *cannot say
  yes* without its regulator's written permission first.
* **Community Federal Savings Bank** (Greenlight's *and* Acorns Early's bank) —
  OCC BSA/AML consent order made public 21 May 2026.
* **Choice Financial** (Current's bank) — FDIC consent order over third-party
  programs. **Blue Ridge**, **Lineage**, **Thread** likewise.

And the middleware layer now screens founders out by policy: Treasury Prime
exited tri-party agreements entirely (Feb 2024); **Synctera requires most new
fintech clients to be "Series C or above, or public companies."** Lithic's
authorized-user KYC-exemption workflow — the exact primitive a teen program needs
— is "available only to users **approved by Lithic on a program by program
basis**." No BaaS provider publicly documents minor support at all.

**Copper is the cautionary tale, and it was Fuime's size and stage:** it
discontinued deposit accounts and debit cards on ~24 hours' notice in May 2024
when its middleware provider sunset service, and today is a rewards app with no
card and no partner bank.

### Recommended sequencing for cards

1. **Now — no cards.** Keep the Issuing UI hidden (Milestone 5's original
   instruction was right). The warning in `Fuime::DisabledModules` explains the
   funding incompatibility.
2. **Near term — refer out.** Payouts settle to the family's own bank; they spend
   via a card they already have (Greenlight, Step, a joint Capital One MONEY
   account). Fuime keeps the durable value — the ledger, receipts, expense
   categorisation, parent visibility — and takes zero liability. This ships the
   *outcome* the founder wants without becoming a different company.
3. **Later, only with a funded compliance function** — copy the settled structure
   exactly: pooled deposit account at a sponsor bank, parent as sole legal
   accountholder, per-child sub-accounts as "the records we maintain to account for
   the value of claims" (Greenlight's and Acorns Early's own phrasing), child as
   authorized user, ownership graduating at 18. Encouragingly, **Greenlight sets no
   minimum age for the child** — only the primary accountholder must be 18+.

One concrete copy constraint if cards ever ship on Stripe Issuing: Stripe's US
Issuing compliance rules **require** the line "can only be used for commercial
purposes, and can't be used for personal, family, or household purposes" and
**forbid** "Personal cards", "Get consumer cards", or "Use [card program] for
anything you want."
