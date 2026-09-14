# Paddle gap analysis — what a general-purpose MoR needs that Fuime lacks

**Status: research, not a decision. Written 2026-09-14.**
**Fuime state verified against `main` + `render.yaml` on 2026-09-14. Paddle state fetched live
from paddle.com, developer.paddle.com and the help centre the same day.**

> ## Progress — updated 2026-09-14 (end of session)
>
> | Tier | State |
> |---|---|
> | **Tier 0** — live-money defects | **Done bar one.** Payout rail decided (manual transfers, honest ledger) and `mark_paid!` now refuses without a bank reference. Jurisdiction capture, sweep scheduled. **Open: `PLAID_ENV=sandbox` — no seller can attach a bank, so there is still no destination to send to.** |
> | **Tier 1** — recurring billing | **Done.** Month/year offers, subscription checkout, renewals posting from `invoice.paid`, operator/plan collision guarded. **Open: self-serve cancellation for buyers** (FTC click-to-cancel; the pay page points at support@fuime.com), and a subscription-aware backfill for a dropped `invoice.paid`. |
> | **Pricing** (not in the original tiers) | **Done.** One flat 5% + 50¢, no monthly fee, nothing gated, Pro retired, site copy rewritten, L8 guard enforcing it. **Open, operational: live `Fuime::Subscription` rows with no event are still billing $19.99 in Stripe.** |
> | **Tier 2** — sales analytics | **Core done.** `Fuime::SalesReport` + `/:event_slug/sales`: revenue over time, top offers, average sale, revenue by jurisdiction. **Open: checkout conversion** — nothing tracks the storefront, and closing that means tracking visitors on pages minors visit (an L7 decision). **Also open: refund rate**, which needs refunds written to `fuime_sales` rather than inferred from the ledger. |
> | **Tier 3** — outbound webhooks | **Core done.** Endpoints, signed delivery (Stripe-shaped signature), retry ladder, SSRF + DNS-rebinding guards, self-rescheduling job + sweeper. **Open: no seller-facing UI to create an endpoint, only `sale.completed` fires, no delivery-log screen.** |
> | **Customer record** | **Done.** `Fuime::Customer`, captured from `customer_details`, linked to sales, surfaced on the dashboard with repeat-purchase counts. Unblocks self-serve cancellation (`stripe_customer_id` captured). **Open: terms/privacy must disclose that Fuime shares buyer data with the fulfilling operator.** |
> | **Tier 4** — tax | Not started, and see §3.2 — the obligation accrues whether or not it is built. |
>
> §3's gap tables below are as-written on 2026-09-14 morning and have NOT been re-marked for
> Tier 0/1. Read this block for status; read §3 for the shape of what is missing.

> ## Read this first
>
> This document answers one question: *if Fuime wants to be a general-purpose merchant-of-record
> platform rather than a teen-only one, what is missing?*
>
> It is **not** a build order on its own. §2 lists defects in the product that is **already taking
> live money**, and those outrank every gap in §3. Building Paddle features on top of a platform
> that cannot pay its sellers would be building the second floor first.
>
> Nothing here is committed to. Two of the recommendations (§5 pricing, §6 audience) are business
> decisions that belong to the founder, not to this document.

---

## 1. The position, stated plainly

**Fuime today** is a single-currency, one-time-payment, US-only merchant-of-record checkout.
`Fuime::Offer` — name, price, slug — is the entire catalogue. It has a real fee engine
(`Event#fuime_fee_cents_on`), a real ledger inherited from HCB, a real hold-and-reserve policy,
a three-endpoint payment-links API, and a guardianship layer nothing else in the category has.

**Paddle** is a subscription billing platform that is also an MoR, selling into 229 countries,
33 currencies, 19 checkout locales, 17 payment methods, and tax registration in 100+ jurisdictions
**in its own name**. Its API has ~25 entity types and ~60 webhook event types.

The distance is larger than a feature list makes it look, because two of Paddle's assets are not
code at all:

1. **Tax registrations in 100+ jurisdictions.** This is a fixed opex block — registrations, filing
   software, indirect-tax staff, audit reserve — that does not scale with GMV. It is brutal at low
   volume and near-free at Paddle's. It is the actual moat, and it cannot be shipped in a sprint.
2. **Multi-acquirer interchange-plus acquiring.** It is why Paddle can charge one flat rate on an
   international card where Lemon Squeezy and Polar both surcharge +1.5%.

**The honest read:** Fuime cannot beat Paddle at Paddle's game in any timeframe that matters. It
can beat Paddle in the segment Paddle has explicitly priced itself out of — see §6.

### 1.1 ⚠️ Paddle's liability promise is marketing, not contract

Worth knowing before Fuime writes a single line of MoR copy, because the temptation is to
reproduce Paddle's phrasing.

