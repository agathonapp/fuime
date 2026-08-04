# Fuime — Launch Specification

**What this is:** everything that must be true before Fuime accepts its first real
teenager, real parent, and real dollar. Written 2026-08-01 against `main` @ `33b11bfb8`.

**Read this first:** Fuime's users are **children**, and its product is **money plus
tax guidance**. That combination means most items below are legal obligations wearing
software costumes. You cannot ship your way past §1 or §2 — those need a lawyer, a CPA,
and signed agreements with providers. Everything in §3 onward is engineering that is
worthless until §1 and §2 are resolved, because §2 determines *which* engineering.

**How to use it:** §0 is the go/no-go checklist. §1–§2 are the blocking decisions. §3
is every API key with what it costs and how to get it. §4 is the feature work. §5 is
sequencing. §6 is what "launch" actually means on day one.

---

## §0. The go/no-go checklist

Nobody signs up until every box is ticked.

**Legal**
- [ ] Money-transmission structure decided in writing by counsel (§1.1)
- [ ] Entity formed; EIN issued; business bank account open (§1.2)
- [ ] Terms of Service, Privacy Policy, Guardian Agreement, E-SIGN consent — all drafted by counsel and live on Fuime domains (§1.3)
- [ ] COPPA posture decided and implemented (§1.4)
- [ ] Insurance bound: E&O / cyber / general liability (§1.5)
- [ ] CPA has reviewed every number and every word on `/taxes` (§1.6)

**Provider**
- [ ] Stripe account approved for the chosen structure, with the teen-users model disclosed in writing (§2.1)
- [ ] Identity verification vendor contracted and integrated (§2.2)
- [ ] Sending domain verified; DKIM/SPF/DMARC passing (§3.4)

**Engineering** *(status updated 2026-08-04 — see §0.5)*
- [ ] All §3 credentials set in Render for **both** `fuime-web` and `fuime-worker`
- [x] S3 configured — boot now refuses to start on `:local` (§3.2)
- [ ] Error tracking live with alerting (§3.5)
- [~] Payments wired end to end — **built and unit-tested, never run against Stripe** (§4.1).
      Not tickable until a `stripe listen` pass in test mode, then real cards.
- [~] Guardian identity verification — **collection exists, verification does not** (§4.2).
      No vendor decision gate, so activation is not yet blocked on it.
- [ ] Data export + deletion working (§4.6)
- [~] Test suite green with a recorded baseline — **573 examples, 1 known failure** on the
      Fuime subset (`known-failures.md`). The full repo suite has not been run.
- [ ] Backup restore rehearsed, not just configured (§4.9)
- [ ] **Stripe's three open questions answered in writing** (`LEGAL_RESEARCH.md`). Gates the
      card path entirely, and one of them gates payouts.

**Operational**
- [ ] Support inbox staffed with a written response-time commitment
- [ ] Incident runbook: who is called, in what order, for a money bug
- [ ] Someone on call who can freeze payments within minutes

---

## §0.5. Where we actually are — updated 2026-08-04, after PR #28

The checklist above was written when none of the money code existed. It now does, in test
mode. This section is the honest position so nobody re-derives it.

### Built and tested (573 examples, 1 known failure)

A venture can be onboarded onto a **guardian-owned Stripe connected account**, publish a
storefront, take a **direct charge**, and have that charge land on the ledger with all
three deductions visible (gross, Fuime's application fee, Stripe's processing fee). A teen
can **request a payout**, a guardian approves it, and Stripe sends it to the family's own
bank. Refunds, disputes, failed payouts and cancelled payouts all reverse correctly. The
tax tracker counts what it should and excludes what it should.

Cards exist behind a flag: a **category allowlist** enforcing business-purchases-only, the
guardian as **Accountholder** and the teen as **Authorized User**, freeze available to the
teen but unfreeze only to the guardian, and card spend flowing back onto the ledger.
Guardian identity collection exists as **collect-and-forward** — values go straight to
Stripe, the ID image goes to Stripe's Files API, and Fuime persists only the consent record.

