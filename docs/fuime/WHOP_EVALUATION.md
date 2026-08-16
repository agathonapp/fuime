# Whop as Fuime's substrate — research dossier

**Written 2026-08-15. Research only; no code was read for behaviour changes and no code was
changed.** Sources are Whop's own documentation, terms pages and newsroom, plus its issuing
partner's case study. Every claim below is tagged **[V]** verified against a primary Whop page,
or **[?]** inferred / unconfirmed with the exact verification step named.

## Why this file exists

`MOR_MIGRATION_PLAN.md` §9 already records a first-pass evaluation of Whop, written earlier the
same day. **This file does not replace §9 — it extends it**, and it corrects §9 in two places.
Read §9 first (it is 80 lines), then this.

The three things §9 did not have, and which change the shape of the decision:

1. **The balance is a stablecoin position, not a fiat balance.** Whop Wallet / Treasury funds
   are held as **USDT**, and Whop Cards are collateralised by crypto in a **self-custodial
   wallet whose key is split with Privy**. §9 evaluated Whop as a fiat neobank substrate. It
   is not one. (§3 below.)
2. **Whop's Youth Safety Policy contains a written guardian-consent-for-minor-earnings rule.**
   §9's blocking question Q9 asked whether a guardian can be the verified principal for a
   16-year-old operator. Whop's published policy answers most of it in Fuime's favour. That
   moves Q9 from "blocking unknown" to "confirm scope in writing." (§4 below.)
3. **Check deposits do not exist on Whop, at all.** Not as a beta, not as a partner feature.
   (§5 below.)

---

## §1 — The short answer to the three questions asked

| Ask | Answer |
|---|---|
| **Card issuing** | **Yes, genuinely.** Whop issues cards to a platform's users via API against a balance the platform holds, no underwriting, and shares interchange back. This is the strongest part of the offer. Two large caveats: the card is a **commercial-use-only** product collateralised by **crypto**, and it is not clear Fuime can enforce its own merchant-category allowlist. |
| **Check deposits** | **No.** Whop has no check deposit, no remote deposit capture, no lockbox. Money-in is cards, ACH debit, Apple Pay, BNPL and crypto. A check rail would need an entirely separate provider and would reintroduce exactly the bank-partner dependency Whop was supposed to remove. |
| **Use our ledger** | **Yes, and this is the easy part.** Whop's webhook surface is rich enough to feed HCB's existing `CanonicalPendingTransaction → CanonicalTransaction` pipeline the same way the Stripe plan did — arguably better, because `card_transaction.*` and `transfer.*` events exist as first-class types. The cost is that Whop keeps **its own** ledger too, so Fuime inherits a reconciliation obligation it does not have today. |

**Overall: Whop is a real candidate and materially better than "build it ourselves," but it is a
substrate swap with a crypto-custody problem sitting under a product for minors.** §9's
recommendation — *do not swap yet, do not stop building* — survives this research unchanged. What
changes is *which question decides it*, and it is no longer the one §9 named.

---

## §2 — What Whop for Platforms actually is

**[V]** Whop is a multi-PSP orchestration layer plus a ledger, a payout network, a KYC/KYB
pipeline and a card program, exposed as one API. Base URL `https://api.whop.com/api/v1`, bearer
auth, date-pinned versioning via an `Api-Version-Date` header (omitting it pins you to the
`2025-01-01` shapes). TypeScript, Python and **Ruby** SDKs exist (`whop_sdk`) — relevant, this is
a Rails monolith. There is a genuine sandbox at `sandbox.whop.com`, a separate account from
production, and **KYC can be exercised in sandbox without a real check**. That last detail matters
more than it looks: it is precisely the thing the Stripe integration has been blocked on since
2026-08-14 (`EMBEDDED_CONNECT.md` §7 — the Stripe CLI is logged into a Hack Club test account).

### The object model, and how cleanly it maps onto Fuime

