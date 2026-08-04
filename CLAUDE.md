# FUIME — Claude Code Operating Guide (Phase 0: Safe Pivot)

> Drop this file in the repo root as `CLAUDE.md` (or `FUIME_PLAN.md` and tell Claude Code to read it first).
> Repo: github.com/MntRushmore/Fuime — fork of hackclub/hcb (Rails monolith, ~14k commits).
> Goal of this phase: get the fork running, understood, de-risked, and re-pointed at
> Fuime's model (one pooled Fuime Stripe account, test mode; ledger allocates funds per
> business — HCB's own architecture) — **without breaking anything**.

---

## What Fuime is (context for every session)

Fuime is a fork of HCB, repurposed from *fiscal sponsorship for teen nonprofits* into
*a financial platform for teen-run businesses (13–17)*. Key differences from upstream HCB:

- HCB: one legal entity (Hack Club 501c3) owns ALL money; bank feeds from Column; cards via Stripe Issuing.
  Verified against upstream: HCB has **zero Stripe Connect usage**. Cards are platform-level
  Issuing funded by `topup_stripe_job.rb` into one shared Issuing balance, and HCB itself
  approves each swipe against its own subledger. That works only because a 501(c)(3) legally
  owns the funds as restricted charitable funds. A for-profit cannot copy it.
- Fuime: **a Stripe connected account per venture, owned by the guardian** (shipped
  2026-08-03). Stripe holds and settles the funds; Fuime takes its cut as a Connect
  application fee on direct charges and is never in the flow of funds. Still
  TEST MODE by default everywhere including production (`StripeService.mode`).
  ~~one pooled platform Stripe account~~ — the pooled model is retired to a
  test-mode simulator only; in production it is money transmission (see L1).
- New concept HCB doesn't have: **guardianship** — every teen user requires a linked
  parent/guardian who is the legal signer. Parent visibility is a feature, not an afterthought.
- HCB's "Event" (organization) becomes Fuime's "Venture" — but see Rule 6 before renaming anything.

---

## PRIME DIRECTIVES (apply to every session, no exceptions)

1. **The test suite is the contract.** Run `bundle exec rspec` before starting and after
   finishing any milestone. If you didn't break it, don't ship a red suite. If it was
   already red, record which specs fail in `docs/fuime/known-failures.md` before changing code.

2. **Disable, don't delete.** HCB modules we don't need (donations, grants, checks, ACH,
   G Suite) get turned off via feature flags, nav removal, or route removal — NOT deleted —
   until Milestone 5. Deletion in a codebase you don't fully understand yet causes
   mystery breakage three weeks later.

3. **Never touch the ledger engine in Phase 0.** `CanonicalTransaction`,
   `CanonicalPendingTransaction`, `HcbCode`, and the transaction ingestion/mapping pipeline
   are the crown jewels. We will FEED them new sources (Stripe Checkout webhooks), never
   modify their internals.

4. **No production or third-party credentials, ever.** Stripe test mode only. All Column,
   Increase, Twilio, and hackclub.com-pointing integrations must be stubbed or disabled
   via environment config (Milestone 2) so nothing in this repo can ever call Hack Club's
   production services, even by accident.

5. **Small, reversible steps.** One milestone = one branch = one PR against main.
   Never rewrite git history, never delete or edit existing migrations — new migrations only.

6. **Do NOT global find-and-replace "hcb" or "event".** `HcbCode` is a load-bearing model
   name woven through the schema; `Event` is the core organization model with hundreds of
   references. Renaming internal class names is a Phase 1+ refactor. In Phase 0 we rename
   only *user-facing strings* (views, mailers, page titles). Internal code keeps upstream
   names so we can still diff and pull fixes from hackclub/hcb.

7. **AGPL + attribution.** The LICENSE file stays AGPL-3.0. The README keeps a visible
   "Fuime is a fork of HCB by Hack Club" attribution with a link. Hack Club's *trademarks*
   (name, logo, laser gif) must be removed from the UI — the license covers code, not brand.

8. **Log every divergence from upstream** in `docs/fuime/UPSTREAM_DIVERGENCE.md`
   (one line per change: what, why, files touched). This preserves our ability to merge
   upstream ledger/security fixes later.

---

## LEGAL CONSTRAINTS (from docs/fuime/LEGAL_RESEARCH.md, Aug 2026 — read it before product/copy/money work)

L1. **The pooled-account model can never go live.** In production it is unlicensed money
    transmission (18 U.S.C. § 1960 — criminal) and violates Stripe's ToS (aggregation outside
    Connect). It stays a test-mode simulator. The production architecture is **Stripe Connect
    Standard: one guardian-owned connected account per venture**, direct charges + 4%
    application fee, payouts to the family's own bank. "Column + Stripe like Hack Club" does
    not transfer to a for-profit: HCB works only because donations are the 501(c)(3)'s own funds.