**Fuime is never in the flow of funds.** That is the single most important property and it
is now structural rather than aspirational.

### The one sentence that matters most

**Nothing here has been exercised against Stripe, in any mode.** Every webhook payload
shape and API parameter set was written from Stripe's documentation. Two of the three bugs
PR #28 fixed were invisible until code was actually run.

### Specifically unverified, in order of how badly it hurts to be wrong

1. **`payouts.schedule.interval = manual`.** If Stripe refuses it on a Stripe-liable
   account, the guardian approval gate is decorative *and* `Stripe::Payout.create` fails
   outright. The entire payout feature rests on this.
2. **Issuing underwriting.** Whether a teen sole-prop with a guardian representative is a
   supported Issuing use case, or gets classed as consumer. Can invalidate the whole card
   path. This is open question 3 in `LEGAL_RESEARCH.md`.
3. **A mixed `losses.payments` fleet.** The `:cards_enabled` profile assumes a platform can
   run Stripe-liable and application-liable accounts side by side. That is an
   **inference**, not a documented Stripe pattern.
4. Every webhook payload shape, collectively.

### What is deliberately inert

Cards deploy dead: gated behind `Flipper.enabled?(:fuime_cards_2026_08_04, event)`, off by
default, and unreachable for every existing venture because Stripe's `controller` property
is create-only and all current accounts are payments-only. A `:cards_enabled` account puts
**Fuime on the hook for every chargeback on a minor's business**, which is a
capitalisation decision, not a product toggle.

### Corrected understanding worth carrying forward

Earlier planning assumed a minor's age was the obstacle to cards. It is not. Stripe's
Issuing cardholder floor is **13**, and Celtic Bank's Authorized User Terms carry **no
minimum age at all**. What is actually restricted is *what the card buys* — "you may not
use your card for personal, family or household purposes" — which is why the enforcement
lives in a category allowlist rather than in an age check. Nothing needed to be withheld
from Stripe; the compliant structure was more permissive than the assumption.

---

## §1. Legal — the things no code can close

### 1.1 Money transmission structure — THE decision

Everything else depends on this. Fuime proposes to receive customer payments and
allocate them to teen businesses. Holding funds that belong to someone else is
**money transmission**, and doing it unlicensed is a felony in most states.

HCB can pool funds because Hack Club is a 501(c)(3) that legally *owns* what it holds
for its fiscally-sponsored projects. Fuime is not a fiscal sponsor and the teens are
not its projects — so Fuime would be holding other people's money. That is the whole
problem.

Three viable structures:

| Structure | What it means | Time | Cost |
|---|---|---|---|
| **Stripe Connect, guardian as connected account** ← recommended | The parent's verified identity *is* the merchant. Stripe does KYC and payouts. Funds never sit in a Fuime-controlled pool. | Weeks | Stripe fees only |
| Money transmitter licences | Fuime holds funds directly, licensed in ~49 states | 12–24 months | Seven figures + surety bonds |
| Merchant of record | Fuime genuinely sells the goods and remits to teens | Months | Sales-tax nexus everywhere; different liability entirely |

**Strong recommendation: Stripe Connect with the guardian as the connected account
holder.** It is *less* code than what exists today. It makes "your parent is the legal
signer" literally true instead of decorative. It deletes the pooled-account problem,
the fronting problem, and most of the payout risk. It also means the parent — an adult
who can legally contract — is the one Stripe has verified.

**Deliverable:** a written memo from counsel naming the structure. Everything in §4.1
is on hold until it exists, because the answer rewrites the money code.

### 1.2 Entity, EIN, banking
- [ ] Entity formed (Delaware C-corp or LLC — ask counsel)
- [ ] EIN from the IRS (free, ~15 min online)
- [ ] Business bank account (Mercury/Brex are the usual startup picks)
- [ ] Registered agent
- [ ] State registrations wherever you have nexus