| Whop object | Fuime equivalent | Notes |
|---|---|---|
| `Company` (`biz_…`), created with `parent_company_id` = Fuime's company | `Event` (venture) | **[V]** One API call creates a connected account under the platform. |
| `AccountLink` with `use_case: "account_onboarding"` | The guardian onboarding flow | **[V]** Hosted KYC/KYB, `refresh_url` + `return_url`. Same shape as Stripe's account links, so `EMBEDDED_CONNECT.md`'s onboarding design mostly ports. |
| `LedgerAccount` (`ldgr_…`), type `primary` or `pool`, owned by a User **or** a Company | `Event#balance_*` / `Fuime::PayablesLedger` | **[V]** Carries `balance`, `pending_balance`, `reserve_balance`, `total_withdrawable_balance`, `settlement_time_at`, `transfer_fee`, plus a payments approval status (`pending`/`approved`/`monitoring`/`rejected`). 70+ currencies including USD, EUR — **and BTC, ETH, USDT, XAU**. |
| `Transfer` | `Fuime::PayablesLedger` postings | **[V]** Moves funds between two ledger accounts; both sides accept a `user_…`, `biz_…` or `ldgr_…` id. Returns a `transfer.id`. |
| `Verification` / `IdentityProfile` | Guardian identity collection (L4) | **[V]** KYC for individuals, KYB for businesses, synced from the underlying provider. |
| `Payout` / `Withdrawal` / `PayoutMethod` | `PayoutService`, payout batches | **[V]** ACH, RTP, wire, crypto, Venmo, local bank in 187+ countries. |
| `Card` / `CardApplication` / `CardTransaction` | Stripe Issuing surface, currently flag-off | **[V]** See §6. |
| `Topup` / `Deposit` | Platform float | **[V]** Platform funds its own balance from a saved payment method. |
| `Swap` | *nothing* | **[V]** Converts a balance between currencies. Exists because balances are multi-currency incl. stablecoins. This object is the tell for §3. |

**[V]** Whop is the **merchant of record and deemed supplier for Whop Payments transactions**,
and handles US sales tax + EU VAT remittance when the tax add-on is enabled. **[V]** KYC and
regulatory compliance are described by Whop as "managed by Whop as part of onboarding and payouts,
not delegated back to the platform operator."

§9.3 read this correctly: **if Whop is MoR, Fuime is not**, and phases 3–6 of the MoR migration
were built on Fuime being the seller. That is the real cost of the swap, and it is large.

---

## §3 — The finding §9 did not have: the balance is USDT

This is the single most important thing in this document.

**[V] Whop Wallet / Treasury holds funds as USDT** — specifically USDT0 on **Plasma**, a
stablecoin-focused chain. Tether is a strategic investor in Whop. Whop's own wallet terms state,
in terms: *"Stablecoins held as USDT are not U.S. dollars, are not bank deposits, and are not FDIC
insured,"* and *"Stablecoins may fail to maintain their stated value."*

**[V] Custody is self-custodial via Privy.** *"Your private key is split between your device and
Privy's infrastructure through end-to-end encryption, so neither Whop nor Privy can access or move
your stablecoins without your consent."* Whop describes itself as *"a technology company, not a
financial institution."* Treasury's yield (advertised up to 6% APY) is explicitly *"provided by
third-party protocols."*

**[V] The card is collateralised by crypto.** The U.S. Card Business Terms say the collateral
comes from *"your primary Linked Wallet or any Additional Wallets,"* across Ethereum, Polygon,
Optimism and Arbitrum, *"held in stablecoins or crypto assets with real-time market valuation."*
Whop's issuing partner **Rain** confirms it: *"Business balances are held in stablecoins on Rain's
infrastructure, and Rain handles daily settlement with the Visa network."*

### Why this is the decision point, not Q9

§9 framed the attraction as "Fuime would not need its own bank partner" and called that the
strongest argument in the proposal. It is true — **[V]** the licensed chain is Whop → Rain →
issuing bank — but it is true in a way that does not mean what it appears to mean:

- **The reason no bank partner is needed is that there is no bank deposit.** A teen venture's
  "balance" would be a stablecoin position in a self-custodial wallet, not a claim on a bank.
  Swapping a missing bank partner for a stablecoin position is not removing a dependency; it is
  substituting a different, less-tested one.
- **§9.2 said L5 restricts the word, not the custody. That is right, and it now cuts harder.**
  If the balance is USDT, then not only is "bank" forbidden — "deposit," "savings," "insured" and
  "your money is safe" become *affirmatively false* rather than merely unlicensed. The standing
  footer disclosure gets longer, not shorter.
- **Depeg and protocol risk land on a minor.** Fuime's whole legal posture (L2) is that the
  guardian is the principal obligor. It is one thing for a guardian to accept chargeback
  liability; it is another for a 15-year-old's sticker-shop revenue to sit in USDT0 on Plasma
  earning yield from third-party protocols. Whether a guardian *can* consent to that on a minor's
  behalf is a question no one has asked yet.