Nine Paddle marketing and help pages say Paddle carries the tax risk — *"all the tax-related risk
rests with Paddle, not with you"*, *"We're liable for the non-compliance fines and penalties — not
you."* **The Master Services Agreement (`paddle.com/legal/terms`, updated 2025-10-08) contains no
reciprocal promise:**

- **Cl. 4.2** — the only tax indemnity runs **seller → Paddle**, triggered by the seller's own
  "Product Information", which cl. 9.4 defines to include **tax categorisation**. A mis-chosen tax
  category shifts the bill back to the seller.
- **Cl. 11.2** — a general seller → Paddle indemnity covering penalties, settlements and legal fees.
- **Cl. 12.3** — Paddle's aggregate liability is capped at **six months of its own fee revenue from
  that seller**, with carve-outs only for fraud, death/personal injury, and statutory implied terms.
  **No tax carve-out.** For a $500K/yr seller that cap is roughly $12.5K.
- **Cl. 8.1–8.3** — Paddle may set off "the whole or any part of the Supplier's liability" against
  funds owed, "at any time, without further notice… present or future, liquidated or unliquidated,
  actual or contingent."
- **Chargebacks follow the same pattern.** Disputes are filed against Paddle rather than the seller
  — but **cl. 10.4** recovers from the seller the full refund amount, all fees and expenses, **plus
  a fee of up to 20 GBP/USD/EUR or 40 AUD/CAD**, win or lose. MoR shifts the scheme relationship,
  not the money.

**Two things follow for Fuime.** First, this is the gap not to reproduce: if Fuime's copy promises
more than Fuime's terms deliver, that is the same exposure with none of Paddle's legal budget
behind it. Second, it is a genuine competitive opening — Fuime's terms already put the refund and
chargeback obligation on Fuime (`MOR_RISK_ACCEPTANCE.md` §4, terms §8), and *actually meaning it* is
a claim Paddle cannot match on paper.

---

## 2. Before any of this: defects in the live product

These are not Paddle gaps. They are the existing product, on live Stripe keys
(`render.yaml:118` `STRIPE_MODE=live`, `:143` `FEATURE_MERCHANT_OF_RECORD=true`).

| # | Defect | Evidence | Why it is first |
|---|---|---|---|
| **2.1** | **No payout rail exists.** `mark_paid!` flips state and posts a ledger debit. No `Stripe::Payout`, no `Stripe::Transfer`, no ACH originator anywhere in the app. | `app/services/fuime/payout_batch_service.rb:118-142` | Money comes in live and cannot go out. The ledger can say "paid" when no bank was credited. |
| **2.2** | **Sellers cannot attach a bank account.** `PLAID_ENV=sandbox` under live Stripe, so `Fuime::PlaidLinkService.collectable?` is false and the payout nav item is hidden. | `render.yaml:171-172`; `STRIPE_FEATURE_AUDIT.md:377-383` | Even once 2.1 is solved there is no destination to send to. |
| **2.3** | **Buyer address is collected and discarded.** `billing_address_collection: "required"` is set, but `PaymentWebhookHandler` persists no `customer_details`. | `payment_link_service.rb:107`; grep of `payment_webhook_handler.rb` | The code comment at `operator_eligibility.rb:59-66` claims nexus data "is already being captured." It is captured by **Stripe**, not by Fuime. Nothing in this app can compute a nexus threshold. Backfillable from Stripe's API — but only while those records are reachable. |
| **2.4** | **`Fuime::MissedMorPaymentSweep` is not scheduled.** `config/schedule.yml` has the settlement sweep, payout batch and guardian reminder jobs — not this one. | `config/schedule.yml` | If Stripe drops both success events, a founder's first sale silently never appears. Backfill is rake-only. |
| ~~2.5~~ | ~~`ProvisionConnectAccountJob` is ungated.~~ **Not a defect — already fixed.** `#perform` returns early under MoR (`app/jobs/fuime/provision_connect_account_job.rb:46`) and `ConnectOnboardingService#find_or_create_account!` raises `RetiredUnderMerchantOfRecord` as a second belt (`:238`). The enqueue in `Guardianship#accept!` is deliberately left in place per Rule 2. **`STRIPE_FEATURE_AUDIT.md:151` is stale on this point.** | verified in code 2026-09-14 | — |
| **2.6** | **Connect payout UI still renders and still fails.** "Ask my guardian → guardian approves" submits and errors with "hasn't finished payment setup yet", because `payment_account` is nil forever under MoR. | `app/controllers/fuime/payouts_controller.rb`; `STRIPE_FEATURE_AUDIT.md:136-137` | A dead path that a real user can walk into. |
| **2.7** | **No seller-facing refund mechanism**, while `_operator_sale_terms.html.erb` promises buyers a 14-day refund window. Refunds must be issued from the Stripe Dashboard by hand. | grep `Stripe::Refund` across `app/` — only in disabled modules | A promise in the terms with no operational path behind it. |
| **2.8** | **Stripe processing fee is never itemised under MoR.** `VentureLedger.processing_fee_key` has exactly one caller, on the Connect path. | `venture_ledger.rb:59`; `connect_payment_recorder.rb:217` | The payouts breakdown renders a processing-fee row that is always $0. |