L2. **The parent/guardian is the legal party everywhere.** Guardian = account owner /
    Stripe Representative / principal obligor on ToS, fees, chargebacks, arbitration,
    indemnity. Teen co-clicks; ratification-at-18 clause. Under-13s click nothing contractual.
    A teen-only clickwrap is voidable (infancy doctrine — Doe v. Epic Games (N.D. Cal. 2020)).

L3. **SSN-free onboarding is only possible while no real money moves.** Live payments require
    guardian KYC: Stripe demands the Representative's SSN last-4 (full SSN at $500K); any bank
    account requires a TIN (31 CFR 1020.220). Plan the parent flow around that, don't fight it.

L4. **Never store ID images.** Parent verification = COPPA-grade method (ID + database check,
    ID + selfie match, or card micro-transaction), then **delete the image**; keep only the
    consent record (method, vendor ref, timestamp, doc-version hash, IP/UA). BIPA applies to
    face-matching.

L5. **Forbidden vocabulary in all user-facing copy while no partner bank exists:** bank,
    banking, neobank, checking, savings, deposits, insured, FDIC, "your money is safe/
    guaranteed", bank-ish domains. (Cal. Fin. Code § 562; 205 ILCS 5/46; FDIC Part 328
    Subpart B; DFPI v. Chime.) Say: "financial platform / financial tools for young founders";
    accounts are "opened and owned by a parent or guardian." Standing footer disclosure:
    "Fuime is a financial technology company, not a bank…" (full text in LEGAL_RESEARCH.md §7).

L6. **Under-13 users are a deliberate, gated expansion, not a copy change.** It requires the
    full amended-COPPA program (VPC, dual notices, retention/security programs, $53,088/
    violation exposure) AND a parent-owned merchant account (Stripe's floor is 13 even with a
    guardian). Until that program exists, the under-13 refusal validation stays.

L7. **No targeted advertising, sale, or profiling of minors' data — ever** (CT flat ban; TX
    SCOPE; NY CDPA "strictly necessary"). Paid acquisition targets parents. Transactional-only
    notifications to minors, none 12–6 a.m. No algorithmic/social feed without legal review.

L8. **fuime.com must describe the product that exists.** The site currently claims a Stripe
    Connect no-custody architecture, a Stripe ID check, and 7% + $15/mo pricing — none
    implemented (app: pooled account, no KYC, 4%, no monthly fee). Fixing this divergence is
    P0; never let site copy lead the code again.

---

## MILESTONE 0 — It runs on my machine (do nothing else until this is done)

Objective: HCB boots locally with seed data; you can log in and click through.

- Follow `dev-docs/development.md` (Docker path recommended; `docker_dev_setup.sh` exists).
- Get seed data loaded, log in as a seeded user, and manually visit: an organization
  home/ledger page, a transaction detail, the receipts flow, and the admin console.
- Deliverable: `docs/fuime/SETUP_NOTES.md` — exact commands that worked, gotchas hit,
  and which seeded accounts to use. (Future sessions start here instead of re-deriving.)
- Verification: `bundle exec rspec` — record the baseline result (pass/fail counts).

**Claude Code prompt:**
"Read dev-docs/development.md and get this app running locally with Docker and seed data.
Do not modify any application code. Document every command and problem in
docs/fuime/SETUP_NOTES.md. Then run the test suite and record baseline results."

## MILESTONE 1 — Map before you cut

Objective: a codebase map so every future change is made with eyes open.

Produce `docs/fuime/CODEBASE_MAP.md` covering:
- **Core domain models**: Event, User, OrganizerPosition, CanonicalTransaction,
  CanonicalPendingTransaction, HcbCode, Receipt — one paragraph each: role, key
  associations, where balances come from.
- **The money pipeline**: trace end-to-end how a raw bank/Stripe event becomes a ledger
  line on an org's page. Name every class in the chain.
- **External service inventory**: grep for Column, Increase, Stripe, Twilio, AWS/S3,
  Sentry, hackclub.com, Airtable, Slack. Table: service → purpose → where configured
  (env var / initializer) → what breaks in dev if absent.
- **Module inventory**: donations, invoices, ACH, checks, disbursements, reimbursements,
  grants, cards/Stripe Issuing, G Suite — for each: KEEP (Fuime needs it),
  DISABLE (not Phase 0), or LATER-DELETE.
- Verification: no code changes in this milestone. Docs only.

**Claude Code prompt:**
"Without changing any code, produce docs/fuime/CODEBASE_MAP.md per the spec in CLAUDE.md
Milestone 1. Be exhaustive on the external-service inventory — I need to know every place
this app can reach outside the machine."

## MILESTONE 2 — Safety rails (make it impossible to hurt anyone)

Objective: this fork can never touch Hack Club production or move real money.

- Create `.env.development` for Fuime from the example file: Stripe TEST keys only,
  dummy/absent creds for Column/Increase/Twilio; app URL localhost.
- Find every initializer/config that points at hackclub.com domains, HCB production
  endpoints, or Hack Club Slack/Airtable — gate them behind env vars that are unset,
  or point them at safe no-op defaults. Prefer config changes over code changes.