- **Yield to minors is a securities question nobody in this repo has looked at.** `LEGAL_RESEARCH.md`
  covers money transmission, COPPA, the infancy doctrine and card terms. It contains nothing on
  offering a yield-bearing instrument to a custodial account for a minor. That is a new research
  workstream, not a footnote.
- **State crypto regimes are a separate licensing map from money transmission.** NYDFS BitLicense
  and the various state VASC regimes key on the activity, and "Whop holds the licence" needs to be
  verified as covering a platform-of-a-platform arrangement, not assumed.

**[?] Open and material: is there a pure-fiat path?** The `LedgerAccount` supports USD as a
currency and the `Swap` object exists to convert between currencies, which suggests a fiat-settled
configuration may be possible for connected accounts even though Treasury and Cards are
stablecoin-native. **This is the highest-value unknown in the entire evaluation.** If a
connected-account balance can be held in USD and paid out over ACH without ever touching USDT, most
of §3 evaporates and Whop becomes a strong candidate. If it cannot, Whop is a crypto product
wearing a fintech UI, and shipping it to 13-to-17-year-olds is a different company than the one
`LEGAL_RESEARCH.md` describes.

*Verify by:* creating a sandbox connected account, funding it, and reading `GET /ledger_accounts`
to see what currency the balance actually lands in — then attempting an ACH withdrawal and checking
whether a `swap.completed` event fires. This is a half-day of sandbox work and it decides the
substrate. **Do this before asking Whop anything.**

---

## §4 — Q9 is mostly answered, and in Fuime's favour

§9.4 called this "the blocking unknown." It is less blocking than it looked.

**[V] Whop's Terms of Service:** *"You must be at least 13 years old… If you are between 13 and
18, you represent that your parent or legal guardian has reviewed and agreed to these Terms and
will supervise your use of Whop."*

**[V] Whop's Youth Safety Policy** goes considerably further, and this is the paragraph that
matters:

> Users under 13 are blocked from registering (COPPA). Users aged 13–17 are flagged as **"minor
> accounts"** and subject to additional protections. **Users under 18 cannot earn until Whop's
> payment processor verifies the guardian's identity and the guardian provides consent via email
> confirmation code.**

That is — structurally — Fuime's guardianship model, already built, already enforced at the
processor layer. §9.4 noted correctly that Content Rewards and the Affiliate Program are 18+, and
inferred a general adult floor on earning. The Youth Safety Policy shows those are **program-specific
floors, not a platform floor**: the platform floor is 13 with verified guardian consent.

**[V] The card terms independently support the guardian-as-principal shape.** The U.S. Card
Business Terms let the account holder designate **Authorized Users**, with *"all Authorized User
activity will be attributed to you"* and full liability on the account holder. Guardian = account
holder, teen = authorized user. This is the same construction `CLAUDE.md` already records for
Celtic's Authorized User Terms, which is why the "a minor's age is not the obstacle to cards"
correction generalises here.

**What is still genuinely open — a narrowed Q9:**

> **Q9′.** Whop's Seller Terms contain **no** age clause and **no** minors/guardian clause at all
> — the age rules live only in the ToS and the Youth Safety Policy. Does the guardian-consent
> earning path extend to a **connected account under a third-party platform** where the
> day-to-day operator is a 16-year-old and the guardian is the KYB principal and chargeback
> obligor? And is the card's Authorized User designation available to a minor?

The absence of any minors clause in the Seller Terms is the gap. §9's instinct — get it in writing
— is right; the question is just much narrower than it was, and it is now a scoping question rather
than an existential one.

---

## §5 — Check deposits: no, and the "no" is clean

**[V]** Whop's money-in surface is: domestic and international cards, Apple Pay, ACH debit
(1.5%, capped at $5), BNPL via Klarna/Afterpay (15%!), crypto, and 100+ local methods. Platform
float is added via the `topups` object from a **saved payment method** on the dashboard.

There is **no** check deposit, remote deposit capture, lockbox, or paper-instrument rail anywhere in
Whop's documentation, fee schedule, webhook event list or beta API index. The word does not appear.

Implication worth stating plainly: **check deposit is the one capability on the founder's list that
Whop cannot supply at any price.** Adding it would mean a bank or a deposit-capture vendor
alongside Whop — reintroducing the bank-partner dependency, splitting custody across two
substrates, and creating a second reconciliation surface. If check deposit is a launch requirement,
Whop does not close the gap and the evaluation changes. If it is a "someday," Whop is unaffected.