### 2.9 Status as of 2026-09-14

| Item | State |
|---|---|
| 2.1 payout rail | **Decided 2026-09-14: manual transfers, honest ledger.** `mark_paid!` now requires a `transfer_reference` and refuses without one; the admin form collects it and a paid run displays it. The money is still sent by hand from the bank — that is the deliberate choice, not an omission. **Written, unverified.** |
| 2.2 Plaid sandbox under live Stripe | **Still open.** Sellers cannot attach a bank account. Manual transfers need a destination, so this is the next thing that actually blocks a payout. |
| 2.3 buyer jurisdiction discarded | **Written, unverified.** `fuime_sale_jurisdictions` + `Fuime::SaleJurisdiction` + capture in `PaymentWebhookHandler#record_jurisdiction`. Migration not run and no spec executed — see §2.10. |
| 2.4 sweep not scheduled | **Written, unverified.** `Fuime::MissedMorPaymentSweepJob` + hourly `config/schedule.yml` entry. |
| 2.5 ungated Connect job | **Not a defect.** Already gated. |
| 2.6 dead Connect payout UI | Open. |
| 2.7 no seller refund path | Open. |
| 2.8 processing fee never itemised | Open. |

### 2.10 ⚠️ Nothing in 2.3 or 2.4 has been executed

The local environment cannot run this app: Docker's daemon is down, and the only
Ruby on the machine besides 4.0.6 is 3.4.10 while the Gemfile pins **3.4.9**.
So `db:migrate` has not run, `rspec` has not run, and the schema has not been
regenerated. All four files parse (`ruby -c`) and the schedule entry is
structurally identical to its neighbours — that is the entire extent of the
verification. **Treat 2.3 and 2.4 as unreviewed drafts until the suite runs.**

**2.1 — decided.** Manual bank transfers, with the ledger made honest about it. The alternatives
were Connect recipient-only accounts (reintroduces Connect, which was just retired) and a dedicated
ACH originator (Increase/Column — currently disabled by Milestone 2's safety rails, and it needs
underwriting conversations before a dollar moves). Manual is legitimate at this volume; what was
not acceptable was a ledger asserting payments nobody made.

So `mark_paid!` — the only thing in the system that debits an operator's ledger — now takes a
mandatory `transfer_reference` and raises `MissingTransferReference` without one. It is not
format-validated: Fuime does not know what a given bank's reference looks like, and a shape rule
would only teach people to type around it. **Requiring a trip to the bank is the control; the
string is the audit trail.** Runs marked paid before this say so explicitly rather than rendering
blank.

**This does not make Fuime able to pay anyone.** It makes the record true. The remaining blocker is
2.2 — with `PLAID_ENV=sandbox` there is no destination to send to, which is now the top of the
queue.

---

## 3. The gap table

Status key: **⛔ absent** · **◐ partial** · **✅ present** · **🔒 built but flagged off**

### 3.1 Recurring billing — the largest gap

Paddle's core. Fuime has none of it, deliberately (`MOR_RISK_ACCEPTANCE.md` §8: *"They do not
exist and were not added"*). `Fuime::Offer` has no interval; `PaymentLinkService` uses
`mode: "payment"`.

| Capability | Paddle | Fuime |
|---|---|---|
| Subscriptions at all | ✅ | ⛔ |
| Arbitrary billing cycles (`{interval, frequency}` — every 3 months, every 2 weeks) | ✅ | ⛔ |
| Multi-item subscriptions | ✅ up to 100 items | ⛔ |
| Seats / quantity | ✅ per-item `quantity`, min/max per price | ⛔ (`quantity: 1` hardcoded) |
| Upgrade / downgrade | ✅ | ⛔ |
| **Proration** | ✅ to the minute, 5 modes (`prorated_immediately`, `full_immediately`, `prorated_next_billing_period`, `full_next_billing_period`, `do_not_bill`) | ⛔ |
| **Preview a change before committing** | ✅ `PATCH /subscriptions/{id}/preview` returns exact financial impact | ⛔ |
| Free trials | ✅ + `requires_payment_method: false` for cardless | ⛔ |
| **Paid trials** | ✅ trial and recurring share one `price_id` | ⛔ |
| Pause / resume | ✅ scheduled or open-ended, with resume-billing choice | ⛔ |
| Cancel at period end vs immediately | ✅ | ⛔ |
| Scheduled changes | ✅ `scheduled_change` with `effective_at` | ⛔ |
| One-time charge on a subscription | ✅ `POST /subscriptions/{id}/charge` | ⛔ |
| Change billing date / currency / collection mode | ✅ all three | ⛔ |
| Subscription audit history | ✅ full log: action, source, actor, reason | ⛔ |
| **Usage-based / metered billing** | ⛔ **Paddle does not have this either** — see §7 | ⛔ |

