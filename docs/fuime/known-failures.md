# Known test failures

Required by CLAUDE.md Prime Directive #1: record which specs fail *before*
changing code, so a red suite can be attributed rather than guessed at.

This file was created late — during the 2026-08-01 hardening pass, not before
it. That was a process failure worth naming: the local toolchain could not run
rspec at all (see SETUP_NOTES.md), and rather than resolve that first, the work
proceeded without a baseline. When the full suite later showed failures there
was no reference point to attribute them against, and reconstructing one
afterwards cost more than recording it up front would have.

## How to measure a baseline

Use a worktree at the commit you want to measure, so the comparison is
apples-to-apples and the working tree stays untouched:

```bash
git worktree add /tmp/baseline <commit>
docker run --rm --network fuime_default \
  -v /tmp/baseline:/usr/src/app -w /usr/src/app \
  -e RAILS_ENV=test -e DATABASE_URL=postgres://postgres:postgres@db:5432 \
  -e REDIS_URL=redis://redis:6379 \
  fuime-web bundle exec rspec <paths>
git worktree remove /tmp/baseline
```

## Measurements

### `f51302a54` — "Rebrand public transparency banner" (pre-hardening)

The tip of `main` when the 2026-08-01 hardening pass began.

| Scope | Result |
|---|---|
| `spec/models/event_spec.rb spec/models/user_spec.rb spec/policies` | **148 examples, 0 failures** |

Full-suite baseline at this commit: **not measured.** Only the subset above was
run, so nothing here licenses a claim about the suite as a whole. Do not treat
this as "the baseline was green."

### Current `main` (post-hardening)

| Scope | Result |
|---|---|
| Same subset as above | **163 examples, 0 failures** (+15 new specs) |
| `spec/models/guardianship_spec.rb`, `user_guardianship_spec.rb`, `spec/services/fuime`, `spec/controllers/fuime`, `spec/policies`, `spec/models/user_spec.rb` | **203 examples, 0 failures** |
| `spec/controllers spec/requests` | 320 examples, **118 failures** — see below |

## The controller/request failures are an ENVIRONMENT artifact, not a regression

Controller and request specs render real views, and `_head.html.erb` pulls in
both the JS bundle and the stylesheet. With neither built in the container,
every view-rendering spec fails regardless of the code under test — via **two
different errors**, which is why fixing only the first barely moved the number:

```
ActionView::Template::Error: The asset "bundle.js" is not present in the asset pipeline.
LoadError: cannot load such file -- sassc
```

| Container state | Result on `main` |
|---|---|
| no JS, no CSS | 320 examples, 118 failures |
| JS built (`yarn build`) | 317 examples, **115 failures** |
| JS + CSS built (`+ yarn build:css`) | 320 examples, **49 failures** |
| JS + CSS + the fixes below | 320 examples, **23 failures**, 14 pending |

Versus **87 failures** at the pre-hardening baseline (`f51302a54`, no assets
built). Two genuine regressions were found in that 23 and fixed — see below.

Building the JS alone removed only 3 failures. The dominant cause was the
missing stylesheet, not the missing bundle — an earlier revision of this file
attributed everything to `bundle.js` on the strength of one inspected failure,
which was wrong.

The `sassc` error is misleading: `sassc` is **not** in the Gemfile and is not
supposed to be. CSS is built by postcss (`yarn build:css`); sprockets only
falls back to its sassc processor because the prebuilt `application.css` is
absent. The fix is to build the CSS, not to add the gem.

**Verified pre-existing**, two ways:

1. The same specs produce the same `bundle.js` error at `f51302a54`, before any
   hardening work.
2. Counted, both without assets built:

   | Commit | `spec/controllers spec/requests` |
   |---|---|
   | `f51302a54` (pre-hardening) | 303 examples, **87 failures** |
   | current `main` | 320 examples, **118 failures** |

   The suite was already substantially red — 87 failures before any hardening
   work.

## The +31 delta: two real regressions, found by diffing per-spec

