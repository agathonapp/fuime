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
| Full suite | measurement in progress; see the handoff in SETUP_NOTES.md |

## Open

The full suite has not yet been shown green at any commit, before or after the
hardening pass. Until it has been run at `f51302a54` and at current `main`, any
failure in it is **unattributed** — it may predate this work or come from it.
Resolve this before the next milestone rather than carrying the ambiguity
forward.