*Worth asking whoever raised it: for a 15-year-old lawn-care or tutoring business, is the real
requirement "deposit a paper check" or "get paid by a customer who wants to pay by check"? Those
have very different answers — the second is solvable with an invoice + ACH debit link on rails
Whop already has.*

---

## §6 — Card issuing, in detail

This is the strongest part of Whop's offer and it is worth being precise about.

**[V] How it works.** Platforms issue cards to their users via API, each linked to a balance held
on the platform. No credit line, no underwriting — the card spends an existing balance. Cards can
be triggered on any product event (signup, balance threshold, task). Visa network, ~175M merchant
locations. Virtual or physical. Apple/Google Wallet provisioning. Platforms earn a share of
interchange (Whop cites the usual 0.2–2.5% band) and Whop processes the split automatically.

**[V] The API.** `POST /cards` (beta). Owner is `account_id` (`biz_…`) or `user_id` (`user_…`);
business card accounts additionally require `assigned_user_id` for the team member holding it.
Controls: `spend_limit` + `spend_limit_frequency` (daily/weekly/monthly/one_time) and
`transaction_limit` (per-authorisation ceiling). `type` is `virtual` or `physical`. Response codes
are meaningful: `201` issued, `202` async (provisioning, onboarding invite, or an application
needing verification), `409` *"the account's card application is not approved."*

**[V] The issuer is Third National**, under a Visa licence, with the terms governed by **Puerto
Rico law** and carrying a **mandatory arbitration clause with a class-action waiver**.

**[V] It is a commercial card.** *"You will not use the Whop Card for personal, family, or
household use."* Prohibited: cash-equivalents (money orders, wire transfers, cryptocurrency),
gambling, lottery, P2P transfers. FX is 1% + 1% cross-border.

### Three things to weigh

**1. The commercial-use restriction is a gift, not an obstacle.** Fuime already enforces a
business-purchases-only category allowlist because of what the card *buys*, not who holds it.
Whop's terms impose the same restriction contractually. These point the same direction.

**2. [?] But Fuime may lose the ability to enforce its own allowlist.** Whop's marketing says
platforms can set *"merchant restrictions"*; the documented `POST /cards` parameters expose only
spend and transaction limits. There is a documented default block list of merchant categories, but
that is Whop's list, not a per-card allowlist under Fuime's control. And critically: the webhook
set is `card_transaction.created / updated / completed / declined / reversed` — **these are
notifications, not authorisation hooks.** HCB's model (`CLAUDE.md`, and C3 in the MoR plan)
approves each swipe against its own subledger in real time. **Whop appears to decide
authorisations, with Fuime watching.** If that is right, Fuime's category allowlist stops being a
Fuime control and becomes a request to Whop.

*Verify by:* reading the full `POST /cards` schema in the beta reference for any MCC / allowed-
category / blocked-merchant field, and asking Whop directly whether a real-time authorisation
webhook (approve/decline within the auth window) exists for platforms. **This is the second most
important unknown after §3's fiat question.**

**3. The crypto collateral applies here too.** Per §3, card spend is collateralised from a linked
crypto wallet and settled by Rain in stablecoins. A guardian-owned business card backed by USDT is
a different product to explain to a parent than a debit card on a bank balance.

**Minor note on optics:** the headline card benefit is **5% cashback at Uber**. For a platform
whose users are 13–17, "our card gives you 5% back on Uber" is not a feature you would put in the
marketing, and L7 (no targeted advertising or profiling of minors) constrains how any rewards
programme gets surfaced to them at all.

---

## §7 — Feeding Fuime's ledger

**Verdict: this is the easy part, and Whop's event surface is better suited to it than Stripe's.**

**[V] Webhook mechanics.** Envelope carries `id`, `type`, `api_version_date`, `timestamp`,
`company_id`, and the full resource in `data`. Signature is HMAC-SHA256 over
`{webhook-id}.{webhook-timestamp}.{raw body}`, base64, in a `webhook-signature` header; Whop's own
docs instruct constant-time comparison and rejecting timestamps older than 5 minutes. Delivery is
**at-least-once**, ordering is **not guaranteed**, and Whop explicitly tells you to store
`webhook-id` for dedupe. Retries: 12 attempts over ~71 hours; warning email at 24h of failures;
webhook disabled after 72h with 10+ failures. Handlers must return 2xx in **under 5 seconds**.

Those three properties — at-least-once, unordered, 5-second budget — mean the handler must enqueue
and return, and idempotency must key on `webhook-id`. That is the same discipline Milestone 6
already required of the Stripe webhook ("replaying the same event does not double-post"), so the
existing design intent carries over.