**Note:** Fuime *does* have `Fuime::SubscriptionService` and `Fuime::Subscription` — but those are
Fuime billing **families** for its own $19.99 plan on the platform account. They are not a facility
for sellers to bill their customers. The code is a useful reference for the seller-facing version,
not a starting point.

### 3.2 Tax — the moat

| Capability | Paddle | Fuime |
|---|---|---|
| Sales tax / VAT / GST of any kind | ✅ | ⛔ **nothing** |
| Registered in own name | ✅ 100+ jurisdictions | ⛔ registered nowhere |
| Calculation at checkout | ✅ | ⛔ (no `automatic_tax`, no Stripe Tax) |
| Filing and remittance | ✅ | ⛔ |
| **Liability** | ✅ Paddle's | ⛔ Fuime's, unmanaged |
| Product tax categories | ✅ 9-value enum (`standard`, `saas`, `digital-goods`, `ebooks`, `website-hosting`, `implementation-services`, `professional-services`, `software-programming-services`, `training-services`) | ⛔ |
| Tax-inclusive vs exclusive | ✅ 4 modes incl. `location` (auto: inclusive in EU-style markets, exclusive in US-style) | ⛔ |
| VAT ID collection at checkout | ✅ creates a `business` entity | ⛔ |
| B2B reverse charge | ✅ | ⛔ |
| US exemption certificates | ✅ via buyer support | ⛔ |
| Post-purchase tax correction | ✅ revise transaction, auto-adjustment, revised invoice PDF | ⛔ |
| Tax invoice / credit note PDFs | ✅ per transaction / per adjustment | ⛔ |
| Per-rate breakdown (`tax_rates_used[]`) | ✅ on transactions and adjustments | ⛔ |

**Fuime's only tax code is `Fuime::TaxTrackerService`, and it is a different thing entirely** — an
*income*-tax estimator for the teen (IRS $400 self-employment threshold, Schedule SE factor),
classifying transactions by memo substring. It states at line 16: *"State income tax, sales tax,
and 1099-K reporting are not modelled."* It is never touched by checkout or the ledger.

**The live exposure, from `MOR_RISK_ACCEPTANCE.md` §7:** digital goods were allowed on 2026-08-20.
~30 US states tax digital goods and SaaS. Under MoR that nexus accrues against **Fuime's single
entity**, not against individual sellers. Economic-nexus thresholds are commonly $100K or 200
transactions per state per year, and **the obligation attaches from the transaction that crosses
it**, not from the day somebody notices.

**International makes this sharper, not softer.** EU VAT on digital goods to consumers is owed
**from the first euro — there is no threshold**. Any deliberate move toward Paddle's market is a
move into that obligation.

**The cheapest correct next step is §2.3 plus a nexus report** — persist the buyer's
state/country, count toward thresholds, and register where Fuime crosses. That is small code and
it is the input to every other decision here. `MOR_MIGRATION_PLAN.md:354` already plans a
`Fuime::NexusReportService`; it was never written.

### 3.3 Catalogue and pricing

| Capability | Paddle | Fuime |
|---|---|---|
| Products separate from prices | ✅ many prices per product | ⛔ one price on the Offer |
| Multi-currency | ✅ 33 | ⛔ USD hardcoded (`payment_link_service.rb:83,162`) |
| Automatic currency conversion at checkout | ✅ | ⛔ |
| **Country-specific price overrides** | ✅ `unit_price_overrides[]`, up to 250 entries | ⛔ |
| Purchasing-power-parity pricing | ◐ via overrides — you set the numbers | ⛔ |
| Discounts / coupons | ✅ percentage, flat, flat-per-seat; usage limits; expiry; product restriction | ⛔ (no `allow_promotion_codes`, no `Stripe::Coupon`) |
| Discount groups (campaigns) | ✅ | ⛔ |
| Non-catalogue / inline items | ✅ | ◐ free-amount path when no offer named |
| Quantity selector at checkout | ✅ | ⛔ |
| Cart / multi-item | ✅ | ⛔ one line item per session |
| Variants / SKUs / inventory | ⛔ Paddle doesn't have these either (digital-only) | ⛔ |