### 1.3 The agreements

All four drafted by a lawyer who has read the COPPA rule. Do not use a template
generator for a product that serves minors and handles money.

1. **Terms of Service** — who may use Fuime, what Fuime does and does not do,
   the fee, dispute handling, termination, what happens to money on termination.
2. **Privacy Policy** — COPPA-compliant. What is collected from a minor, why, who it
   is shared with, retention, and the parent's rights to review and delete.
3. **Guardian Agreement** — the legal core. The adult accepts responsibility for the
   minor's account and business. Versioned; the code already stamps
   `agreement_version`, IP, and user agent at signature (`Guardianship#accept!`).
4. **E-SIGN consent** — required for electronic signatures to bind.

> **Live bug:** [config/routes.rb:694](config/routes.rb#L694) — `/privacy` currently
> **redirects to `hackclub.com/privacy-and-terms/`**. Fuime is today pointing its users
> at another organisation's privacy policy. That is a misrepresentation and must be
> fixed before any real signup.

### 1.4 COPPA
Under-13 users trigger Verifiable Parental Consent, which is a heavy, audited process.

**Recommendation: hard 13+ floor, never collect under-13 data.** Already implemented
(`User#minimum_age_requirement`), and the DOB is now mandatory to finish onboarding so
the check cannot be skipped. Confirm this posture with counsel and write it down.

Also required regardless: state minor-privacy laws (CA AADC and equivalents), data
deletion rights, and a parent's right to review what has been collected.

### 1.5 Insurance
E&O / professional liability · cyber liability (you hold minors' PII and financial
records) · general liability · D&O if you have a board. Get quotes early; underwriters
ask hard questions about the minors-plus-money combination and it takes time.

### 1.6 CPA review of the Tax Tracker
The arithmetic is now correct and tested — the $400 threshold applies to net earnings
(net profit × 0.9235, so ~$433.14 of profit), income is classified rather than
"every positive line," and all copy is hedged as estimates.

**But correct arithmetic is not correct advice.** A CPA must review:
- the income classification heuristic (it is memo-pattern matching, which is a stopgap)
- the year-end packet's contents and wording
- whether the quarterly-estimates warning is right for this population
- every user-facing sentence on `/taxes`

---

## §2. Provider approvals

### 2.1 Stripe — disclose the teen-user model in writing
Stripe's own terms generally require account holders to be 18+. **Do not discover this
after launch.** Contact Stripe sales/compliance *before* building, explain the
structure from §1.1, and get written confirmation. Under the recommended Connect model
the account holder is the parent, which is precisely why that model is the safe one.

Ask them explicitly about: the connected-account structure, KYC on guardians, payout
timing, chargeback liability, and their Restricted Businesses list.

### 2.2 Identity verification vendor
Required by §4.2. **Stripe Identity** (~$1.50/verification) composes best if you are
already on Connect. **Persona** and **Onfido** are the alternatives. You need it for
guardians; decide with counsel whether teens need a lighter check too.

---

## §3. Every API key and service

Set in Render for **both** `fuime-web` **and** `fuime-worker`. Anything marked
**REQUIRED** blocks launch.

### 3.1 Stripe — REQUIRED
| Variable | Notes |
|---|---|
| `STRIPE_MODE` | `test` today. Set to `live` **only** after §1.1 and §2.1. |
| `STRIPE__LIVE__SECRET_KEY` | Live secret key |
| `STRIPE__LIVE__PUBLISHABLE_KEY` | Live publishable key |
| `FUIME_STRIPE_WEBHOOK_SECRET` | Signing secret for `POST /fuime/webhooks/stripe` |

> The boot guard refuses to start if `STRIPE_MODE=live` without live keys, and refuses
> if a live key is present while mode is not live. Both are deliberate.

**Cost:** 2.9% + $0.30 per transaction. Connect adds fees — model this against your 4%
before promising anyone a margin.

### 3.2 Object storage — REQUIRED (data loss today)

Any **S3-compatible** store; it does not have to be AWS. Cloudflare R2 and
Backblaze B2 both work unchanged. **R2 is the recommended pick** — S3-compatible
API, no egress fees, and materially cheaper than S3 for records kept seven years.

| Variable | Notes |
|---|---|
| `ACTIVE_STORAGE_SERVICE` | Must be `amazon` — upstream's service name. It means "S3-compatible", not "AWS". |
| `S3__BUCKET` `S3__REGION` `S3__ACCESS_KEY_ID` `S3__SECRET_ACCESS_KEY` | Credentials scoped to one bucket |
| `S3__ENDPOINT` | Optional. Set for non-AWS: R2 is `https://<account-id>.r2.cloudflarestorage.com` with `S3__REGION=auto`. Leave unset for AWS. |

> **Why not a Render persistent disk?** It cannot work for Fuime — a hard
> constraint, not a preference. A Render disk is "accessible by only a single
> service instance" and unreachable "from any other service". Fuime runs
> **two**, and `fuime-worker` genuinely reads uploaded bytes:
> `Receipt::SuggestPairingsJob` OCRs receipts via RTesseract/MiniMagick,
> `ProcessColumnCheckDepositJob` calls `check_deposit.front.open`, and Active
> Storage's own `AnalyzeJob` downloads every new blob. A disk on the web service
> is invisible to all of it. Disks also forbid scaling past one instance and
> rule out zero-downtime deploys.

> **This is live data loss.** Active Storage defaults to `:local`, Render's filesystem
> is ephemeral, and `render.yaml` defines no disk. Every deploy **permanently destroys
> every uploaded receipt** — the exact records Fuime tells families to keep for taxes.
> Also configure versioning, lifecycle, and a 7-year retention policy for tax records.

**Cost:** a few dollars a month at launch scale; less on R2, which bills no egress.

### 3.3 Postgres + Redis — REQUIRED
Currently `basic-256mb` Postgres and a **free** Redis with `maxmemoryPolicy: noeviction`
backing both cache and Sidekiq — it will fill and start refusing writes under real
traffic. Upgrade Redis to a paid plan; upgrade Postgres and enable PITR backups.
**Cost:** ~$25–100/mo combined.

### 3.4 Email — REQUIRED
| Variable | Notes |
|---|---|
| `SMTP__PASSWORD` | Resend API key |
| `SMTP__ADDRESS` `SMTP__USERNAME` `SMTP__DOMAIN` `SMTP__PORT` | Already defaulted in `render.yaml` |
| `LIVE_URL_HOST` | Your real domain — **never** a hackclub.com host; the boot guard rejects it |

Verify the sending domain in Resend and get **DKIM, SPF, and DMARC** passing. Login
codes send inline, so broken email means **nobody can log in**. This has already broken
production once.

Also set: `FUIME_ENGINEER_EMAILS` (ops alerts — previously hardcoded to Hack Club
staff), and `FUIME_RECEIPT_PARSE_DOMAIN` only if you stand up inbound receipt parsing
on a Fuime domain. Leave it blank and the feature stays hidden rather than sending
users' receipts to Hack Club's parser.

**Cost:** Resend free tier → ~$20/mo.

### 3.5 Error tracking — REQUIRED
`APPSIGNAL_PUSH_API_KEY`, or swap in Sentry. Currently **unset**, which once made a
total homepage outage invisible. With real users you will not hear about failures until
someone emails you. Alert on 500-rate and Sidekiq failures. **Cost:** free tier → ~$30/mo.

### 3.6 Rails secrets — REQUIRED
`SECRET_KEY_BASE` · `RAILS_MASTER_KEY` · `LOCKBOX` ·
`ACTIVE_RECORD__ENCRYPTION__{PRIMARY_KEY,DETERMINISTIC_KEY,KEY_DERIVATION_SALT}` ·
`HASHID_SALT`

> Generate `LOCKBOX` yourself with `openssl rand -hex 32`. The example file previously
> shipped a real-looking 64-hex value — anyone who copied it inherited a
> publicly-known encryption key. Now blank; keep it that way.

### 3.7 Identity verification — REQUIRED (needs new integration)
Stripe Identity / Persona / Onfido. No env var exists yet; §4.2 is net-new work.
**Cost:** ~$1.50/verification.

### 3.8 Optional / later
`OPENAI_API_KEY` (receipt extraction, suggested tags) · `TWILIO__*` (SMS 2FA) ·
`HELPSCOUT__BEACON_ID` (support widget) · `MAPBOX` · `INTERCOM__*` ·
`IP_INFO` · `DISCORD__*`

### 3.9 Delete these — inherited from HCB, Fuime must never call them
`COLUMN__*` (Hack Club's banking rails) · `AWS_KMS__*` (TIN encryption, unused) ·
`TAXBANDITS__*` (1099 filing — a later phase, and a legal decision) ·
`DOPPLER_TOKEN` · `GSUITE__*` · `PLAID__*` · `DOCUSEAL__*`

Every unused credential is attack surface with no upside. Remove them from `render.yaml`.

---

## §4. Feature work

### 4.1 Payments, end to end — BLOCKING
**Today the product cannot take a single dollar.** `Fuime::PaymentLinkService` exists
but is **called from nowhere**, and the storefront's Pay button is `disabled` with the
label "(Payment links coming soon)".

- [ ] Rebuild against the §1.1 structure (Connect changes most of this)
- [ ] Guardian-facing onboarding into Stripe Connect, incl. KYC handoff
- [ ] UI for a teen to create and share a payment link
- [ ] Enable the storefront Pay button
- [ ] **Actually charge the 4% fee.** It is computed into Stripe metadata and then
      never read by anything — no line item, no `application_fee_amount`, nothing
      booked to the ledger. The business model is currently a comment.
- [ ] Payout scheduling and visibility for the guardian
- [ ] Test with real cards, real refunds, real disputes

Already done and worth keeping: webhook signature verification, idempotency keyed on
the payment intent, `fronted: false`, and refund/dispute reversal capped at the
outstanding amount.

### 4.2 Guardian identity verification — BLOCKING
Today, accepting an invite proves only **control of an email address plus a
self-asserted birthday**. The storefront badge has been softened to "Guardian on
account" to stop overclaiming, but the underlying control is thin.

- [ ] Verify identity before a guardianship goes `active`
- [ ] Store the verification result against the guardianship
- [ ] Restore the stronger "Parent-signed account ✓" badge only once this ships
- [ ] Decide with counsel whether to verify the parent–child relationship itself

### 4.3 Parent dashboard — BLOCKING for the value proposition
"Parents see everything" is currently a claim with no page behind it.
`User#wards` exists and is unused.

- [ ] One page: businesses they sign for, balances, recent transactions, tax status
- [ ] Guardian-visible notifications for money in/out
- [ ] Self-serve revocation UI (`Guardianship#revoke!` and its policy exist; no UI)

### 4.4 Fix what is currently broken on `main`
Two live bugs, both fixed in commits `895a120fa` and `0b5b0305c`, which were orphaned
when the branch history was rewritten. Restore with
`git cherry-pick 895a120fa 0b5b0305c`:

- [ ] **Reimbursements are wrongly disabled** — report PATCHes are silent no-ops
      (success responses that change nothing). The spec lists reimbursements as
      "hide nav", not disable.
- [ ] **`api/v4/*` back door** — `card_grants`, `ach_transfers`, `disbursements`,
      `stripe_cards`, `checks`, `check_deposits`, `wires`, `donations` are all
      reachable while their HTML twins are blocked.
- [ ] Fix `/privacy` redirecting to hackclub.com (§1.3)

### 4.5 Tax Tracker hardening
- [ ] CPA sign-off (§1.6)
- [ ] Replace memo-pattern income classification with explicit classification at ingestion
- [ ] Deduct Stripe fees withheld before settlement
- [ ] Decide on 1099-K reporting obligations
- [ ] Consider state tax

### 4.6 Data rights — BLOCKING for COPPA
- [ ] Parent can review everything collected about their minor
- [ ] Parent can request deletion; deletion actually works across all tables
- [ ] Data export (also feeds the "graduate to your own LLC" story)
- [ ] Documented retention: 7 years for tax records, defined for everything else

### 4.7 Security
- [ ] Full security review of the guardianship and money paths
- [ ] Rate limiting on auth and payment endpoints (rack_attack is configured but still
      references Hack Club office IPs)
- [ ] Set `config.hosts` — currently commented out, so there is no host authorization
- [ ] Rotate every credential inherited from the fork
- [ ] Penetration test before launch

### 4.8 Remaining brand and correctness sweep
- [ ] Residual Hack Club strings in PDF templates, `static_pages/branding`,
      `zach_signature.png` on contracts, and `hcb.hackclub.com` URLs in `Event#slug` /
      `HcbCode#hashid`
- [ ] **Delete the fiscal-sponsorship letter generator.** Fuime is not a fiscal sponsor
      and must never generate one. This is the one place where "disable, don't delete"
      should yield to "this is dangerous."
- [ ] Update `CLAUDE.md` — it says test-mode-only-forever while the app is in
      production; future sessions will optimise against a stale rule

### 4.9 Operational readiness
- [ ] Backups **and a rehearsed restore** — configured is not the same as working
- [ ] Uptime monitoring with alerting
- [ ] Status page
- [ ] Incident runbook: who is called, in what order, for a money bug
- [ ] Ability to freeze all payments within minutes
- [ ] Support inbox with a written response-time commitment

### 4.10 Test suite
- [ ] Get the full suite green and record the baseline in `known-failures.md`
- [ ] Fix CI so `yarn build` **and** `yarn build:css` run — without them every
      view-rendering spec fails on a missing bundle or a misleading `sassc` LoadError

Current state: 209 Fuime specs green (guardianship, tax math, webhooks, policies,
icons). Controllers/requests: 23 failures with assets built, versus 87 at the
pre-hardening baseline.

---

## §5. Sequence — rewritten 2026-08-04

The original sequence assumed the money code did not exist. It does. What changed is that
**engineering is no longer the critical path**, and the plan has to say so rather than
generate more code to feel productive.

### Step 0 — This week, and it is one engineer-day

**Run `stripe listen` against test mode and drive the whole flow by hand.** Onboard an
account, take a charge, request and approve a payout, trigger a refund. This is first
because it is cheap, because it validates roughly 3,000 lines of
documentation-derived assumptions, and because two of the three bugs in PR #28 were
invisible until code ran. Everything below is worth less until this is done.

Expect it to find things. Fix them, then re-baseline `known-failures.md`.

### Step 1 — In parallel, start the two things with the longest lead times

Both are letters and conversations, not commits, and both can sit for weeks with no
warning:

1. **The §1.1 counsel memo.** Still the gate on everything, but the question is now much
   narrower and cheaper to answer than it was: *"Fuime never receives, holds, or directs
   customer funds; charges settle directly to a guardian-owned Stripe account and Fuime
   takes a Connect application fee. Confirm this is not money transmission in our
   operating states, and confirm the guardian-as-principal agreement structure."* That is
   a reviewable memo rather than an open-ended research project.
2. **Stripe, in writing.** Disclose the teen-user model (§2.1) *and* get answers to the
   three questions in `LEGAL_RESEARCH.md`. Do this before any further card work — a "no"
   on Issuing underwriting deletes a feature, and it is better to learn that from an email
   than from a rejected account belonging to a real family.

### Step 2 — Engineering that does not depend on either answer

Ordered by what blocks a real user soonest:

- **Error tracking with alerting** (§3.5). Still absent. Taking real money without it means
  a family's failed payout is discovered by the family.
- **The agreements as versioned, hash-recorded documents** (§1.3). The plumbing already
  exists and is proven: `Guardianship` records version + IP + UA, and the verification
  disclosure is content-hashed. The documents themselves do not exist. Counsel writes the
  words; wiring them in is small.
- **Data export and deletion** (§4.6). COPPA-blocking, and it does not depend on the
  money structure at all.
- **Parent dashboard** (§4.3). The guardian can currently see a venture and approve
  payouts, but there is no one place that answers "how is my kid's business doing?" This
  is the value proposition, and it is the cheapest remaining differentiator.
- **Stripe processing fee on the pooled simulator.** Only the Connect path posts it. Low
  priority, but the asymmetry will confuse someone.

### Step 3 — Only after Stripe answers on Issuing

Guardian identity **verification** (§4.2), meaning a vendor decision gate rather than
today's collect-and-forward, and then cards to a real cohort. Both are wasted work if
underwriting says consumer.

### Step 4 — Prove it

Full repo suite green (not just the Fuime subset). Restore drill. Security review. Then a
**closed beta of 5–10 families you can call by name**, with every transaction watched by
hand. Under-13 stays refused until the COPPA program in §1.4 actually exists — that is a
funded compliance workstream, not a validation change.

### Honest timeline

**6–10 weeks**, down from 10–14, and the reduction is entirely because Phase B is largely
built. The floor is set by the counsel memo and by Stripe's response, neither of which
goes faster because engineering is ready. If §1.1 comes back needing licences, the money
architecture already survives — Fuime is not in the flow of funds — which is precisely why
that structure was worth building before the answer arrived.

---

## §6. What "launch" means on day one

A 15-year-old signs up, enters a date of birth, and is parked until a guardian is
invited. The guardian receives an email, verifies their identity, reads a versioned
agreement, and accepts — with IP, timestamp, and agreement version recorded. The teen
can then create a business, share a payment link, and take a real card payment. The
money lands in an account the parent legally controls. Both see the ledger. A receipt
uploads and **survives the next deploy**. The tax page shows an honest estimate with a
CPA-approved disclaimer. The parent can revoke consent, export everything, or delete
it. If something breaks at 2am, someone gets paged.

**Updated 2026-08-04:** most of that paragraph is now true in test mode. A teen is parked
until a guardian is invited; the guardian accepts a versioned agreement with IP, timestamp
and version recorded; the teen can create a business, publish a storefront, take a card
payment, and see it on the ledger; the money settles to an account the parent legally owns;
both can see it; receipts survive a deploy; the tax page shows an honest estimate.

Four things in it are still false, and they are the remaining list:

1. The guardian **verifies their identity** — collection exists, verification does not.
2. The agreement they read is **written by counsel** — the plumbing is real, the words are not.
3. The parent can **export or delete everything** — not built.
4. **Someone gets paged** when it breaks at 2am — no error tracking, no on-call.

And one thing that paragraph never said, which now matters more than any of them: none of
it has run against Stripe. The §1.1 memo is still the gate on real money, but it is no
longer the gate on knowing whether the code works.

---

## Appendix: cost estimate at launch scale

| Item | Monthly |
|---|---|
| Render (web + worker + Postgres + Redis) | $50–150 |
| S3 + backups | $5–20 |
| Resend | $0–20 |
| Error tracking | $0–30 |
| Identity verification | ~$1.50 × new guardians |
| Stripe | 2.9% + $0.30 per transaction |
| **Recurring subtotal** | **~$100–250/mo** |

| One-time | Cost |
|---|---|
| Legal (formation, 4 agreements, money-transmission memo) | $5k–25k |
| CPA review | $1k–5k |
| Penetration test | $5k–15k |
| Insurance | $2k–10k/yr |

The engineering is cheap. The legal is not, and it is not optional — it is what makes
the difference between a product and a liability.