**[V] The events that map to ledger lines:**

| Whop event | Ledger meaning |
|---|---|
| `payment.created / pending / succeeded / failed` | Money-in → `CanonicalPendingTransaction` → `CanonicalTransaction` |
| `ledger_account.funds_available` | Pending clears to withdrawable — the settlement flip |
| `transfer.created / completed / failed` | Internal movement (platform → venture) |
| `withdrawal.created / updated` | Payout to the family's bank |
| `deposit.succeeded` | Platform float top-up |
| `card_transaction.created / updated / completed / declined / reversed` | Card spend, with a real reversal event |
| `refund.created / updated`, `dispute.created / updated` | Refunds and chargebacks |
| `resolution_center_case.*`, `dispute_alert.created` | Dispute lifecycle |
| `payout_account.status_updated`, `verification.succeeded`, `identity_profile.updated` | Onboarding/KYC state → the admin queues in `ADMIN_OPS_QUEUES.md` |
| `swap.completed` | Currency conversion — **the one with no HCB analogue** |

Rule 3 holds without strain: this feeds the pipeline through a new source, exactly as Milestone 6
specified, and touches no pipeline internals.

**The genuinely new cost: two ledgers.** Whop maintains its own `LedgerAccount` per company, with
its own `balance` / `pending_balance` / `reserve_balance` / `total_withdrawable_balance`. HCB's
ledger is authoritative in Fuime's UI. Today, under Connect, Stripe's balance and Fuime's ledger
diverging is a display problem. Under Whop, **Whop's ledger is where the money actually is** and
Fuime's is a mirror. That requires a reconciliation job and a drift alarm that do not exist and are
not in any current plan. Budget for them; the failure mode (a venture's page showing a balance
Whop disagrees with) is exactly the kind of thing that erodes a parent's trust irreversibly.

`Fuime::PayablesLedger`'s shape survives — §9.3 got this right, an operator has a receivable rather
than a balance — but the debtor changes from Fuime to Whop, and every copy string naming Fuime as
payer becomes wrong.

---

## §8 — The money, and it is worse than §9 assumed

**[V] Whop's fee schedule** (from `docs.whop.com/fees`, which is authoritative — third-party blog
summaries disagree with it and should be ignored):

| Item | Rate |
|---|---|
| Domestic card | **2.7% + $0.30** |
| International card | +1.5% |
| Currency conversion | +1% |
| ACH debit | 1.5%, max $5 |
| BNPL (Klarna/Afterpay) | **15%** |
| Orchestration (optional) | 0.8% |
| Billing (optional) | 0.5% |
| **Tax & remittance** | **2%** |
| 3DS | $0.03 |
| Radar fraud ML | $0.07 |
| **Dispute / chargeback** | **$15.00** |
| Early dispute alert (RDR) | $29.00 |
| Affiliate processing | 1.25% |
| **Next-day ACH payout** | **$2.50 flat** |
| Instant (RTP) payout | 4% + $1.00 |
| Crypto payout | 5% + $1.00 |
| Venmo payout | 5% + $1.00 |
| Bank wire | $23.00 |

**[?]** Whop's consumer marketplace also charges a 3% platform fee on gated-community sales. It is
unclear whether that applies to Whop-for-Platforms connected accounts. **Confirm before doing any
pricing work** — it is the difference between a workable margin and none.

### Against Fuime's plan ladder

`MOR_MIGRATION_PLAN.md` §8.6 derives margin as `(rate − processor) × amount − fixed`. Substituting
Whop's 2.7% + $0.30 for Stripe's 2.9% + $0.30, in the **lean** configuration (no tax add-on, no
orchestration, no billing):

| Plan | Rate | Margin over Whop | Break-even sale |
|---|---|---|---|
| Free | 7% | 4.3% | **$6.98** (Stripe today: $7.32) |
| Standard | 5% | 2.3% | **$13.04** (Stripe: $14.29) |
| Pro | 3% | 0.3% | **$100.00** (Stripe: $300.00) |

Marginally better than Stripe across the board. **But turn on tax & remittance at 2%** — which is
much of *why* you would choose Whop, since it is the thing that makes Whop the MoR and makes phases
7–8 evaporate — and the effective processor rate becomes **4.7% + $0.30**:

| Plan | Rate | Margin | Break-even sale |
|---|---|---|---|
| Free | 7% | 2.3% | **$13.04** |
| Standard | 5% | 0.3% | **$100.00** |
| Pro | 3% | **−1.7%** | **never profitable** |

