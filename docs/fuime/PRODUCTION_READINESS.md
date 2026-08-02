# Fuime — Production Readiness Sweep

**Date:** 2026-08-01
**Scope:** What must be true before Fuime serves real teenagers and real parents with real money.
**Verdict:** **Not launchable** — but the engineering blockers are now closed. What remains is
legal, and no amount of code closes it.

This is a hackathon demo that has been deployed to a public URL. That is fine. The gap between
that and "real teenagers, real people" is the subject of this document.

---

## STATUS — 2026-08-01, after the hardening pass

Branch `fuime/production-hardening`. See `UPSTREAM_DIVERGENCE.md` for the change-by-change log.

**Closed in code:**

| § | Item | What changed |
|---|------|--------------|
| 1.1 | Guardianship unenforced | Now a deny-by-default request filter + EventPolicy gate; unknown age fails closed; DOB required to finish onboarding |
| 1.2 | Guardian could be anyone | Activation refuses unless the guardian is a *confirmed* adult; consent record (version/IP/UA); 7-day token expiry; auditable revocation |
| 1.3 | Production Stripe mode didn't exist | `STRIPE_MODE`, defaulting to test everywhere; boot check refuses half-configured live keys |
| 1.4 | Webhook broken + wrong | Signature now required; double-post fixed; `fronted: false`; refunds and disputes reverse correctly |
| 1.6 | Wrong tax numbers | Threshold on net earnings (×0.9235); income classified; copy reframed as estimates |
| 1.7 | Receipts destroyed each deploy | S3 configured on web + worker; boot check refuses to start on `:local` |
| 2.2 | Storefront leaked minors' data | Balance removed; owner name adults-only; tax figures never public; badge claims only what's evidenced |
| 2.3 | Money-out routes reachable | Blocked at request level, not nav-hidden |
| 2.4 | Mail leaked to Hack Club | Comment mailer, receipt address, and admin alerts moved off hackclub.com |
| 2.6 | Secrets hygiene | Live-looking `LOCKBOX` key and hackclub.com host removed from the example |
| 2.7 | Zero tests | 68 specs covering every rule above |

**Still open, and each independently gates launch:**

- **§1.2 identity verification** — a guardian is still only a controlled email plus a
  self-asserted birthday. Needs Stripe Identity/Persona.
- **§1.5 money transmission** — unresolved. Determines how much of the money code survives.
- **§1.6 CPA review** — the arithmetic is now correct and tested; whether the *guidance* is
  right is not a question code can answer.
- **§2.1 the product doesn't take payments yet** — `PaymentLinkService` is still called from
  nowhere and the storefront Pay button is disabled. Deliberate: wiring it up before §1.5 is
  settled would be building on a foundation that may move.
- **§2.5 error tracking** — still no Sentry/Appsignal key.
- ToS, COPPA privacy policy, guardian agreement — none exist.

**Operator actions required before this branch helps anyone** (the app will now refuse to boot
without the first two):

1. Set `S3__BUCKET`, `S3__REGION`, `S3__ACCESS_KEY_ID`, `S3__SECRET_ACCESS_KEY` in Render.
2. Re-sync the Render Blueprint so `ACTIVE_STORAGE_SERVICE=amazon` and `STRIPE_MODE=test` apply.
3. Set `FUIME_STRIPE_WEBHOOK_SECRET` if payments are to be tested.
4. Run `rails db:migrate` (three new migrations).
5. Note: existing receipts on the current deploy are **already gone**, and any uploaded before
   step 1 completes will be too.

---

## 0. The one thing to internalize

Fuime's users are **minors**, and its product is **money and tax advice**. That combination puts
this app under COPPA, state money-transmitter law, IRS filing rules, and — because a parent
"signs" — actual contract law. Almost every finding below is a *legal* finding wearing a
software costume. Ship order matters: the blockers in §1 are not "tech debt," they are the
difference between a product and a liability.

---

## 1. BLOCKERS — do not accept a single real user until these are closed

### 1.1 The guardian requirement is not enforced anywhere

This is the product thesis, and it is decorative.