### 3.4 Checkout

| Capability | Paddle | Fuime |
|---|---|---|
| Hosted checkout | ✅ | ✅ Stripe-hosted redirect |
| **Overlay checkout** (modal over the seller's own page) | ✅ + HTML data-attribute API | ⛔ |
| **Inline / embedded checkout** | ✅ 50+ no-code styling options | ⛔ |
| **Express checkout** (wallet-first, no form) | ✅ | ⛔ |
| **Post-purchase upsell** | ✅ one-click within 5 min of the original transaction | ⛔ |
| Drop-in React components | ✅ shadcn registry: pricing cards, interval toggle, checkout, plan-change preview | ⛔ |
| Custom domains for checkout | ✅ with review lifecycle + Apple Pay domain verification | ⛔ |
| Seller branding on checkout | ✅ extensive | ◐ logo + tagline on Fuime's own pages; Stripe Checkout carries Fuime's branding by MoR design |
| Localization | ✅ 19 locales | ⛔ `en.yml` only |
| Payment methods | ✅ 17, toggled without code | ◐ **not configured in code at all** — inherits whatever the Stripe Dashboard has |
| Wallets (Apple/Google Pay) | ✅ | ◐ same — unknown to this repo |
| Abandoned-cart recovery | ✅ one email at 60 min, optional auto-discount, 10–30% claimed recovery | ⛔ for buyers (there *is* an abandoned-draft series for founders) |
| Saved payment methods | ✅ with explicit consent capture | ⛔ |
| Regional compliance automation (FTC Negative Option, Korea renewal consent, one-click cancel) | ✅ automatic | ⛔ |

### 3.5 Post-purchase and the buyer

| Capability | Paddle | Fuime |
|---|---|---|
| **Buyer account / portal** | ✅ Paddle-hosted, magic link, zero setup, 19 locales | ⛔ **no buyer entity exists** — buyer identity lives only in Stripe |
| Itemised purchase history + one-click PDF | ✅ | ⛔ |
| Manage / cancel subscription self-serve | ✅ | ⛔ |
| Update expired card self-serve | ✅ | ⛔ |
| Refunds initiated by the seller | ✅ (Paddle-approved above ~$400) | ⛔ Stripe Dashboard only |
| Refund *ingestion* into the ledger | — | ✅ `charge.refunded` posts a reversal + proportional fee rebate |
| Disputes: evidence submission, UI, model | ✅ automated Dispute Defense + pre-chargeback alerts | ⛔ |
| Dispute *ingestion* | — | ◐ `charge.dispute.created` posts a negative line; no `.closed`/`.updated` handling |
| Credit notes | ✅ PDF per adjustment | ⛔ |
| License keys / entitlements / fulfillment | ⛔ **Paddle removed this in Billing** | ⛔ |
| **Receipts and comment threads on a sale** | ⛔ Paddle has nothing like it | ✅ every sale becomes an `HcbCode` — receipt upload, receipt-bin pairing, mailbox forwarding, threaded comments, all free |

### 3.6 Dunning and revenue recovery

Paddle's baseline alone retries a failed payment 7 times over 30 days. **Paddle Retain** adds ML
retry retiming, 4 whitelabelled emails, in-app and pre-dunning notices, SMS via Twilio, a no-login
card-update form, and a 5-step cancellation flow with automated salvage offers (switch plan, pause,
discount, book a call). Sold standalone from $500/month.

**Fuime has none of this, and cannot have any of it until §3.1 exists** — there is no failed
recurring payment to recover. `SubscriptionWebhookHandler` handles only
`customer.subscription.created/updated/deleted`; there is no `invoice.payment_failed` path even for
Fuime's own family plan.

### 3.7 Analytics

| Capability | Paddle | Fuime |
|---|---|---|
| MRR / ARR | ✅ | ⛔ (nothing recurring to compute from) |
| MRR waterfall (new/expansion/contraction/churn/reactivation) | ✅ | ⛔ |
| Churn, LTV, ARPU, NRR | ✅ | ⛔ |
| Cohort retention heatmap | ✅ | ⛔ (`Fuime::Cohort` is an admission batch, not a retention cohort) |
| Segment comparison, by-plan comparison | ✅ | ⛔ |
| Revenue over time | ✅ | ⛔ **the only time-bucketed chart in the app is the admin waitlist sparkline** |
| Top products | ✅ | ⛔ (`Fuime::Offer` has no sales association or counter) |
| Checkout conversion | ✅ | ⛔ `ahoy_matey` is in the Gemfile with **zero `ahoy.track` calls** |
| Refund rate / chargeback rate dashboards | ✅ | ⛔ |
| Ad-hoc exploration | ✅ Explore UI + Metrics API | ◐ Blazer (raw SQL, auditors only) |
| CSV reports | ✅ 10 types, incl. a very detailed payout reconciliation | ◐ tax packet, admin waitlist, HCB transaction export. No sales, payout-history or buyer export |
| Spend-side analytics | — | ✅ inherited HCB Insights: merchants, categories, tags, heatmap |

**Fuime's seller-side reporting is balances plus *spend* breakdowns plus an income-tax estimate.
It is not commerce analytics.** The three-number strip is "Owed to you / Total revenue / Total
expenses."

### 3.8 Developer surface

| Capability | Paddle | Fuime |
|---|---|---|
| API breadth | ✅ ~25 entities, full CRUD | ◐ **3 endpoints** (`/me`, `/payment_links` CRUD-lite) |
| **Outbound webhooks to sellers** | ✅ ~60 event types, at-least-once, HMAC-SHA256, 60 retries over 3 days, 10 destinations, replay | ⛔ **no table, no deliverer, no signer, no retry queue** — grep `webhook` in `db/schema.rb` returns nothing |
| Server SDKs | ✅ Node, Python, Go, PHP | ⛔ (a copy-pasteable curl on the Developer page) |
| Browser SDK | ✅ Paddle.js + TypeScript types | ⛔ |
| OpenAPI spec / Postman | ✅ | ⛔ |
| API reference docs | ✅ extensive, with `.md` siblings and `llms-full.txt` | ⛔ (HCB's V3 Stoplight viewer is mounted but documents HCB's transparency API) |
| Sandbox | ✅ full separate account, test cards, Test Mode watermark | ⛔ **no API sandbox** — a developer testing `/api/fuime/v1` hits the production data path |
| Webhook simulator / scenario replay | ✅ multi-event lifecycle scenarios with real entities | ⛔ |
| API key scopes | ✅ 38 | ⛔ (the key *is* the venture; no scopes, no rotation, no test-vs-live keys) |
| Key expiry, rotation, secret scanning | ✅ incl. AWS Secrets Manager + GitHub exposure alerts | ⛔ |
| Idempotency keys | ⛔ **Paddle doesn't have them either** | ⛔ |
| MCP server + agent tooling | ✅ remote MCP, Claude Code plugin, agent skills, `llms.txt` | ⛔ |

Fuime's API does have real virtues worth keeping: the key is structurally scoped to one venture
(no route or body anywhere carries an event id), it can only *ask* for money — never move it out,
read the ledger, or see PII — and it is rate-limited at 120/min. That is a better security posture
than Paddle's by default. It is just very small.

---

## 4. What Fuime has that Paddle does not

Not consolation prizes — several of these are why a different customer would choose Fuime.

1. **Guardianship as a first-class legal object.** Versioned agreements (now v4), signature IP/UA,
   revocation, invite tokens, reminder cron. Resolved through `EventPolicy` so a guardian reads the
   ledger and decides payouts but cannot set prices.
2. **Receipts and threaded comments on every sale**, inherited from HCB's ledger. Paddle has
   nothing comparable.
3. **Hold and reserve policy expressed as product**, with a stated per-operator reason for every
   skipped payout — not fine print.
4. **Human operator vetting** before a venture may sell, plus a category allowlist.
5. **Full admin console, audit log, Blazer.**
6. **Card issuing, built and deliberately off** — `Fuime::CardSpendPolicy` is a network-level MCC
   allowlist implementing Celtic Bank's Authorized User Terms.
7. **Income-tax tracker and parent packet** — a teaching tool, not a compliance product.
8. **Playground and demo sandbox**, safe under live keys.
9. **School / institutional mode** — pooled accounts, awards with 1099-MISC, per-student balance
   capping.
10. **Transparency mode** — a venture can publish its full ledger.

---

## 5. Pricing

### 5.1 What the market actually charges

| Provider | Rate | Surcharges | Monthly |
|---|---|---|---|
| **Paddle** | 5% + 50¢ | none published | $0 |
| **Lemon Squeezy** | 5% + 50¢ on tax-inclusive total | +1.5% intl, +1.5% PayPal, +0.5% subscriptions | $0 |
| **Polar** (repriced 2026-05-27) | 5% + 50¢ free tier | +1.5% intl | $0 |
| Polar Pro / Growth / Scale | 3.8% / 3.6% / 3.4% | +1.5% intl | $20 / $100 / $400 |
| **Gumroad** | 10% + 50¢ | — | $0 |
| **Stripe Managed Payments** | +3.5% on top of processing (≈6.4% + 30¢ US) | APM rates on top | $0 |
| Stripe raw (not MoR) | 2.9% + 30¢ | +1.5% intl, +1% FX | $0 |
| **Fuime today** | **7%, 50¢ minimum** | none | $0 Free / $19.99 Pro |

**5% + 50¢ is an industry convention, not Paddle's rate.** Three independent MoRs landed on it to
the cent. Copying it copies the market.

### 5.2 The margin arithmetic

At Stripe's list price, on a US domestic card with no tax:

| Order | Fee at 5% + 50¢ | Effective take | Stripe cost | Margin |
|---|---|---|---|---|
| $10 | $1.00 | **10.00%** | $0.59 | $0.41 |
| $50 | $3.00 | 6.00% | $1.75 | $1.25 |
| $200 | $10.50 | 5.25% | $6.10 | $4.40 |
| $1,000 | $50.50 | 5.05% | $29.30 | $21.20 |

Margin as a share of fee is flat at ~41–42% at every size — the rate card is close to a uniform
1.7× markup on Stripe list. What swings is the take rate the seller *feels*.

**On an international card at Stripe list prices, 5% + 50¢ is margin-negative** (a $200 order costs
$11.10 against a $10.50 fee). Paddle absorbs this because it runs multi-acquirer interchange-plus.
Lemon Squeezy and Polar both surcharge +1.5% because they cannot.

### 5.3 Recommendation — SUPERSEDED 2026-09-14

**The founder decided on one flat 5% + 50¢ with no monthly fee, and it shipped.** Custom pricing
is a sales conversation rather than a tier. The reasoning below argued for holding at 7% and is
kept because its *arithmetic* still governs: the 50¢ floor is what makes small baskets viable, the
sub-$25 comparison is still the strongest pitch against Paddle, and the tax point in (2) is
unchanged and still unfunded.

One correction the repricing surfaced, which strengthens the position: **Fuime absorbs Stripe's
2.9% + 30¢ rather than charging it to the seller** — the site had claimed otherwise and was
overstating seller cost by roughly three points. So Fuime's 5% is genuinely all-in, where Lemon
Squeezy and Polar both surcharge international and PayPal on top of theirs.

*Original recommendation, for the record:*

**Do not cut to 5% yet.** Three reasons:

1. **It buys nothing.** A seller choosing Paddle at 5% is buying the tax liability transfer.
   Fuime does not offer that at any price. Cutting to match means 29% less revenue for the same
   hard sell.
2. **The tax obligation is growing while the rate would shrink.** §3.2 — the nexus is accruing now
   and remediation costs real money.
3. **Fuime's orders are small, where the 50¢ dominates.** At a $12 sale, 5% + 50¢ is 9.2% —
   *higher* than today's flat 7%. A flat percentage is genuinely better for small baskets, and the
   50¢ floor already covers the sub-$7.32 break-even.

**When repricing does happen, tier it the way Polar does** — a lower rate behind a monthly plan.
That is the shape Fuime already has with Free and Pro at $19.99. Paddle's flat, no-monthly-fee
model would mean abandoning Pro, not extending it.

**And surcharge international rather than matching Paddle's flat rate.** Fuime will not have
Paddle's acquiring costs.

---

## 6. The wedge: Paddle has priced itself out of Fuime's market

From Paddle's own pricing page: **"If you're selling products under $10 or require invoicing,
contact us for custom pricing."**

Paddle does not want small baskets, because 50¢ fixed makes the effective take 10% at $10. That is
exactly what Fuime's sellers sell. So the segment is not a consolation prize for losing to Paddle —
it is a segment Paddle actively declines.

Combine that with the other structural facts:

- **A flat 7% with no fixed fee beats 5% + 50¢ on every order under $25.** That is a real,
  defensible pricing argument Fuime can make today, with no new engineering.
- **Adult sellers reduce legal risk.** `MOR_RISK_ACCEPTANCE.md` Q2 — whether umbrella MoR breaks the
  independent-contractor characterisation — is flagged as the **highest unreviewed risk**, and it is
  FLSA child-labor territory precisely *because* the operators are 13–17. That question simply does
  not arise for an adult seller. Broadening the audience is risk-reducing, not risk-adding.
- **The model already represents adults.** `age_attestation: adult_18_plus` and a `:adult` persona
  exist (`app/models/user.rb:105, 955`). What gates adults out is `Fuime::OperatorEligibility`'s age
  floor, the guardianship requirements, the `services digital` category allowlist, and copy — not
  the schema.

**Suggested framing:** not "Paddle for teens," and not "Paddle but cheaper." Something closer to
*the MoR for small-ticket sellers* — with the teen/guardian product as the flagship vertical rather
than the whole company. That keeps every existing asset and stops requiring Fuime to win a fight it
cannot win.

---

## 7. Paddle's own gaps — where a competitor has room

Verified absences in Paddle's documented surface:

1. **No native usage-based or metered billing.** No usage records API, no tiered/graduated/volume
   pricing, no quota enforcement. Their documented workaround is external metering plus custom line
   items. This is the largest unclaimed territory in the category.
2. **No client-supplied idempotency keys.** Their guidance is to list-before-retry.
3. **No promotional or manual credits** — credits exist only as a by-product of proration.
4. **No seller-configurable fraud rules** — no blocklists, velocity rules, or review queue.
5. **Refunds gated on Paddle approval** above ~$400 on live accounts.
6. **Pause is not self-serve** in the customer portal.
7. **Cancellations are irreversible** — no reinstatement.
8. **Invoicing is USD/EUR/GBP only**; no quotes object; no partial payments.
9. **Discounts do not stack**; no per-customer usage limits.
10. **No mobile SDKs** — mobile is browser link-out only.
11. **Explore data is 24h stale**; ProfitWell Metrics 3–6h.
12. **Sub-$10 products require custom pricing** — see §6.

---

## 8. Suggested build sequence

Each tier assumes the one above it. Tier 0 is not optional.

**Tier 0 — stop the bleeding.** §2, all of it. The rail decision (2.1/2.2) first; 2.3, 2.4, 2.5 are
each an hour or two. Nothing new gets built until a seller can be paid and the ledger stops
asserting payments that did not happen.

**Tier 1 — recurring billing for sellers.** §3.1. The single highest-value build, and the
prerequisite for §3.6 dunning and most of §3.7 analytics. Scope: an interval on `Fuime::Offer`,
`mode: "subscription"` on the checkout, `customer.subscription.*` and `invoice.*` wired to the
ledger, and Stripe's **hosted** billing portal for buyers — do not build a portal, you already use
the hosted one for family billing.

**Tier 2 — sales analytics on existing data.** §3.7, the subset that does not need recurring:
revenue over time, per-offer revenue, AOV, refund rate, repeat purchase. Two blockers first —
`Fuime::Offer` needs a sales association and counter, and `ahoy.track` calls need to exist for
conversion to be computable at all. This is where the dashboard design work lands.

**Tier 3 — outbound webhooks.** §3.8. The first-order developer gap and the thing that lets anyone
build *on* Fuime. Table, signer (HMAC-SHA256), retry queue, replay, a destinations UI.

**Tier 4 — tax, incrementally.** Persist jurisdiction (Tier 0), build the nexus report, register
where Fuime has crossed, then add Stripe Tax calculation at checkout. Full Paddle-parity is an
opex programme, not a sprint, and should not be attempted as one.

**Not sequenced here:** the marketing-site work. It is independent of all of the above and can run
in parallel — see `docs/fuime/` for the design teardown if one gets written up.

---

## 9. Uncertainty log

- ~~**Paddle's fee base**~~ — **resolved.** The MSA (cl. 3.1) computes the fee on the
  **tax-inclusive** total, with Paddle's own worked example: UK buyer, $120 order, $20 VAT, fee
  $6.50, seller earns $93.50. You pay 5% on the tax too. If Fuime bills on net, that is free margin
  available — but it is also the thing that gets MoRs accused of hidden fees, so document it.
- **Paddle's invoicing rate is 3.5%, and is not on the pricing page** — MSA cl. 3.2, where payment
  is by bank transfer. The public page only says "contact us."
- **Paddle's custom-pricing volume threshold** — every figure circulating is third-party.
- **Paddle Retain's performance-based percentage** — only the $500/mo floor is public.
- **FastSpring publishes no rates at all** in 2026.
- **Lemon Squeezy's forward status** is changing right now — Stripe-owned, pointing customers at
  Stripe Managed Payments, signup appears waitlist-gated. Re-check before citing.
- **Paddle rolling reserves** — no documentation found.
- **Paddle VAT ID validation method** (VIES or otherwise) — not stated.
- **Fuime's payment methods and wallets** are genuinely unknown to this repo — they are whatever the
  Stripe Dashboard has enabled, and no code asserts them.

## 10. Sources

Fuime: verified against `main` at the file:line citations above, plus `render.yaml`,
`config/schedule.yml`, `MOR_RISK_ACCEPTANCE.md`, `STRIPE_FEATURE_AUDIT.md`, `MOR_MIGRATION_PLAN.md`.

Paddle: `developer.paddle.com/llms-full.txt` (the full docs corpus, read directly rather than
scraped), `paddle.com/pricing`, `paddle.com/help/*`, `paddle.com/compare/*`. Competitor rates from
`docs.lemonsqueezy.com/help/getting-started/fees`, `polar.sh/docs/merchant-of-record/fees`,
`gumroad.com/pricing`, `stripe.com/pricing`, `support.stripe.com/questions/managed-payments-pricing`,
`docs.whop.com/fees`, `chargebee.com/pricing`, `recurly.com/pricing`.