- Add a boot-time guard: if any production-flavored credential (live Stripe key,
  Column key) is present in a non-production environment, raise loudly.
- Outcome: app boots and functions in "island mode" with only test-mode Stripe reachable.
- Verification: boot the app with the new env; click through Milestone 0's pages; rspec.

## MILESTONE 3 — Surface rebrand (Fuime face, HCB bones)

Objective: user-visible identity becomes Fuime; internals untouched.

- Replace user-facing "HCB" / "Hack Club" strings in views, layouts, mailers, page
  titles, and the transparency pages. Swap logos/favicons for Fuime placeholders.
  Remove hcb_laser.gif and Hack Club badges from README.
- Rewrite README.md: Fuime description, quick start, AND the attribution block per Rule 7.
- Do NOT rename: Ruby classes, DB tables/columns, routes' internal names, the HcbCode
  model, or anything in db/. (Rule 6.)
- Deliverable addition: `docs/fuime/BRAND_STRINGS.md` listing every file touched.
- Verification: rspec (some view/mailer specs assert copy — update those specs with the
  new strings, and note each in UPSTREAM_DIVERGENCE.md); manual click-through.

## MILESTONE 4 — Guardianship (Fuime's first real feature)

Objective: the parent–teen structure, additive-only.

- New migration: `guardianships` table (guardian_user_id, minor_user_id, status,
  agreement_signed_at, unique on the pair). New nullable `date_of_birth` on users
  (or a parallel profile table if users is too hot — check the map first).
- Model rules: a user under 18 cannot hold an owner/manager position on an org unless
  they have an ACTIVE guardianship; under-13 signup is refused at validation.
- New org role concept: guardian/parent-signer with read access to the org's ledger.
  Implement as a new OrganizerPosition role if the map shows that's clean; otherwise a
  parallel association. Choose based on Milestone 1 findings and record the decision.
- Flows: parent invites teen; teen-first signup parks at "invite your guardian."
  Plain pages, no polish — correctness over beauty.
- Verification: new model specs for every rule above; full rspec; manual run of both
  onboarding orders.

## MILESTONE 5 — Prune the nonprofit limbs (now that you know where they are)

Objective: turn off what Fuime doesn't need, guided by the Milestone 1 inventory.

- Feature-flag or route-remove: donations, grants, check sending, G Suite provisioning,
  ACH origination (Phase 0 has no custody, so no outbound money movement at all).
- Keep fully alive: ledger engine, receipts, comments, invoices (our money-in),
  transparency mode, admin console, auth.
- Hide, don't delete, the Stripe Issuing/cards UI (a later phase revives it).
- Verification: rspec (skip/pending the specs for disabled modules — with a comment tag
  `# FUIME-DISABLED` so they're findable); click-through confirms no dead nav links.

## MILESTONE 6 — The funding-source spike (pooled Stripe account, test mode)

&gt; **Superseded in direction by L1 (Aug 2026):** the pooled-account pipeline built here stays
&gt; as the test-mode simulator; the *production* money-in is a new spike — Stripe Connect
&gt; Standard, guardian-owned connected accounts, direct charges + 4% application fee. See
&gt; docs/fuime/LEGAL_RESEARCH.md "Recommended path" P1.

Objective: prove the new money model feeds the old ledger. Spike = learning, not shipping.

- One Fuime platform Stripe account, test mode, configured via env.
- Per-business payment links: Stripe Checkout sessions tagged with the org id in
  metadata (plus a 4% platform-fee line item or ledger split).
- Webhook receiver (Stripe CLI `listen` in dev) that stores the raw event, maps
  metadata → org, and creates a
  CanonicalPendingTransaction → CanonicalTransaction pair through the EXISTING pipeline
  interfaces (find the narrowest legitimate entry point — do not modify pipeline internals).
- Success = a test-mode payment appears as a normal ledger line on the org's page,
  with receipt upload and comments working on it.
- Deliverable: `docs/fuime/CONNECT_SPIKE.md` — what worked, what fought back, and the
  recommended real architecture for Phase 0 money-in.
- Verification: rspec green; the ledger line renders; the webhook is idempotent
  (replaying the same Stripe event does not double-post).

---

## Session ritual (every Claude Code session)

1. Read this file + `docs/fuime/SETUP_NOTES.md` + `UPSTREAM_DIVERGENCE.md`.
2. State which milestone you're on and what "done" means before writing code.
3. Work on a branch named `fuime/m<N>-<slug>`.
4. End by: running rspec, updating UPSTREAM_DIVERGENCE.md, and writing a 5-line
   handoff note at the top of SETUP_NOTES.md for the next session.

## Explicitly out of scope for Phase 0

Real money movement · live Stripe keys · card issuing · custody/FBO/merchant-of-record ·
KYC · production deployment · renaming Event→Venture or HcbCode internals ·
mobile · marketing site. If a task seems to require any of these, stop and flag it.