`User#needs_guardian?` exists and is correct. It is referenced in exactly **one** place —
[users_controller.rb:431](app/controllers/users_controller.rb#L431) — as a *redirect after
profile creation*. A redirect is a suggestion, not a control.

What a 15-year-old can do today without any guardian:

- Ignore the redirect, navigate anywhere. Nothing re-checks.
- Create a business (`Event`). No policy consults guardianship.
- Own, manage, and transact on it.
- Never invite a parent at all.

Verified: `grep guardian app/policies/` matches **only** `guardianship_policy.rb`.
`event_policy.rb`, `events_controller.rb`, and `event.rb` contain zero guardian logic.

Worse, the age gate is trivially bypassed. `needs_guardian?` is `is_minor? && !has_active_guardian?`,
and `is_minor?` is `age&.<(18)` — **nil when no birthday is set**. Birthday is optional. A user who
simply never enters a DOB is `is_minor? == nil`, so `needs_guardian?` is falsy and the redirect
never fires. The COPPA under-13 validation
([user.rb:731](app/models/user.rb#L731)) is guarded by `if birthday.present?` — so **skipping the
birthday field skips the under-13 block entirely.**

`GuardianshipPolicy#new?` even documents this nil case and deliberately allows it. That's right
for *inviting* a guardian; it's catastrophic as the only gate on *being* a minor.

**Required:**
- Make `birthday` mandatory at signup, before any other onboarding step. No DOB → no account.
- Treat unknown age as minor-until-proven-adult everywhere except the invite flow.
- Enforce in `EventPolicy` / `Event` creation: a minor with no `active` guardianship cannot
  create, own, or move money in a business. Enforce in the **policy layer**, not a controller redirect.
- Add a `before_action` at `ApplicationController` level that hard-parks un-guardianed minors
  on the invite page (allowlist: invite, logout, settings).
- Specs for every one of these rules. There are currently **zero** — `find spec -ipath "*guardian*"`
  returns nothing.

### 1.2 Nothing verifies the "guardian" is an adult, a parent, or a real person

The invite flow is: teen types an email → **Fuime creates a user account for that address**
([guardianships_controller.rb:41](app/controllers/guardianships_controller.rb#L41)) → whoever
opens the link clicks accept.

There is no identity verification, no age verification, no proof of parental relationship.
`Guardianship#guardian_must_be_adult` calls `guardian.is_minor?` — which, for a freshly created
user with no birthday, is **nil**. Falsy. The check passes.

So: a 14-year-old can enter their 15-year-old friend's email — or a second address of their own —
and self-authorize a "parent-signed account." The product then displays
**"Parent-signed account ✓"** on a public storefront. That badge is, in the general case, a false
statement to the public, and the "signature" backing it has no legal weight.

**Required (this is a legal design task, not a coding task):**
- Real identity verification for guardians (Stripe Identity / Persona) before a guardianship
  goes `active`.
- A written guardian agreement with recorded consent — IP, timestamp, user agent, agreement
  version — since this is what makes the adult the legal signer. Store immutably.
- Block same-person self-invites beyond the current `guardian.id == current_user.id` check
  (compare verified identity, not user id).
- Do not render "Parent-signed ✓" until identity-verified consent exists.
- Verifiable Parental Consent under COPPA for any user under 13 — or, far simpler and my
  recommendation, **enforce 13+ hard** and never collect under-13 data at all.

### 1.3 Production Stripe mode does not exist → money-in is dead on arrival

`StripeService.mode` returns **`:live`** when `Rails.env.production?`
([stripe_service.rb:4-10](app/services/stripe_service.rb#L4-L10)), so every key lookup resolves
`STRIPE__LIVE__*`.

`render.yaml` provisions only `STRIPE__TEST__PUBLISHABLE_KEY` / `STRIPE__TEST__SECRET_KEY`.
**No `STRIPE__LIVE__*` keys are defined at all.**

Consequences, right now, on the deployed service:
- `Fuime::PaymentLinkService` → `StripeService.secret_key` → nil/raise. Payment links cannot be created.
- Any Stripe-touching HCB code path in production is reading credentials that were never set.

This also collides head-on with CLAUDE.md's hard rule ("test mode only, forever, in this repo").
The repo is deployed to production, and production means live mode. **The rule and the deployment
are in direct contradiction and one of them has to change.**

**Required — decide explicitly:**
- **(a) Real users, real money:** you need live keys, which means §1.5's regulatory work first.
  Then set `STRIPE__LIVE__*`.
- **(b) Real users, no money yet:** override `StripeService.mode` to `:test` via env
  (`STRIPE_MODE`), and make it loud in the UI that no real money moves. This is the honest
  interim posture and the one I'd pick.

Either way, add a boot-time assertion that the mode's keys are actually present.

### 1.4 The webhook cannot work in production, and the ledger entry is wrong when it does

Two separate defects in the money-in path.

**(a) Webhook secret is never set.** `Fuime::WebhooksController#fuime_webhook_secret` reads
`FUIME_STRIPE_WEBHOOK_SECRET`, which is **absent from `render.yaml`**. With a nil secret,
`Stripe::Webhook.construct_event` raises `SignatureVerificationError`; the rescue only bypasses
in `Rails.env.development?`, so **production returns 400 to every Stripe webhook, forever.**
Payments would be taken and never appear in a ledger. Stripe will retry, then give up.

**(b) Payments are booked as `fronted: true`.**
[payment_webhook_handler.rb:83](app/services/fuime/payment_webhook_handler.rb#L83) hardcodes
`fronted: true` on the `CanonicalPendingTransaction`.

In HCB, "fronted" means *Hack Club advances the org spendable credit before the money actually
settles* — it's a balance-sheet risk decision backed by a real 501(c)(3)'s reserves. Fuime has no
reserves. Marking every incoming teen payment as fronted tells the ledger the business can spend
money Fuime does not have and has not received. Stripe payouts are T+2 at best; a chargeback or a
failed payout leaves a negative real position against a positive displayed balance.

**Required:**
- Set `FUIME_STRIPE_WEBHOOK_SECRET` in `render.yaml` for web (and worker), and remove the
  development bypass or gate it behind an explicit env flag.
- Change `fronted:` to `false` unless you have made a deliberate, funded decision to front — and
  if so, document who absorbs the loss.
- Handle the failure half of the lifecycle, which is entirely missing: `charge.refunded`,
  `charge.dispute.created`, `payment_intent.payment_failed`, `payout.failed`. Today a refunded
  payment stays on the teen's ledger as income — and flows into their tax number.
- The idempotency design is good (keyed on Stripe object id) — but note `checkout.session.completed`
  and `payment_intent.succeeded` fire for the *same* payment with *different* object ids, so a
  single Checkout payment currently posts **two ledger lines**. Key on the payment intent id, or
  handle only one event type.

### 1.5 There is no legal structure for holding other people's money

CLAUDE.md is candid that this is "a Phase 2 lawyers-and-Stripe conversation." Serving real users
*is* Phase 2. Naming it plainly:

Fuime proposes to receive customer payments into a pooled Fuime-controlled Stripe account and
allocate them to teen businesses via an internal ledger. That is **money transmission**. HCB can
do its version because Hack Club is a 501(c)(3) that legally *owns* the funds it holds for its
fiscally-sponsored projects. Fuime is not a fiscal sponsor and the teens are not its projects —
so Fuime is holding funds *belonging to someone else*, which is the textbook trigger for:

- State money transmitter licenses (~49 states, 12–24 months, seven figures), **or**
- Operating as an agent of a licensed partner / payfac (Stripe Connect with the *teen's parent*
  as the connected account holder), **or**
- Merchant-of-record: Fuime genuinely sells the goods and remits to teens. Different tax and
  liability profile entirely.

**The Stripe Connect route is almost certainly the answer**, and notably it is *less* code than
what's here: the parent's verified identity becomes the connected account, Stripe handles KYC and
payouts, funds never sit in a Fuime-controlled pool, and the "parent is the legal signer" thesis
becomes literally true instead of decorative. It also deletes §1.3 and most of §1.4.

**Required before any real money:** counsel review, and a written decision on which of the three
structures you're in. Also required and currently absent: Terms of Service, Privacy Policy
(COPPA-compliant), and the guardian agreement from §1.2.

### 1.6 Tax Tracker gives incorrect tax guidance

The demo star is also the biggest liability per line of code. Every issue below produces a
*wrong number* shown to a teenager as tax guidance.

From [tax_tracker_service.rb](app/services/fuime/tax_tracker_service.rb):

1. **`income_cents` and `expenses_cents` memoize after the subtraction is computed.**
   `net_income_cents` calls `income_cents - expenses_cents`; both use `@x ||=` but the
   `year_start` local is recomputed per call — harmless today, but the memoization means a
   long-lived service instance spanning midnight on Jan 1 reports mixed-year data. Minor, but
   it's a money number.
2. **The $400 threshold is applied to the wrong base.** IRS: self-employment tax is owed on **net
   earnings ≥ $400**, where net earnings = net profit × 0.9235. The code compares raw net income
   to $400. Businesses between $400 and ~$433 net are told they owe when they may not.
3. **Every positive ledger line counts as income.** Transfers in, refunds, corrections,
   the teen depositing their own money — all inflate taxable income. Real accounting needs
   income *classification*, not a sign check.
4. **Platform fees and Stripe fees are never deducted** (they aren't recorded at all — see §2.1),
   so expenses are understated and the tax number is overstated.
5. **Refunds/chargebacks never reverse** (§1.4), permanently inflating income.
6. **No state tax, no 1099-K, no quarterly estimated payments** — for many teens crossing $400,
   quarterlies are the actually-urgent obligation and Fuime is silent on them.

The CSV disclaimer ("Consult a tax professional") is real but thin cover when the headline UI
says *"You'll owe self-employment tax"* as a definitive statement.

**Required:**
- Correct the threshold math (`net × 0.9235 ≥ 400`).
- Classify ledger lines; only count actual business revenue.
- Deduct fees; reverse refunds.
- Rewrite all copy from determinations to estimates ("Based on your Fuime ledger, you may owe…").
- Have a CPA review the packet and the copy before it reaches a real family.
- Add the quarterly-estimates warning.

### 1.7 Uploaded receipts are silently destroyed on every deploy

`config.active_storage.service = ENV.fetch("ACTIVE_STORAGE_SERVICE", "local")`
([production.rb:73](config/environments/production.rb#L73)). `render.yaml` sets neither
`ACTIVE_STORAGE_SERVICE` nor any S3 credentials, and defines **no persistent disk**.

So production Active Storage writes to the container's ephemeral filesystem. Every deploy,
restart, or Render instance recycle **permanently deletes every uploaded receipt** — the exact
records a family needs for the tax filing Fuime is telling them to make. Silent, unrecoverable.

**Required:** configure S3 (bucket, credentials, `ACTIVE_STORAGE_SERVICE=amazon`) before any real
upload. `config/storage.yml` already has the `amazon` block; it just needs credentials.
Then: backups, lifecycle policy, and a documented retention period (tax records: 7 years).

---

## 2. HIGH — needed for a credible, honest launch

### 2.1 The 4% platform fee is computed and then thrown away

`PaymentLinkService` calculates `fee_cents` and writes it to Stripe metadata. `grep` for
`fuime_fee_cents` outside that file: **no matches**. The webhook handler ignores it. Nothing
deducts it, records it, or shows it. The business model exists only in a metadata field.

Also: the fee is added as metadata but **not** as a line item or `application_fee_amount`, so
the customer is charged the base amount and Fuime collects nothing. And `PaymentLinkService`
itself is **never called from anywhere** in the app — no controller, no view, no job. The
storefront's Pay button is `disabled` with the label *"(Payment links coming soon)"*.

So the money-in feature is, end to end, not wired up. That's honest for a demo; it means "real
users can get paid" is net-new work, not a fix.

### 2.2 Storefront leaks a minor's financial data publicly, with no minor-specific consideration

`/b/:slug` is unauthenticated and renders, for a child's business:
account balance, business age, **owner's first name**, public ledger, and a guardian badge.

`@event.is_public` gates it, and that's inherited HCB behavior — but HCB's users are nonprofit
*organizations* publishing accountability data by choice. Fuime's are **children publishing
financial data**. A first name + business + city-adjacent info + live balance is a targeting
profile. This needs a deliberate decision, ideally with the guardian in it.

**Required:** default storefronts to private; require explicit *guardian* opt-in to publish;
never show the owner's name or precise balance by default; add `noindex` unless opted in.

### 2.3 Abandoned/half-disabled HCB modules are still routed and reachable

`grep -c` finds ~60 route lines for ACH transfers, checks, disbursements, reimbursements,
donations. Only **7** `FUIME-DISABLED` tags exist in the entire app. UPSTREAM_DIVERGENCE confirms
disabling was done by *not rendering two homepage partials* — nav-level hiding, with routes live.

These are **money-out** paths inherited from a platform with real banking rails, now sitting
behind a login used by 14-year-olds, pointed at Column sandbox credentials that may or may not be
set. Anything reachable by URL is reachable by a curious teenager.

**Required:** route-level removal (or a global `before_action` deny) for every module Fuime
doesn't offer — not nav hiding. Milestone 5 was specified this way in CLAUDE.md and hasn't been
done.

### 2.4 Outbound email still comes from and replies to Hack Club

`comment_mailer.rb` sets `reply_to: comments+...@hcb.hackclub.com` and
`from: hcb@hackclub.com`. Same in `wire_mailer`, `increase_check_mailer`, `ach_transfer_mailer`.
`admin_mailer.rb:132` emails **gary@, luke@, ian@ hackclub.com** on admin events.
`hcb_code.rb:110` generates receipt-upload addresses at `@hcb.hackclub.com`.

Real Fuime users emailing real Hack Club staff, and receipt emails routing to Hack Club's parser,
is both a privacy incident and a bad-neighbor problem for an upstream project you depend on.
It also means receipt-by-email **does not work** for Fuime.

**Required:** sweep all mailers to Fuime addresses; stand up Fuime's own receipt-parse domain or
disable receipt-by-email; remove the hardcoded Hack Club admin recipients.

### 2.5 No error tracking in production

Appsignal is configured but `APPSIGNAL_PUSH_API_KEY` is unset, which previously made a total
homepage outage invisible (documented in UPSTREAM_DIVERGENCE). The mitigation was to route
lograge to stdout — better than nothing, but Render log search is not error tracking. With real
users you will not hear about failures until someone emails you.

**Required:** Sentry or Appsignal with a real key, alerting on 500-rate and on Sidekiq failures.

### 2.6 Secrets hygiene

- `.env.development.example` ships a **real-looking 64-hex `LOCKBOX` key**. Anyone copying the
  example into a working env inherits a publicly-known encryption key. Replace with an obvious
  placeholder.
- `LIVE_URL_HOST="hcb.hackclub.com"` in the example points Fuime dev at Hack Club production.
- `render.yaml` still provisions `COLUMN__SANDBOX__*`, `TWILIO__*`, `AWS_KMS__*`, `TAXBANDITS__*`,
  `OPENAI_API_KEY`, `DOPPLER_TOKEN` for services Fuime doesn't use — a credential surface with no
  corresponding benefit.
- Production runs on `fuime-web.onrender.com` while SMTP is configured for `fuime.com` and
  `config.hosts` is commented out (no host authorization).

### 2.7 Zero test coverage on everything Fuime added

`find spec -ipath "*fuime*" -o -ipath "*guardian*"` → **nothing**. Guardianship, payments, taxes,
storefront: no specs. CLAUDE.md Prime Directive #1 says "the test suite is the contract," and
Milestone 4 explicitly required "new model specs for every rule above."

For a system making tax claims and enforcing legal guardianship, this is the gap that will let a
future refactor silently break a legal control.

**Required:** specs for every §1.1 rule, webhook idempotency + refund handling, and tax math
against hand-computed fixtures.

---

## 3. MEDIUM — real but not launch-blocking

- **Under-13 handling.** Currently a validation error at signup *if* a DOB is given. Decide and
  document the COPPA posture; my recommendation is a hard 13+ floor, no under-13 data collected, ever.
- **Guardian invite tokens never expire.** `SecureRandom.urlsafe_base64(32)` is strong, but
  `invite_sent_at` is recorded and never checked. Add a TTL (7 days) and re-send.
- **No guardian revocation UI.** `revoke!` exists on the model; nothing calls it. A parent must be
  able to withdraw consent — that's a legal requirement, not a feature.
- **No parent dashboard.** S2 in the spec, unbuilt. "Parents see everything" is currently a claim
  with no page behind it. `has_many :wards` exists and is unused.
- **Data deletion / export.** Minors' data under COPPA and state privacy laws requires parental
  deletion rights. No mechanism exists.
- **`likely_event_id` returns nil for Fuime payments** — handled deliberately, but it means Fuime
  rows are invisible to any upstream pipeline code that relies on it. Worth an audit before
  trusting reconciliation.
- **Statement descriptor** is built manually in `PaymentLinkService` while HCB has
  `StripeService::StatementDescriptor` (whose `PREFIX` is still `"HCB* "`). Two implementations,
  one of them still branded Hack Club.
- **Residual Hack Club branding** in PDF templates (`verification_letter`,
  `fiscal_sponsorship_letter`), `static_pages/branding`, `zach_signature.png` on contracts, and
  `hcb.hackclub.com` URLs in `Event#slug` / `HcbCode#hashid` helpers. UPSTREAM_DIVERGENCE
  acknowledges these as unfinished Milestone 3 work. The **fiscal sponsorship letter is
  actively dangerous** — Fuime is not a fiscal sponsor and must never generate one.
- **`.md` docs conflict.** CLAUDE.md says test-mode-only-forever; the app is in production. Update
  CLAUDE.md to describe the real posture so future sessions don't optimize against a stale rule.
- **Redis on Render `free` plan** with `maxmemoryPolicy: noeviction` backs both cache and Sidekiq;
  it will fill and start refusing writes under real traffic.
- **Postgres `basic-256mb`** with no documented backup/PITR policy, holding financial records.

---

## 4. Recommended sequence

**Phase A — stop the bleeding (before *any* real user)**
1. S3 for Active Storage (§1.7) — silent data loss is the worst failure mode here.
2. Enforce guardianship in the policy layer + mandatory DOB (§1.1).
3. Decide Stripe mode; assert keys at boot (§1.3).
4. Error tracking with alerts (§2.5).
5. Rotate the example `LOCKBOX` key; strip unused credentials (§2.6).
6. Route-level disable of all money-out modules (§2.3).
7. Fix the mailers so no user email reaches Hack Club (§2.4).

**Phase B — legal foundation (parallel, and it gates everything else)**
8. Counsel: money transmission structure. Strongly evaluate **Stripe Connect with the
   guardian as the connected account** — it makes the thesis literally true and deletes most of §1.3–1.5.
9. ToS, COPPA privacy policy, guardian agreement.
10. Guardian identity verification (§1.2).
11. CPA review of the Tax Tracker (§1.6).

**Phase C — make the product real**
12. Fix tax math; reframe copy as estimates.
13. Wire payments end to end: webhook secret, `fronted: false`, refunds/disputes, dedup, fee capture.
14. Storefront privacy defaults with guardian opt-in.
15. Specs for all of the above.
16. Parent dashboard; guardian revocation; data export/deletion.

**Phase D — operate**
17. Backups + restore drill. Paid Redis. Host authorization. Load check.

---

## 5. Honest summary

The HCB fork was the right call — the ledger, receipts, comments, and admin console are mature
infrastructure you could not have built in a weekend, and they are largely untouched, which is
exactly per CLAUDE.md Rule 3.

What was built *on top* is demo-grade: the guardianship system models the right idea but enforces
nothing, the payment path isn't connected to a UI and would fail in production if it were, and the
Tax Tracker computes a number that is wrong in at least four ways. None of that is a criticism of a
48-hour build — it's precisely what a 48-hour build should look like.

The distance to "real teenagers, real people" is not mostly engineering. It's **§1.5 and §1.2** —
the legal structure for holding money and the verified adult signer. Those two decisions determine
how much of the current code survives. I'd resolve them with counsel *before* investing in Phase C,
because the Stripe Connect path would rewrite most of the money code anyway — favorably, and with
less of it.
