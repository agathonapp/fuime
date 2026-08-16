# Fuime docs — what lives where

The documents here accumulated across Phase 0, several overlapping. This index exists
so the next person does not read a stale blocker as a current one, which is the specific
failure mode doc sprawl produces.

**Read in this order if you are new:** `../../CLAUDE.md` → `LEGAL_RESEARCH.md` →
`LAUNCH_SPEC.md` → `SETUP_NOTES.md`.

| Document | What it is | Trust it for | Staleness |
|---|---|---|---|
| **LEGAL_RESEARCH.md** | The constraints the code is built against. Money transmission, COPPA, the minor-contracting problem, Stripe/Celtic card terms, the kid-fintech market table. | **Authoritative.** Every `L1`–`L8` reference in the code points here. Check it before agreeing *or* refusing on a compliance question — it often contradicts the assumption on both sides. | Aug 2026. Current. |
| **LAUNCH_SPEC.md** | The launch plan: go/no-go checklist, legal gates, provider approvals, every credential, feature work, sequence. | **The plan of record.** Start here for "what is left before real money." | §0 and §5 reconciled post-PR #28. §3 credentials still accurate. |
| **PRODUCTION_READINESS.md** | A point-in-time audit from 2026-08-01 that found the original blockers. | **History, not status.** Its numbered findings (§1.1–§2.7) are still the clearest write-up of *why* each control exists. | ⚠️ Its STATUS block is superseded — see the note at its top. Do not read its "still open" list as current. |
| **EMBEDDED_CONNECT.md** | The Stripe Connect integration end to end: what account each venture gets and why, which embedded components replace the Stripe Dashboard, which feature flags are deliberately off, and the `stripe listen` test plan. | **The reference for anything Connect.** Start here before touching payments, onboarding or payouts. | Aug 2026. Current — but the management surface has not been exercised against Stripe; see its §7. |
| **WHOP_EVALUATION.md** | Research dossier on Whop for Platforms as a substrate — card issuing, ledger, payouts, fees, and the stablecoin custody finding. Extends and corrects `MOR_MIGRATION_PLAN.md` §9. | **Research, not a decision.** Read §9 of the MoR plan first, then this. Its §10 is the ordered next-step list. | Aug 2026. Current. Nothing in it has been exercised against Whop. |
| **UPSTREAM_DIVERGENCE.md** | Append-only log of every divergence from upstream HCB, newest last. Required by CLAUDE.md Rule 8 so upstream ledger and security fixes can still be merged. | Understanding *why* a specific file differs from hackclub/hcb. | Current. Large (~190KB); read the last entry first, then search by filename. |
| **SETUP_NOTES.md** | How to actually run the thing, plus a handoff note at the top from each session. | Getting a local environment up, and the gotchas that cost time. | Current. Handoff newest-first. |
| **ADMIN_OPS_QUEUES.md** | Spec for the admin queues Fuime's own money model needs (failed payouts, connected-account status, stuck guardianships, past-due subscriptions). | **Deliberately unbuilt** — parked behind the `stripe listen` pass per CLAUDE.md. Build from it when engineering resumes. | Aug 2026. Current. |
| **known-failures.md** | Recorded spec baselines, so a red suite can be attributed rather than guessed at (Prime Directive 1). | Deciding whether a failure is yours. | Current. Latest baseline: 573 examples, 1 known failure. |
| **BRAND_STRINGS.md** | Every file touched during the HCB → Fuime surface rebrand. | Finding remaining Hack Club references. | Milestone 3 era. |
| **DOCUSEAL_SETUP.md** | DocuSeal integration notes. | That integration only. | Unverified against current code. |

## Conventions

- **Legal constraints are cited as `L1`–`L8`**, defined in `CLAUDE.md` and sourced in
  `LEGAL_RESEARCH.md`. Code comments reference them by number.
- **`PRODUCTION_READINESS.md` section numbers (§1.4, §2.1, …) are still cited from code
  comments** and from the other docs. They are stable identifiers for *findings*, even
  though the document's own status summary is out of date. Do not renumber them.
- **The money-in path has now been exercised against Stripe** (test mode, 2026-08-14):
  `Fuime::PaymentLinkService`'s direct-charge shape is accepted, and
  `application_fee_amount` is stored at the right value. **Everything else is still
  documentation-derived** — no webhook, no onboarding, no ledger posting has ever run.
  Results and the remaining steps are in `EMBEDDED_CONNECT.md` §7, which is the only place
  that record lives.
