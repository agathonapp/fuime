# fuime — design

Date: 2026-08-01
Repo: `hangryclaude/fuime` (fork of `hackclub/hcb`, AGPL-3.0)

## Goal

A teen running a service business sends a real invoice, gets paid into an account they operate day to day, sees their books, and knows what they owe at tax time — without being 18 and without routing money through a parent's PayPal.

## Approach

Fork HCB for its ledger, transaction model, and Stripe plumbing. Remove the fiscal-sponsorship chassis, which is a 501(c)(3) instrument and does not transfer to for-profit businesses. Replace it with:

**Stripe Connect Standard, guardian as account owner, `application_fee_amount` as the revenue mechanism.**

Stripe Connect Standard permits account holders aged 13+ when a legal guardian is the account owner. The guardian signs once during onboarding. The teen operates the account. Every charge carries a 7% `application_fee_amount` that settles to the platform account. We never take custody of funds, so no money transmitter license, no bank partner, and no Merchant of Record liability.

### Rejected

| Option | Why not |
|---|---|
| Merchant of Record | We become the legal seller: chargebacks, refunds, fraud, and product liability across thousands of unvetted minor merchants. Heaviest possible v1. |
| Custodial ledger + BaaS | Requires a sponsor bank agreement. ~12 months and capital, gated on a decision we do not control. |
| Clean rebuild | Discards HCB's proven ledger, the single asset that makes this buildable at all. |
| Non-custodial with no fee path | No mechanism to collect a percentage of money we never touch. Kills the 7%. |

## Money flow

```
client pays invoice
  → Stripe charge on guardian-owned Connect Standard account
     → 93% settles to their bank
     → 7% application_fee → platform account
```

## Components

| # | Component | Responsibility | Depends on |
|---|---|---|---|
| 1 | Guardian onboarding | Teen signs up, invites guardian by email, guardian completes Connect Standard KYC as legal owner, teen receives operator access | Stripe Connect |
| 2 | Invoicing | Teen composes an invoice, sends a public pay link, client pays by card or ACH | 1 |
| 3 | Ledger | HCB's transaction ledger, reduced from multi-user orgs to single-operator businesses | 1 |
| 4 | Tax view | Tracks gross, expenses, and net; flags the $400 self-employment filing threshold; produces a year-end summary | 3 |
| 5 | Guardian console | Read-only oversight of the teen's activity; holds the subscription billing relationship | 1 |
| 6 | Landing + waitlist | Public site, waitlist capture, the Stage 1 validation gate | none |

Each component is independently testable. Onboarding can be verified without invoicing existing; the ledger can be seeded with fixtures and verified without a live charge.

## Pricing

- **7%** `application_fee_amount` on collected revenue, always.
- **$0/month** below $250 trailing-30-day collected revenue.
- **$15/month** above $250 trailing-30-day collected revenue, billed to the guardian.

A flat $15 from the first dollar takes 22% of a teen earning $100/month, which is Fiverr's take rate without Fiverr's demand. The revenue gate preserves the same money from real users and stops taxing beginners.

## Acceptance

1. `hangryclaude/fuime` boots locally: `bin/dev` starts and the home page renders at `localhost:3000`.
2. A `Business` model replaces the sponsored-organization entity as the primary object, linked to exactly one guardian-owned Stripe Connect Standard account.
3. Guardian onboarding completes end to end in Stripe test mode: teen signs up, guardian receives an invite, guardian finishes Connect KYC, teen lands on an operator dashboard.
4. A teen creates an invoice, a test card pays it, and the Stripe test dashboard shows the charge succeeded with `application_fee_amount` equal to 7% of the total.
5. The $15/month subscription activates only when trailing-30-day collected revenue exceeds $250, verified against a seeded fixture on both sides of the threshold.
6. The business dashboard renders income, expenses, and net from seeded data, and flags when net self-employment income crosses $400.
7. A landing page is deployed to a live Vercel URL with working waitlist capture, and its copy passes `no-ai-slop`.
8. Everything is committed and pushed, with a README that a stranger can follow to run it.

## Out of scope

Issued cards. Fund custody. LLC formation. Product sellers, resellers, and creators — service businesses only. School partnerships. Stripe live mode; v1 is test mode throughout.

## Risks

1. **Stripe must approve a platform whose operators are minors.** This is the kill risk. Everything else is work; this is someone else's decision. Confirm before live mode, not before building.
2. **Two-party signup destroys conversion.** Both teen and guardian must finish. Design onboarding to survive heavy drop-off, and instrument it from day one.
3. **HCB is Ruby on Rails** and large. Budget a week to run and understand it before changing behavior.
4. **AGPL-3.0.** Running this as a network service obliges publishing modifications. The fork is public on purpose.
5. **Churn is structural.** Every user ages out at 18. Acquisition never stops being the job.

## Human-only

The Stripe **platform** account requires an adult or a legal entity to sign. A 15-year-old cannot. Resolve with a parent, an adult co-founder, or Hack Club before live mode. This does not block the build.

## Sharpened

_(appended by the sharpen phase)_
