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