An earlier revision recorded this delta as unexplained, then guessed it was
just new view-rendering specs. Re-running the baseline while **retaining the
failure list** — rather than filtering to the count — made the answer immediate.
Per-file counts, baseline vs `main`:

| Spec file | Baseline | `main` |
|---|---|---|
| `ach_transfers_controller_spec` | 1 | 5 |
| `increase_checks_controller_spec` | 1 | 5 |
| `reimbursement/reports_controller_spec` | 0 | 11 |
| `reimbursement/expenses_controller_spec` | 0 | 3 |
| `api/v4/card_grants_controller_spec` | 0 | 1 |

Both regressions came from `Fuime::DisabledModules`:

1. **It blocked GETs, not just writes.** Fuime must not *originate* a payment
   or issue a card — all POST/PATCH/PUT/DELETE. Blocking reads stopped anyone
   viewing records inherited from upstream (an ACH transfer's detail page,
   linked from the transaction drawer). Prevents nothing; breaks real paths.
2. **Reimbursements should never have been on the list.**
   `FUIME_HACKATHON_SPEC` lists them as "hide nav", not disable. Blocking them
   silently no-opped report PATCHes — a success response that changed nothing,
   which is worse than either allowing the action or plainly refusing it.

A third issue surfaced the same way: `api/v4/card_grants` was reachable while
the HTML `card_grants` controller was blocked — an open API back door. Eight
`api/v4/*` paths are now covered, with a spec that fails if any disabled HTML
module keeps an unguarded API twin.

**Lesson for the next baseline:** keep the failure list, not just the count.
Filtering to `grep "examples,"` cost several rounds of guessing at a delta that
a diff answered in one command.

**Fix before running these locally:**

```bash
docker compose run --rm -e RAILS_ENV=test \
  -e DATABASE_URL=postgres://postgres:postgres@db:5432 \
  web bash -c 'yarn install && yarn build'
```

CI does this as part of its setup, which is why it isn't visible there.

## Open

The full suite has still not been shown green at any commit. The model-, policy-,
and service-level specs are green and directly comparable to baseline; the
view-rendering specs are dominated by the asset artifact above and need a build
step before they say anything useful. Run both scopes with assets built, at
`f51302a54` and at `main`, to close this out.

### `16a003485` — "Document canonical domain migration" (2026-08-01)

Measured from a clean worktree, per the procedure above.

| Scope | Result |
|---|---|
| `spec/views spec/mailers spec/helpers` | **37 examples, 19 failures** |

**rspec does run locally** — the "local toolchain could not run rspec" note at
the top of this file is stale as of this measurement. The `fuime-web` image
against the running `fuime_default` network works; the two-file subset
`spec/models/event_spec.rb spec/models/user_spec.rb` gives 95 examples / 0
failures in ~4 minutes.

Most of the 19 failures are one environmental cause: mailer specs render
`stylesheet_link_tag "mailer"` and die on `LoadError: cannot load such file --
sassc`. The gem is missing from the test image. Fixing that would likely clear
most of these; it was not attempted here.

Full-suite baseline at this commit: **still not measured** (the suite is slow —
budget well over an hour). This subset is not a claim about the suite as a whole.

### `cafd73bba` vs. this branch — approval fix + money-in (2026-08-02)

Measured with the worktree method above, on separate databases so the two runs
could not contend (`bank_test` and `bank_baseline`), with **identical prebuilt
assets copied into both** so the asset artifact described earlier could not skew
the comparison.

| Scope: `spec/controllers spec/policies spec/models` | Examples | Failures |
|---|---|---|
| `cafd73bba` (baseline) | 1382 | **34** |
| This branch | 1407 (+25 new) | **34** |

The failure lists are **byte-identical** — `comm -23` of the two sorted lists is
empty. Zero regressions; the +25 examples are new passing specs.

The 34 are all pre-existing, in modules untouched by this work:
`ach_transfers`, `payroll/positions`, `wires`, `logins`, `user_session`,
`organizer_position_invites`, `comment_policy`, `has_payment_recipient`. None
overlap the seven application files changed here.