**Standard becomes what Pro is today, and Pro becomes unsalvageable.** §8.6's open item ("Pro needs
a rate change, not a floor") does not get resolved by Whop — it gets one tier worse. The 50¢ floor
in `Event#fuime_fee_cents_on` rescues small sales under either substrate and rescues nothing in the
middle of the range under this one.

### The payout fee is the finding for the branch you are on

**$2.50 flat per next-day ACH payout.** Under Stripe Connect, payouts to a connected account are
free. On a teen's $40 payout, $2.50 is **6.25%** — larger than Fuime's entire Standard-tier take.

The current branch is `fuime/mor-phase6-payout-batches`. If Whop is ever adopted, **payout batching
stops being an efficiency and becomes the thing that makes the unit economics work at all**, and the
batch cadence becomes a pricing decision rather than an ops decision. Whoever finishes phase 6
should know that its value under a Whop substrate is roughly an order of magnitude higher than
under Stripe — which is a mild argument for finishing it properly now, since it is
substrate-independent work (per §9.5) that pays off more under the alternative.

---

## §9 — What adopting Whop would cost, restated

§9.3 of the MoR plan lists this; these are the additions this research surfaces.

**Survives the swap:** `Fuime::PayablesLedger`'s shape · the payout approval gate and phase 6
dials · guardianship models and the under-13 refusal · the ledger pipeline · onboarding UX ·
vetting and payout-review queues · the fee floor mechanism.

**Dies or is rewritten:** the entire Stripe Connect stack (`EMBEDDED_CONNECT.md` — embedded
components, `Fuime::PaymentLinkService`, account links, the one thing actually tested against a
live provider on 2026-08-14) · `Event::Plan`'s rate ladder (§8 above) · every copy string naming
Fuime as payer or seller · `FEATURE_SPONSOR_BANKING`'s boot guard, which demands a named partner
bank and would now have a strange answer.

**Newly required, in nobody's plan:**
- A two-ledger reconciliation job and drift alarm (§7).
- A stablecoin-custody disclosure regime and, probably, a fresh section of `LEGAL_RESEARCH.md`
  on yield-bearing instruments held for minors (§3).
- A payout-batching economic model, because $2.50/payout changes the shape (§8).
- Whatever replaces the card category allowlist if Fuime cannot enforce one (§6).

**Gets cheaper:** 1099-NEC filing (§9.3's strongest argument, unchanged and still correct — if Whop
is MoR, Whop files) · sales-tax nexus (phase 8 largely evaporates) · disputes (phase 7 shrinks, at
$15/dispute) · **and the provider-testing blocker**, since Whop's sandbox does KYC without a real
check and does not care whose CLI is logged in where.

---

## §10 — What the next session should actually do

Ordered. Steps 1–2 are sandbox work that costs a day and decides most of it; do not skip to 3.

1. **Answer the fiat question (§3).** Sign up at `sandbox.whop.com`, create a connected `Company`
   under a platform company, run the `AccountLink` onboarding, take a test payment, and read the
   resulting `LedgerAccount`. **What currency is the balance in?** Then attempt an ACH withdrawal
   and watch for `swap.completed`. If a USD-in/USD-out path exists with no stablecoin leg, §3
   mostly dissolves. If it does not, escalate to the founder before any further work — that is a
   change in what company Fuime is, not a technical detail.
2. **Answer the authorisation question (§6).** Read the complete `POST /cards` beta schema for any
   merchant-category field. Establish whether a real-time authorisation webhook exists for
   platforms. Without one, Fuime's category allowlist is not enforceable by Fuime.
3. **Send Whop the narrowed Q9′ (§4), in writing**, in the same conversation already owed to
   Stripe per §9.5 — the answers are directly comparable and one exchange decides the substrate.
   Ask alongside it: does the 3% marketplace platform fee apply to connected accounts under
   Whop for Platforms?
4. **Do not write any Whop code, and do not touch the Stripe stack.** §9.5's reasoning holds and
   nothing here weakens it. The substrate-independent work — onboarding, guides, own-business
   analytics, vetting and payout-review queues, and finishing phase 6 — is safe under either and
   is where effort should go.
5. **Do not let this reach fuime.com.** L8 exists because the site once described a Stripe Connect
   architecture that did not exist. "Neobank," "card issuing" and "banking" are all *more*
   forbidden under Whop than under Stripe, not less — §9.2 established that L5 restricts the word
   regardless of custody, and §3 shows the custody here makes several of those words affirmatively
   untrue. Nothing in this document is a marketing claim.

