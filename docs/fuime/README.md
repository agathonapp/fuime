# Fuime docs — what lives where

Eight documents accumulated here across Phase 0, several overlapping. This index exists
so the next person does not read a stale blocker as a current one, which is the specific
failure mode doc sprawl produces.

**Read in this order if you are new:** `../../CLAUDE.md` → `LEGAL_RESEARCH.md` →
`LAUNCH_SPEC.md` → `SETUP_NOTES.md`.

| Document | What it is | Trust it for | Staleness |
|---|---|---|---|
| **LEGAL_RESEARCH.md** | The constraints the code is built against. Money transmission, COPPA, the minor-contracting problem, Stripe/Celtic card terms, the kid-fintech market table. | **Authoritative.** Every `L1`–`L8` reference in the code points here. Check it before agreeing *or* refusing on a compliance question — it often contradicts the assumption on both sides. | Aug 2026. Current. |
| **LAUNCH_SPEC.md** | The launch plan: go/no-go checklist, legal gates, provider approvals, every credential, feature work, sequence. | **The plan of record.** Start here for "what is left before real money." | §0 and §5 reconciled post-PR #28. §3 credentials still accurate. |
| **PRODUCTION_READINESS.md** | A point-in-time audit from 2026-08-01 that found the original blockers. | **History, not status.** Its numbered findings (§1.1–§2.7) are still the clearest write-up of *why* each control exists. | ⚠️ Its STATUS block is superseded — see the note at its top. Do not read its "still open" list as current. |
| **UPSTREAM_DIVERGENCE.md** | Append-only log of every divergence from upstream HCB, newest last. Required by CLAUDE.md Rule 8 so upstream ledger and security fixes can still be merged. | Understanding *why* a specific file differs from hackclub/hcb. | Current. Large (~190KB); read the last entry first, then search by filename. |
| **SETUP_NOTES.md** | How to actually run the thing, plus a handoff note at the top from each session. | Getting a local environment up, and the gotchas that cost time. | Current. Handoff newest-first. |
| **known-failures.md** | Recorded spec baselines, so a red suite can be attributed rather than guessed at (Prime Directive 1). | Deciding whether a failure is yours. | Current. Latest baseline: 573 examples, 1 known failure. |
| **BRAND_STRINGS.md** | Every file touched during the HCB → Fuime surface rebrand. | Finding remaining Hack Club references. | Milestone 3 era. |
| **DOCUSEAL_SETUP.md** | DocuSeal integration notes. | That integration only. | Unverified against current code. |

## Conventions

- **Legal constraints are cited as `L1`–`L8`**, defined in `CLAUDE.md` and sourced in
  `LEGAL_RESEARCH.md`. Code comments reference them by number.
- **`PRODUCTION_READINESS.md` section numbers (§1.4, §2.1, …) are still cited from code
  comments** and from the other docs. They are stable identifiers for *findings*, even
  though the document's own status summary is out of date. Do not renumber them.
- **Nothing in this repo has been exercised against Stripe**, in any mode, as of the
  latest entry in `UPSTREAM_DIVERGENCE.md`. Treat every API parameter shape as
  documentation-derived until a `stripe listen` run says otherwise.