Per the lesson recorded above, the failure **list** was kept, not just the
count — which is what made "34 vs 34" provable rather than a coincidence of
totals.

### `97ddfe3e0` — "Turn test-mode card issuing back on" (Phase 1 baseline)

Measured 2026-08-02 in a clean `git worktree` at `HEAD`, with
`app/assets/builds` copied in so the asset-related failures documented above do
not dominate. Same scope, same container, both sides.

| Scope | Tree | Result |
|---|---|---|
| `spec/controllers spec/requests spec/policies spec/helpers` | `HEAD` | **450 examples, 22 failures, 14 pending** |
| same | `HEAD` + the Phase 1 honesty work | **474 examples, 22 failures, 14 pending** |

The failure lists are **identical** — diffed with `comm`, not compared by count.
The +24 examples are the 24 specs added by that work.

The 22 are pre-existing and cluster in five areas, none of them Fuime-authored:

| Area | Count |
|---|---|
| `payroll/positions_controller_spec` | 9 |
| `users/first_controller_spec` | 3 |
| webauthn (`logins_controller`, `webauthn_credentials_controller`) | 3 |
| `wires_controller_spec` (2), `ach_transfers_controller_spec` (1), `sudo_mode_handler_spec` (1), `organizer_position_invites_controller_spec` (1) | 5 |
| `comment_policy_spec` — factory hits "Company name is too long (maximum is 16)" | 1 |

The last one is Faker-seed dependent and will move between runs; treat a change
in that single example as noise rather than a regression. **Use this table as
the reference point for the next change**, and diff lists rather than counts.

### The full suite, measured at last — 2026-08-02 (plan lineup work)

**The first full-suite measurement in this repo's history.** Every entry above
this one is a subset, and each says so; the "Open" section's request to finally
run the whole thing is now answered.

Both sides run as **complete suites, in parallel, against separate databases** so
they could not contend — `bank_test` for the branch and `bank_planbaseline`,
cloned schema-only from it, for the baseline. Prebuilt assets were already
present in `app/assets/builds`, which is why the asset artifact that dominates
the earlier measurements does not appear here.

The baseline is **not** `HEAD`. `HEAD` was missing a concurrent session's
uncommitted Phase 1 work, so measuring against it would have compared two trees
differing in far more than the plan changes. Instead the working tree was copied
and *only* the plan-related files reverted to `HEAD` — a true one-variable
comparison.

| Tree | Examples | Failures | Pending |
|---|---|---|---|
| Working tree, plan changes reverted (baseline) | 2152 | **64** | 14 |
| Working tree, plan changes applied | 2162 | **64** | 14 |

Failure lists diffed with `comm`, per the lesson recorded above — **byte-identical
in both directions**. No new failures and none fixed. The +10 examples are exactly
the 10 added to `spec/models/event/plan_spec.rb`.

The 64 are all pre-existing, and all in modules the plan work does not touch —
the same families named in the `cafd73bba` measurement plus several this wider
scope reaches for the first time:

| Spec file | Failures |
|---|---|
| `controllers/payroll/positions_controller_spec` | 10 |
| `models/ach_transfer_spec` | 7 |
| `models/payroll/position_spec` | 6 |
| `mailboxes/receipt_bin_mailbox_spec` | 4 |
| `config/webauthn_configuration_spec` | 4 |
| `services/process_login_service_spec` | 3 |
| `.../import/outgoing_ach_spec` | 3 |
| `requests/users/first_controller_spec` | 3 |
| `mailers/payroll/position_mailer_spec` | 3 |
| 17 further files | 1–2 each |

Not one is a plan, fee, disbursement, storefront, legal-page or helper spec.

