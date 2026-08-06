# Admin ops queues — spec (not yet built)

**Status: spec'd 2026-08-05, deliberately unbuilt.** CLAUDE.md's current position says
the `stripe listen` pass outranks writing more features, and every queue here renders
webhook-fed state — so building them *before* the pass would mean building dashboards
over data shapes nobody has verified. Build order: stripe listen pass → this doc.

## Why this exists

The admin trim (see UPSTREAM_DIVERGENCE.md, 2026-08-05) removed HCB's ops desk — the
ACH/checks/wires/payroll queues for money rails Fuime doesn't have. What it exposed is
that Fuime's *own* money model has no ops surface at all. Concretely, today:

- A family payout that **fails at Stripe** (`PayoutRequest#mark_failed`, including the
  post-hoc reversal path from `paid`) is recorded faithfully and shown to nobody.
- A connected account that Stripe **disables for charges or payouts** (requirements
  past due) silently stops a venture's income; no admin list exists.
- A teen parked at "invite your guardian" (`Guardianship` stuck `pending`) is invisible
  except one-user-at-a-time on `/users/:id/admin`.
- A Pro family whose card fails goes `past_due` in `Fuime::Subscription` via webhook
  and keeps their venture slots until someone happens to look.

HCB never needed these because its ops desk *was* the money movement. On a Connect
platform Fuime is never in the flow of funds (L1) — so ops' job shifts from "move the
money" to "notice when Stripe/the family is stuck." These queues are that noticing.

## Shape: one section, four queues

Add a **"Fuime Ops"** section to `Admin::Nav` (first position — it is the section with
real tasks) and mirror the task-badge cards onto `admin_tools`. Follow the existing
pattern exactly: `Admin::Nav::Item` with `count_type: :tasks` for actionable queues,
`:records` for indexes. All pages are `AdminController` actions (or an
`Admin::` namespaced controller like `admin/payments_controller.rb`) behind the
existing admin constraint. Read-only first; the only write actions are the two
explicitly listed under Payouts.

### 1. Payout requests

- **Query:** `PayoutRequest.recent_first`, filterable by state. Badge counts
  `aasm_state: "failed"` — failures are ops' to-do; `pending` belongs to guardians,
  not ops (that's the whole approval gate), and `awaiting_settlement` belongs to the
  school's business office (it already has that scope, surfaced on the school org).
- **Columns:** venture, requester, approver, amount, destination
  (`account_owner_bank` / `personal_transfer`), state, `failure_code` /
  `failure_message`, `stripe_payout_id` (link to Stripe test-mode dashboard),
  timestamps.
- **Actions:** none on the happy path. For `failed`: a "mark paid" button calling the
  existing `mark_paid` event (valid transition `failed → paid`) for the case where the
  family re-attached a bank and Stripe retried — **only** after the operator confirms
  in the Stripe dashboard; the button copy should say that. Rejection/approval stay
  guardian-only (`approver_must_be_the_responsible_adult` already admits admins for
  stuck cases — that stays the escape hatch, exercised from the venture page, not
  here).
- **Why not auto-notify instead:** notification is also unbuilt; a queue is the
  precondition for knowing a notification system works. Do the queue first.

### 2. Connected accounts

- **Query:** `StripeConnectedAccount.all`, ordered so problems float:
  `#status` (derived: `ready` / `ready_action_needed` / disabled-ish states) is not a
  column, so order in Ruby or expose the underlying booleans:
  `charges_enabled: false` first, then `requirements_outstanding?`.
- **Badge:** count of accounts where `charges_enabled: false` OR
  `requirements["past_due"]` non-empty. These are ventures that cannot take money.
- **Columns:** venture(s) (via `Event#payment_account` — remember school accounts are
  shared, so one row may back many ventures), owner (guardian) with link to
  `/users/:id/admin`, `charges_enabled`, `payouts_enabled`,
  `requirements_currently_due` / `past_due` / `pending_verification` (rendered as the
  raw requirement keys — they are Stripe's vocabulary and ops will paste them into
  Stripe search), `disabled_reason`, last webhook-update timestamp.
- **Actions:** none. The fix always happens on Stripe's side or the guardian's;
  the page's job is a deep link to the account in the Stripe dashboard.

### 3. Guardianships & verifications

- **Query:** `Guardianship.pending` ordered oldest-first (staleness is the signal),
  plus a second tab/list for `GuardianVerification` records not yet `accepted`
  (`accepted_at: nil`, `submitted_at` present).
- **Badge:** pending guardianships older than N days (start N=7; a fresh invite is
  not a problem, a stale one is a lost family).
- **Columns:** minor (age via `date_of_birth`), guardian email invited, invited-at,
  and for verifications: method, vendor ref, submitted-at. **Never any ID imagery or
  verification payload — L4; the consent record is the only thing that exists to
  show, which is the point.**
- **Actions:** resend invite (exists on the user admin page — reuse, don't duplicate
  logic). Revocation stays on `/users/:id/admin` where the context (who is this
  person) lives.

### 4. Subscriptions

- **Query:** `Fuime::Subscription.all`; badge counts `status: "past_due"` +
  `"incomplete"` older than ~1 day (Stripe's own retry window makes fresher ones
  noise).
- **Columns:** `billed_to` user, family vs event scope (`event_id` nil ⇒ family-wide
  Pro), status verbatim from Stripe, current-period end, Stripe subscription id
  (dashboard link).
- **Actions:** none. Dunning is Stripe's; plan enforcement is
  `Event#billing_plan`'s. The page answers "who is about to fall off Pro and does
  their slot math change" before support finds out from an angry parent.

## What deliberately does NOT exist

- **No admin approval of payouts.** The guardian gate is L2's load-bearing wall;
  an ops queue that can approve would quietly become the real approval path.
- **No editing of connected-account or subscription state.** Both models mirror
  Stripe verbatim; local edits would fork the truth. Fixes happen at Stripe.
- **No bulk actions anywhere.** Every record here is one family's money or one
  minor's guardianship; the volumes that justify bulk tooling are a problem Fuime
  would be lucky to have, and bulk mistakes here are the expensive kind.
- **No new notification channels.** Queues first, alerting later, if ever.

## Verification plan (when built)

- Model scopes: spec each badge query against factories in every state.
- Request specs: each page as admin (200, shows the fixture rows) and as non-admin
  (redirect) — same pattern as existing admin request specs.
- The nav spec (`spec/models/admin/nav_spec.rb`) will need its section list updated;
  it has been the canary for every nav change so far.
- Badge lambdas must be cheap: every count here is a single indexed `where.count`
  (`payout_requests` already has the partial index on pending; add equivalents for
  `failed` and for `guardianships.status` if the planner says so — new migrations
  only, Rule 5).