### Corrections to record if Whop is pursued

`MOR_MIGRATION_PLAN.md` §9 should be amended, not rewritten:
- §9.1's row *"Fuime would not need its own bank partner — **True**, the strongest argument"*
  needs the qualifier from §3: true, because there is no bank deposit. The strength of the argument
  depends entirely on the fiat question in step 1.
- §9.4's *"blocking unknown"* framing should be replaced with §4's narrowed Q9′. Whop's Youth
  Safety Policy is a published, written guardian-consent-for-minor-earnings rule; the gap is the
  Seller Terms' silence on minors and whether the rule extends to third-party platform connected
  accounts.
- §9.5's recommendation stands unchanged.

---

## Sources

Whop primary: [Docs index](https://docs.whop.com/llms.txt) ·
[Beta API overview](https://docs.whop.com/api-reference/beta/overview) ·
[Enroll connected accounts](https://docs.whop.com/developer/platforms/enroll-connected-accounts) ·
[Connected accounts](https://docs.whop.com/manage-your-business/manage-payouts/connected-accounts) ·
[LedgerAccount](https://docs.whop.com/api-reference/ledger-accounts/ledger-account) ·
[Transfers](https://docs.whop.com/api-reference/transfers/create-transfer) ·
[Webhooks](https://docs.whop.com/developer/guides/webhooks) ·
[Add funds](https://docs.whop.com/developer/platforms/add-funds-to-your-balance) ·
[Whop Cards](https://docs.whop.com/whop-finance/cards) ·
[Create card](https://docs.whop.com/api-reference/beta/cards/create-card) ·
[Fees](https://docs.whop.com/fees) ·
[Terms of Service](https://whop.com/tos/) ·
[Seller Terms](https://whop.com/seller-terms/) ·
[Youth Safety Policy](https://whop.com/youth-safety-policy/) ·
[Whop Wallet Terms](https://whop.com/whop-wallet-terms/) ·
[U.S. Card Business Terms](https://whop.com/us-card-business-terms/) ·
[Sandbox guide](https://whop.com/blog/whop-sandbox/) ·
[Virtual card issuing](https://whop.com/blog/virtual-card-issuing/) ·
[Payments network](https://whop.com/blog/whop-payments-network/) ·
[Treasury](https://whop.com/blog/whop-treasury/) ·
[Card launch](https://newsroom.whop.com/cards/) ·
[Treasury launch](https://newsroom.whop.com/whop-treasury/)

Third party: [Rain — how Whop launched a global card program](https://www.rain.xyz/resources/how-whop-launched-a-global-card-program-in-weeks-instead-of-years-using-stablecoins) ·
[Finextra — Whop issues stablecoin debit card](https://www.finextra.com/pressarticle/109969/whop-issues-stablecoin-debit-card) ·
[Sacra — Whop revenue and funding](https://sacra.com/c/whop/)

---

## §11 — DECISION (2026-08-16): stay on Stripe Connect

**Decided.** The dossier's §10 says the fiat question decides the substrate. On the numbers in
§8, it does not — **the economics decide it, and they decide it against Whop regardless of what
currency the balance is in.** Recording the reasoning because the four things Whop appears to
win are real, and somebody will raise them again.

### 11.1 The fee analysis is substrate-deciding on its own

§8's own table, restated as the thing it actually implies. With the tax add-on enabled — which
is *most of why* you would pick Whop, since it is what makes Whop the MoR and makes phase 8
evaporate — the effective processor rate is **4.7% + $0.30**:

| Plan | Rate | Margin over Whop | Break-even sale |
|---|---|---|---|
| Free | 7% | 2.3% | $13.04 |
| Standard | 5% | 0.3% | $100.00 |
| Pro | 3% | **−1.7%** | **never** |

`Event::Plan`'s ladder does not survive that. **Standard becomes what Pro is today** — §8.6
already records Pro as a live exposure that gets worse the more successful a low-ticket operator
is — and Pro becomes structurally unprofitable at every sale size. The 50¢ floor rescues small
sales and nothing in the middle.

**And the payout fee is worse than the processing fee.** $2.50 flat per next-day ACH payout,
against **free** on Stripe Connect. On a teen's $40 payout that is 6.25% — more than Fuime's
entire Standard-tier take on the sale that produced it. Phase 6's batching mitigates it (one
fee per operator per run, not per sale), which is the dossier's good catch, but at launch scale
— 25 operators, $25K GMV by November, ~$77/operator/week — a weekly batch still burns 3.25% of
gross on the payout alone, i.e. **two-thirds of Standard-tier revenue**.

None of that depends on §3's fiat question. It is true in USD and true in USDT.

### 11.2 Each of the four apparent wins is off the launch path or cheap

| Apparent win | Why it does not decide |
|---|---|
| **No bank partner needed** | Only `FEATURE_SPONSOR_BANKING` ever needed one, it is off, and it is not on the launch path. The launch path is Connect, which needs no bank partner either. §9.1 called this "the strongest argument"; §3 of this dossier shows *why* it is available — there is no bank deposit — which makes it an argument for a different product, not a cheaper version of this one. |
| **1099-NEC filing** (§8.4 item 2) | A vendor problem, not a substrate problem. Track1099/Tax1099-class filing runs ~$3/form; at 25 operators that is **~$75/year**. HCB already does the hard half — `Tax::Form` (DocuSeal W-9) and `LegalEntity#tin_hash` collect the data. Swapping payment substrates to avoid $75/year of filing is not a trade. |
| **Sales tax / nexus** (phase 8) | **Already neutralised by a decision made in §8.3 D3.** Phase 1 is services-only precisely to remove sales-tax nexus and product liability. Whop's biggest structural advantage is against an exposure Fuime deliberately does not have. It becomes real only if physical goods open — see 11.4. |
| **Whop's sandbox unblocks provider testing** | The Stripe blocker (`EMBEDDED_CONNECT.md` §7, open since 2026-08-14) is that **the CLI is logged into the wrong account**. That is a `stripe login` away. It has been quoted three times now as though it were structural; it is not, and it must stop being an argument for anything. |

### 11.3 And three costs that land squarely on the launch path

1. **A minor's revenue would sit in USDT.** §3 is the finding of this dossier and it is
   disqualifying on its own terms for a 13–17 product. Not because stablecoins are
   illegitimate, but because of what it does to Fuime's own position: L5's forbidden words stop
   being *unlicensed* and become **affirmatively false** — "deposit", "savings", "your money is
   safe" are not merely unavailable, they would be untrue. It also opens a legal workstream
   `LEGAL_RESEARCH.md` has nothing on (a yield-bearing instrument held for a minor, plus state
   VASC/BitLicense regimes), which is a new research programme rather than a section.
2. **Fuime probably loses its card allowlist** (§6.2). The webhook set is
   `card_transaction.created/updated/completed/declined/reversed` — notifications, not
   authorisation hooks. Fuime's business-purchases-only category allowlist is *the* control that
   makes teen cards defensible; converting it from a Fuime control into a request to Whop is
   worse than having no cards.
3. **It discards the only integration ever exercised against a live provider.** The
   direct-charge shape and `application_fee_amount` were verified against real Stripe on
   2026-08-14. That is the single piece of this system with evidence behind it.

### 11.4 What would reopen this

Not "Whop got better" — two specific changes in **Fuime's** situation, and both must hold:

1. **Physical goods or digital products open up**, making sales-tax nexus a real exposure rather
   than one designed out. That is when Whop-as-MoR starts paying for itself.
2. **§3's fiat question resolves in favour of a USD-in / USD-out path** with no stablecoin leg
   (dossier §10 step 1 — still a half-day of sandbox work, still worth doing when the time comes).

Even then the fee ladder in 11.1 has to be re-derived, because a 4.7% all-in processor cost
does not support a 5% retail rate under any arrangement.

### 11.5 What to do now

- **Stay on Stripe Connect.** Phases 3a–6 and 9 stand. Nothing gets rewritten.
- **Run `stripe login` against the Fuime account** and finish the `stripe listen` pass. It is
  the oldest open item in the repo and it is five minutes of work.
- **Put 1099-NEC filing on the roadmap as a vendor integration**, not as a reason to move.
  §8.4 item 2 stops being an argument for anything once it is priced.
- **Keep this dossier.** It is the best provider research in the repo and 11.4 names exactly
  when to reread it. Nothing in it was wasted; §4's Youth Safety finding in particular is worth
  carrying — Whop publishing a guardian-consent-for-minor-earnings rule is independent evidence
  that Fuime's guardianship model is the industry-standard shape and not an idiosyncratic one.

### 11.6 A naming collision to fix

The onboarding work committed on 2026-08-15 was called "phase 7a", which collides with §8.5's
**phase 7 (disputes and clawback)**. §8.5's numbering is the plan of record and does not move.
The onboarding work should be referred to as **the business-type step**, not phase 7.