**Caveat, stated rather than papered over:** the branch run finished *before* two
final edits — the `legacy HCB fiscal sponsorship (n%)` labels and the
`eager_load!` in `plan_spec`. Rather than re-run 40 minutes for a label string,
the specs that could possibly depend on plan labels were identified by grep
(`spec/models/contract/party_spec.rb`, `spec/requests/documents_letters_spec.rb`,
`spec/models/event/plan_spec.rb`) and run together with `event_spec`,
`fee_relationship_spec` and `event_service/create_spec`: **67 examples, 0
failures**. The full-suite figure above therefore describes the tree minus two
string/test-setup changes, both separately covered.

## How to reproduce

```bash
docker exec fuime-db-1 psql -U postgres -c "CREATE DATABASE bank_planbaseline;"
docker exec fuime-db-1 bash -c 'pg_dump -U postgres -s bank_test | psql -U postgres -q bank_planbaseline'
docker run --rm --network fuime_default -v "$PWD":/usr/src/app -w /usr/src/app \
  -e RAILS_ENV=test -e DATABASE_URL=postgres://postgres:postgres@db:5432 \
  -e REDIS_URL=redis://redis:6379 fuime-web bundle exec rspec
```

Point `DATABASE_URL` at `/bank_planbaseline` for the baseline copy. Budget ~45
minutes per side; they run concurrently. Keep the failure **list**:

```bash
grep -a "^rspec \./spec" run.log | sed 's/ *#.*//' | sort > failures.txt
```

### `fuime/p0-honest-posture` @ 2026-08-04 (Connect ledger + payouts session)

Command (Docker, per "Running specs" in SETUP_NOTES.md):

```
spec/services/fuime/ spec/models/payout_request_spec.rb
spec/models/stripe_connected_account_spec.rb spec/models/guardianship_spec.rb
spec/models/user_guardianship_spec.rb spec/policies/ spec/controllers/fuime/
spec/requests/fuime/ spec/requests/marketing_spec.rb
```

**370 examples, 1 failure.**

| Failure | Count | Status |
|---|---|---|
| `comment_policy_spec:84` — factory hits "Company name is too long (maximum is 16)" | 1 | **Pre-existing**, already recorded above. Untouched this session. |

Sixteen other failures were present when this session began measuring and were all
fixed; see the 2026-08-04 entry in `UPSTREAM_DIVERGENCE.md` for what each was. The
short version: fifteen were the previous session's own specs, written but never run,
reporting two genuine app bugs (Pundit predicates below `private`, and the FDIC
disclosure missing from the signed-out layout branch) plus spec drift from the
pooled-to-Connect migration. One was a seed-dependent flake.

**Note on measuring this suite:** RSpec randomises order, and one storefront example
was flaky on name escaping (now fixed). If a single storefront or checkout example
fails on one run and passes on another, check for a Faker-generated string being
asserted against rendered HTML before assuming a regression.

---

## Full-suite baseline, 2026-08-05 (post upstream merge)

**2549 examples, 54 failures, 14 pending.**

**The previously recorded baseline of "573 examples, 1 known failure" was not the full
suite.** The suite is 2549 examples. Earlier sessions ran subsets — the Fuime-specific
directories listed in SETUP_NOTES — and recorded the result as if it were the whole thing.
Treat 2549/54 as the real number from here.

### None of the 54 are caused by the upstream merge

Attributed by cross-referencing the failing spec files against `git diff --name-only`
across the merge. Exactly one failing spec file was touched by the merge —
`spec/services/canonical_pending_transaction_service/unsettle_spec.rb:27` — and its failure
is `Validation failed: Company name is too long (maximum is 16 characters)`, from
`AchTransfer#company_name` being rebranded `"HCB (Hack Club)"` (15 chars) ->
`"Fuime (Hack Club)"` (17). That commit predates the merge.

The four `Ledger::Item` status migrations and the new unique indexes on
`canonical_pending_settled_mappings` broke nothing, which was the main risk going in.

### What the 54 actually are, by cause

1. **Stale rebrand assertions — specs still asserting Hack Club copy** (g_suite ×3,
   and others). e.g. `expected "Your Google Workspace account via Fuime is ready!" to
   include "...via HCB is ready"`, and `expected ["hcb@hackclub.com"] got
   ["support@fuime.com"]`. Milestone 3 required updating specs that assert copy; this was
   not finished.
2. **Disabled-module specs that were never marked pending** (ACH ×12, G Suite ×3, wires ×2,
   invoices ×1). Milestone 5 disabled these modules and asked for `# FUIME-DISABLED` tags.
   14 specs carry the tag; these do not.
3. **DocuSeal without credentials** (payroll/positions ×19, the single largest cluster):
   `Contract Party (N) role and/or slug missing in DocuSeal.` Environmental — DOCUSEAL_SETUP.md
   is already flagged as unverified against current code.
4. **`comment_policy_spec` ×1** — the failure the divergence log already records.
5. **Remainder** (`users/first_controller` ×3, `receipt_bin_mailbox` ×4, `user_session` ×2,
   and singles) — unexamined. `receipt_bin_mailbox` is the likely consequence of
   `HcbCode#receipt_email` deliberately returning nil now that Fuime has no inbound parser.

### Real bug worth carrying

`AchTransfer#company_name` is 17 characters against a 16-character limit, so **every outgoing
ACH would fail validation, not just the spec.** Harmless today because ACH is disabled, and
the trailing "(Hack Club)" only existed to satisfy Column, which Fuime has no relationship
with. Fix it whenever ACH is revisited; do not simply truncate to keep a Hack Club reference
Fuime does not need.

---

## Spec hygiene pass, 2026-08-05 (after the upstream merge)

The 54 failures recorded above were worked through. Almost none were what they looked like.

### The largest cluster was a stale stub, not missing credentials

19 failures across `payroll/positions_controller_spec`, `payroll/position_spec`,
`payroll/position_mailer_spec` and `organizer_position_invites_controller_spec` reported
`Contract Party (N) role and/or slug missing in DocuSeal.` That reads as an absent DOCUSEAL
credential. It was not: `Contract::Party#docuseal_role` returns **"Fuime"** for the `:hcb`
role since the rebrand, while five spec stubs still answered `"HCB"`. The submitter lookup
in `Contract#send_to_docuseal!` found no matching slug and called
`Rails.error.unexpected`, which raises under test.

### Three real bugs were hiding behind spec failures

1. **`AchTransfer#company_name` was 17 characters against a 16-character limit.** Every
   outgoing ACH would have failed validation, not merely the specs — invisible because ACH
   is disabled and the recorded baseline was a subset. Now `"Fuime"`; the `(Hack Club)`
   suffix existed only to satisfy Column, which Fuime has no relationship with, and it would
   have printed a Hack Club trademark on a recipient's bank statement (Rule 7). **One line,
   13 failures.**
2. **`Invoice#set_fields_from_stripe_invoice` had an unreachable branch.** It guarded the
   Stripe `finalized_at` -> `status_transitions.finalized_at` move with
   `inv.respond_to?(:status_transitions)`, but `inv` is a `Stripe::StripeObject`, which
   answers `respond_to?` affirmatively for essentially any name via `method_missing`. The
   guard was always true, the fallback was dead code, and an object with the old flat shape
   hit `nil.finalized_at`. Branches on presence now.
3. **`public_activity/user_session/create_spec` asserted an unreachable state** — a session
   built with `user: nil` then read via `.activities.sole`, when
   `after_save :create_login_activity` is guarded by `user(...).present?` (upstream #13577),
   so no activity is ever created. Rewritten to reach the fallback from the direction that
   is actually reachable.

### One spec was fixed by NOT making it pass

`organizer_position_invites_controller_spec` asserted that inviting a signee sends a fiscal
sponsorship contract. Fuime deliberately does not: `send_contract` returns early unless
`event.plan.contract_available?`, because no Fuime agreement exists and the upstream
templates are Hack Club's own legal documents. Correcting the stub would have made a test
pass by asserting behaviour we intentionally removed. Split instead: the param handling it is
named for still runs and now asserts that **no** DocuSeal request is made and no contract is
created, so the test fails if a Hack Club legal template is ever mailed to a Fuime user. The
original expectations are preserved in a `skip: "FUIME-DISABLED"` sibling (Rule 2).

### Stale rebrand assertions (Milestone 3's unfinished work)

Specs asserting Hack Club copy the code had already changed: G Suite mailer subject and
recipient, `"interested in HCB"`, `"You logged into HCB"`, the Stripe statement descriptor
`"HCB* Scrapyard"`, and the reimbursement mailer sender `hcb@staging.hcb.hackclub.com`.

### Tagged disabled (Milestone 5's unfinished work)

`wires_controller_spec` — wires are an outbound money path Fuime does not offer, and
`spec/controllers/fuime/disabled_modules_spec.rb` already asserts it. The create action
redirects (302) rather than reaching the sudo check (401).

### Environment-specific, NOT a Fuime issue — do not tag these disabled

`spec/mailboxes/receipt_bin_mailbox_spec.rb` (4 failures) fails only on **Apple Silicon**:

```
Invalid platform ... (missing binary: wkhtmltopdf_debian_13_arm64)
```

The `wkhtmltopdf-binary` gem ships no arm64 Debian 13 build. These pass on any supported
platform, so they are a local-toolchain gap and must not be marked FUIME-DISABLED — doing so
would hide a working feature. Anyone triaging on an M-series Mac should expect exactly these
four.

### `2d806dadc` — full suite, measured 2026-08-06

First full-suite measurement recorded in this file. **2656 examples, 8 failures, 17
pending.** All eight attributed individually; none are in the school-money surfaces
changed by that commit.

| Spec | Verdict | How attributed |
|---|---|---|
| `receipt_bin_mailbox_spec` :34 :48 :68 :84 | Environment | Apple Silicon — `wkhtmltopdf-binary` ships no `debian_13_arm64` build. Documented above. |
| `event/plan_spec.rb:32` | Pre-existing | `selectable_plans` asserts a six-plan lineup; `Event::Plan::School` (committed 2026-08-05 with `selectable? == true`) makes seven. Two committed specs contradict each other — `event_institutional_sponsorship_spec` asserts School IS selectable. Reproduced at `HEAD` before the school-money commit. |
| `stripe_connected_account_spec.rb:134` | Pre-existing | `mirrors livemode` expects true, gets false. Reproduced at `HEAD` before the school-money commit. |
| `guardianships_controller_index_spec.rb:91` | Pre-existing | Reproduced at `b115d34dc` (with `app/assets/builds` copied in, so not the asset artifact) — 6 examples, same 1 failure. Introduced by `e6691c7ac` "Auto-send the guardian invite". |
| `requirement_collections_controller_spec.rb:156` | Run-order pollution | **Passes in isolation.** Fails only in a full run, so it is leakage from an earlier example rather than a defect in the code under test. Worth fixing; not a regression. |

**Method note.** A fresh `git worktree` has no `app/assets/builds`, and every
view-rendering spec fails without it (see the asset section above), which makes a naive
worktree baseline useless for controller specs — it showed 13 failures where the working
tree showed 2. Copy `app/assets/builds/.` into the worktree before comparing anything
that renders a view.

### School-awards rescue branch — measured 2026-08-06 against `f467a507d`

The awards work itself: **45 examples, 0 failures**. The regression set around it —
`spec/policies`, `event_spec`, `event_institutional_sponsorship_spec`,
`event_school_payment_account_spec`, both `payout_request` specs, `spec/services/fuime`
and `spec/controllers/fuime` — **653 examples, 1 failure**, and that one is new to this
file:

| Spec | Verdict | How attributed |
|---|---|---|
| `event_spec.rb:296` "uses the standard plan as a fallback" | Pre-existing | Expects `Event::Plan::Standard`, gets `Event::Plan::Free`. `8f372bd0a` ("The pricing ladder") deliberately changed the root-venture fallback at `event.rb:1350` and did not update this upstream spec. **Reproduced on a detached checkout of clean `origin/main`**, with none of the awards commits applied. |

That last one is a stale assertion rather than a defect: the code comment at
`event.rb:1345` states the new default on purpose. Fixing it means editing an upstream
spec, so it wants its own commit and an `UPSTREAM_DIVERGENCE` line — deliberately not
folded into the rescue branch, whose job was to recover lost work unchanged.

## Full-suite baseline — measured 2026-08-13 on `fuime/mor-pivot-phase1`

**The first full-suite baseline in this file.** Everything above is a subset run, which is
why the counts here are so much larger and are not comparable to them. Recorded because the
merchant-of-record pivot touches `Event#can_front_balance?`, and a change to a balance
method can only be judged against a number somebody has actually measured.

`docker compose run --rm -e RAILS_ENV=test -e DATABASE_URL=... web bundle exec rspec`
(no path argument), ~14 minutes on an M-series Mac.

**2896 examples, 8 failures, 17 pending.** All 8 are already accounted for above:

| Spec | Verdict |
|---|---|
| `receipt_bin_mailbox_spec` :34 :48 :68 :84 | Environment — Apple Silicon `wkhtmltopdf` |
| `guardianships_controller_index_spec.rb:91` | Pre-existing (`e6691c7ac`) |
| `event/plan_spec.rb:32` | Pre-existing — the `School` plan lineup contradiction |
| `event_spec.rb:296` | Pre-existing — stale assertion after `8f372bd0a` |
| `stripe_connected_account_spec.rb:134` | Pre-existing — `mirrors livemode` |

`requirement_collections_controller_spec.rb:156` (recorded above as run-order pollution)
did **not** fail in this run. It remains order-dependent rather than fixed.

### Two specs that were red before this baseline and are green in it

Neither was a regression from the pivot; both are recorded here so the delta is
attributable rather than mysterious.

- **`spec/services/fuime/pooled_simulator_guard_spec.rb` :45 :50** — asserted the pooled
  handler posts ONE `CanonicalPendingTransaction` per payment. It posts two (the payment and
  Fuime's cut, `VentureLedger#payment_key` and `#fee_key`). Written in the 2026-08-11
  embedded-Connect work whose `UPSTREAM_DIVERGENCE` entry records "Verification: NOT RUN",
  so it had never passed. Corrected to `by(2)`.

### Specs newly tagged `:sponsor_banking`

`Event#can_front_balance?` now returns false unless `FEATURE_SPONSOR_BANKING` is on, and the
column defaults to false. Three files fund their events with **fronted** pending
transactions — credit the platform advances against unsettled sales — so they were asserting
against a $0 balance and failing with `inadequate_balance` or a transfer validation error.
They test upstream behaviour that is still correct *when custody is on*, so they are tagged
rather than rewritten (see `spec/support/sponsor_banking.rb`):

- `spec/models/ach_transfer_spec.rb` (7 examples)
- `spec/models/concerns/has_payment_recipient_spec.rb` (1)
- `spec/services/stripe_authorization_service/webhook/handle_issuing_authorization_request_spec.rb` (25)

Each also needed `can_front_balance: true` passed explicitly to its event factory, because
the tag governs whether Fuime fronts *at all* and the column governs whether it fronts for
that venture. A spec that spends fronted money now has to ask for both.

## Full-suite baselines — measured 2026-08-14 on `fuime/mor-pivot-phase1` (MoR phase 3)

Two runs, deliberately, at two different seeds. RSpec randomises order per run, and adding
~75 examples reshuffles everything — so a one-run comparison against the 2026-08-13 baseline
cannot distinguish a regression from an order-dependent spec that happened to land differently.

| Run | Seed | Result |
|---|---|---|
| A | 8951 | 2964 examples, 9 failures, 17 pending |
| B | 4242 | 2969 examples, 10 failures, 17 pending |
| **C (final)** | 30780 | **2969 examples, 8 failures, 17 pending** — the 8 pre-existing ones and nothing else |

Run B has five more examples than A because
`spec/controllers/fuime/selling_blockers_partial_spec.rb` was written after A had already
loaded its files. Run C is the state of the branch: B's two real failures fixed, and the
`flipper_groups` flake did not recur.

### `flipper_groups_spec.rb:25` — order-dependent, NOT a regression

Run A's ninth failure, absent from the 2026-08-13 baseline:

| Spec | Verdict | How attributed |
|---|---|---|
| `spec/initializers/flipper_groups_spec.rb:25` "gates a feature on the `:hcb_engineers` group" | **Pre-existing / order-dependent** | `expect(gate(:hcb_engineers, outsider)).to be(false)` got `true` — the feature read as enabled for everyone. **Passes in isolation** (6 examples, 0 failures) and **passed in run B** at a different seed. The spec exercises Flipper group wiring against `hackclub.com` email addresses; nothing in the phase 3 diff touches Flipper, its group config, or user emails. Its own header comment names the hazard: "a distinct feature per group keeps `enable_group` state from leaking between examples." |

Same class as `requirement_collections_controller_spec.rb:156` recorded above — a spec whose
result depends on what ran before it. Neither is fixed; both are attributable.

### The two real failures, found by run B and fixed

Both were in a spec written after run A, so this is the first run that ever executed them —
worth recording because the cause is a trap that will recur.

`selling_blockers_partial_spec.rb:51` and `:62` asserted
`include("This business can't take payments yet")`. The callout's title reaches the page
through `<%= local_assigns[:title] %>`, so the apostrophe renders as `&#39;` and the raw
string never appears. The markup was correct; the assertion was not. **This is the same trap
`storefronts_controller_spec.rb` documents for Faker names containing apostrophes.**

Fixed by asserting against `CGI.unescapeHTML(response.body)` rather than by rewording the
copy — the copy is what an operator reads and should not be shaped by the test. The same
helper was then added to `storefront_blocker_privacy_spec.rb`, where it matters more: that
file's guarantee is `not_to include(blocker)`, and an escaped page would have **passed while
leaking a child's age in plain sight**.

### Standing baseline after phase 3

**8 pre-existing failures**, unchanged from 2026-08-13 (4 × `receipt_bin_mailbox` Apple-Silicon
`wkhtmltopdf`, `guardianships_controller_index_spec.rb:91`, `event/plan_spec.rb:32`,
`event_spec.rb:296`, `stripe_connected_account_spec.rb:134`), **plus up to one order-dependent
flake** from the pair above depending on seed. Anything else is new and yours.

### Baseline after MoR phase 6 (2026-08-15)

**3091 examples, 8 failures, 17 pending.** +122 examples over the phase-3 run, and the
failures are the same eight, unchanged:

| Spec | Cause |
|---|---|
| `receipt_bin_mailbox_spec.rb` ×4 | Apple-Silicon `wkhtmltopdf` |
| `guardianships_controller_index_spec.rb:91` | pre-existing |
| `event/plan_spec.rb:32` | pre-existing |
| `event_spec.rb:296` | pre-existing |
| `stripe_connected_account_spec.rb:134` | pre-existing |

Nothing new. The order-dependent pair recorded above (`flipper_groups_spec.rb:25`,
`requirement_collections_controller_spec.rb:156`) did not recur at this seed.

One run, not three. The phase-3 note argues for several seeds when a change adds ~75 examples,
and that reasoning still holds — this run is a single seed and should be read as such. It is
recorded because the failure *set* matches the standing baseline exactly, which is the check
that matters; a second seed would strengthen it, not change what it says.

### Baseline after phase 7a (2026-08-15)

**3115 examples, 8 failures, 17 pending** — the same eight as the phase-6 baseline above,
unchanged. +24 examples.

One failure during the run was **new and correct**: `applications_spec.rb:37` "redirects to the
project info step" encoded the pre-phase-7 flow, where `#create` sent an applicant straight to
`project_info`. The business-type fork now comes first. The spec was updated to assert the new
destination rather than the behaviour being reverted — the redirect change is the feature.
