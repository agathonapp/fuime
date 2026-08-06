# Fuime — Setup Notes

## Handoff (most recent first)

**2026-08-06 (later) — CI had never run, and a school can now be funded.** Two things.

**(1) No test had ever executed in CI on this fork.** `ci.yml` — sharded RSpec,
Rubocop, ERB lint, ESLint, Prettier — was committed and dormant, because GitHub
disables *inherited* workflows on a fork until someone clicks through the Actions
banner. `gh workflow list` showed only CodeQL. That is the root cause of PR #55
shipping `current_user.staff?` to `main` with no such method: nothing ran. Now enabled;
expect the first runs to surface the 8 pre-existing failures in known-failures.md plus
whatever CI-specific asset problems §4.10 predicted. **If CI ever goes quiet again,
check that banner first.**

**(2) `SchoolFunding` closes the awards feature's open question** — money can now get
INTO a school's Stripe balance (`Stripe::Topup` on its own account), which awards then
reattribute. The one thing to know before touching it: **whether a `:payments_only`
(Stripe-liability) connected account may create top-ups through the API is unverified.**
The webhook recorder is built so it does not matter — a top-up made in the Stripe
Dashboard produces the same `topup.succeeded` and the same ledger credit. Verify with a
`stripe_pass` run before telling a school the in-app button works.

**2026-08-06 — A merged PR is not the same as merged work. It happened twice.** PR #52
was opened at `67f9c1597`; two further commits were made on `fuime/paywall-signage`
afterwards and never pushed, so ~1,400 lines of school awards — migration, model,
service, controller, view, three spec files — merged nowhere while `main` looked healthy.
The only symptom was a dirty `db/schema.rb` describing a table with no migration behind
it.

**The second one shipped a red `main`.** PR #55 merged the *callers* of `User#staff?`
(`Fuime::BillingController`, `fuime/billing/show`) while the method's definition, its
three other call sites and both spec files stayed uncommitted in the working tree. So
`/my/billing` raised `NoMethodError` for every user on `main` — found only because a
regression run on an unrelated branch went red. Both halves are recovered in PR #56.

**One PR merging half a feature is not rare here, it is the house failure mode.** Both
came from committing on a branch after its PR was already open, in a checkout shared with
another session.

**Two habits this argues for.** (1) After a PR merges, check
`git log --oneline origin/<branch>..<branch>` before deleting the local branch — GitHub
deletes the remote on merge and a later prune sends unpushed commits to reflog-only.
(2) A dirty `db/schema.rb` is a *symptom*, never a thing to just commit; ask which
migration produces it and confirm that migration is tracked at `HEAD`.

**Also worth knowing:** running two sessions against one checkout and one dev Postgres is
how this happened. An isolated `git worktree` plus `docker compose -p fuime run --rm web`
from inside it reuses the running `fuime-db-1`/`fuime-redis-1` while mounting the
worktree — but `.env.development` is gitignored and `app/assets/builds` is empty in a
fresh worktree, so copy both in first or every view-rendering spec fails misleadingly.

**2026-08-06 — Every Fuime admin was a parentless minor.** The age check is
fail-closed (`minor_or_unknown_age?`: no birthday ⇒ minor) and no staff account
has a birthday, so admins hit the teen branch of every gate written on it — the
family-plan page told its own operators to "ask your parent" and refused to sell
them the plan. `User#staff?` names the exemption that EventPolicy and
GuardianshipEnforcement had each already invented privately; billing, the paywall
banner, the activation gate (applicant only — activating someone else's
application is unchanged) and the Guardian menu link now use it. For seeing what
a user sees, use impersonation, not a preview mode — it already exists at
/admin/users and swaps `current_user` for real. 297 examples green; full suite
not re-run.

**2026-08-05 — The admin console is Fuime's now.** HCB's ops desk (ACH, checks,
wires, Wise, disbursements, payroll, donations, Column/Plaid/Intrafi, G Suite,
Emburse, the hack.af knowledgebase link) is out of the nav and admin_tools —
FUIME-DISABLED comments, routes untouched, capability unchanged since M5. Also
gone: the last live-capable call to identity.hackclub.com in admin_controller.
What the trim exposed: Fuime's own money model has NO ops surface — a failed
family payout, a charges-disabled connected account, a stuck guardianship, a
past_due Pro subscription are all invisible. Spec'd in ADMIN_OPS_QUEUES.md,
deliberately unbuilt: the stripe listen pass still outranks it. Nav spec 5/5,
rubocop clean; full suite not re-run (no logic changed).

**2026-08-06 — Schools can earn, and cash out has a second shape.** The school
programme was half-built: only three of five surfaces got the guardian->school
substitution, and money-in was never wired. A student sub org under a fully onboarded
school took **$0** (`stripe_connected_account` is per-event with no fallback) and was
billed **4%** while its school was 0%. Worse, `decide_payout?` needed a guardian that a
school venture never has, while `request_payout?` let the student ask — so one click
wedged the venture permanently. `Event#payment_account` / `#billing_plan` now resolve up
the tree, gated on `institutionally_sponsored?` so upstream HCB sub-orgs are untouched.

**Three things worth knowing before touching this.** (1) On a shared account Stripe's
balance is the WHOLE programme's — anything reading a balance to decide what one student
may take must cap against `balance_v2_cents`, or student A withdraws student B's
revenue. (2) Stripe pays out only to the account holder's own bank, so it *cannot* send
a student's share to a student's account; `personal_transfer` records the authorisation
and the school pays through its own AP, and the ledger debit waits for `#settle!`, not
approval. (3) `Event#reload` does NOT clear plain ivars — three tree-resolved answers
are memoized, and a plan change on a warm object silently billed on the old plan until
`reload` was taught to clear them.

**Toolchain:** the Docker image was stale against `Gemfile.lock` (faraday bumped in
`df797ba3e`) and rspec would not boot — `command not found: rspec`, then
`Could not find faraday-1.10.6`. `docker compose build web` fixes it; the `gems` volume
in docker-compose.yml is commented out, so gems live in the image and a lock bump means
a rebuild. Baseline caveat now in known-failures.md: a fresh worktree has no
`app/assets/builds`, so copy it in before baselining anything that renders a view.

**Full suite: 2656 examples, 8 failures, 17 pending** — all eight pre-existing and
individually attributed in known-failures.md. **Still nothing has run against Stripe.**

**2026-08-04 (evening) — Cards and guardian verification.** Same branch. Three layers
went in after the payouts work: (1) **account profiles** — `controller` is create-only at
Stripe, so `:payments_only` (default, Stripe-liable) vs `:cards_enabled` (Fuime absorbs
losses, collects SSNs, pays processing) is decided at creation and can never be changed;
a venture cannot be upgraded into cards, it re-onboards. (2) **Cards** —
`Fuime::CardSpendPolicy` enforces "business purchases only" as a Stripe
`allowed_categories` allowlist (allowlist not blocklist: a missed category declines a
purchase, a missed blocklist entry is a compliance violation). Guardian is the
Accountholder, teen the Authorized User, and issuance **cancels any card Stripe returns
without the controls applied**. (3) **Guardian verification** — collect-and-forward: PII
goes straight to Stripe, `guardian_verifications` holds metadata only, and a spec fails
the suite if a PII-capable column is ever added.

**Two things worth knowing before touching this.** `Stripe::StripeObject#to_h` is
SHALLOW — nested values stay StripeObjects with no `dig`, so it fails on the *second*
key. Use `Fuime::StripeHash.deep`. And uploading a file for a connected account needs the
`Stripe-Account` header while updating that account does not; getting either backwards
looks like a permissions bug.

**Nothing has run against Stripe, still.** The blocker is not code: the three questions
in LEGAL_RESEARCH need answers, and question 3 (will underwriting class a teen sole-prop
with a guardian representative as consumer rather than business?) can invalidate the
whole card path. Also unverified: `payouts.schedule.interval=manual`, and Stripe's own
processing fee is still not posted to the ledger.

**2026-08-04 — The ledger sees Connect charges, and money can leave.** Same branch
`fuime/p0-honest-posture`. Two things shipped. (1) **Direct charges now reach the
ledger.** `Fuime::ConnectPaymentRecorder` maps `event.account` → connected account →
venture (Stripe's word, not our metadata), reads the fee from
`application_fee_amount` instead of recomputing it, and — the one real behaviour
difference from the pooled handler — only credits Fuime's fee back on
`application_fee.refunded`, because Stripe does NOT return an application fee on a
plain refund and posting a rebate would print money into a family's ledger that is
still in ours. (2) **Payouts**: teen requests, guardian approves, Stripe sends to the
family's bank. `Fuime::ConnectOnboardingService` now sets
`payouts.schedule.interval=manual`, without which Stripe drains the balance on a
timer and the approval gate is theatre.

**Found and fixed a bug that made the whole payment-setup flow 500:**
`EventPolicy#setup_payments?` and `#payment_setup_status?` sat BELOW `private`, and
Pundit resolves queries with `public_send`. The previous session's specs were saying
so; they had never been run. `spec/policies/event_policy_payouts_spec.rb` now pins
the visibility of all five Fuime predicates.

**Cleared from the last handoff:** `Stripe::AccountSession` **does** exist in stripe
11.7.0 (so do `Payout`, `Balance`, `ApplicationFee`) — no need for the Account Links
fallback. And rspec runs fine; the toolchain gap was only that the Docker daemon was
off. `docker compose up -d db redis`, then `rails db:migrate` with `RAILS_ENV=test`,
then the spec command below.

**Read `docs/fuime/UPSTREAM_DIVERGENCE.md` (2026-08-04 entry) for what is still
missing.** Short version: nothing has touched Stripe even in test mode, so verify
`payouts.schedule.interval=manual` against a real test-mode account first — platform
control of the payout schedule interacts with `losses.payments=stripe` and that
combination is unconfirmed. Also, Stripe's own processing fee is still not posted, so
the ledger overstates each balance by Stripe's cut.

**2026-08-03 (later) — Stripe Connect: the pooled account is gone.** Same branch
`fuime/p0-honest-posture`. Money-in is now a **direct charge on a connected account
the guardian owns**; Fuime takes a platform fee and is out of the flow of funds,
which is what CLAUDE.md L1 requires. Account config is
`losses.payments=stripe` + `requirement_collection=stripe` +
`stripe_dashboard.type=none` — the first choice forces the other two (Stripe
documents `requirement_collection=application` as incompatible with Stripe-liability),
and the side effect is that the guardian's SSN never touches Fuime's database. New
`stripe_connected_accounts` table (one per venture, `event_id` UNIQUE — that index
is the anti-commingling guarantee), `Fuime::ConnectOnboardingService`, a four-surface
guardian flow at `/:event_slug/payments`, a second Connect-scoped webhook endpoint,
and `@stripe/connect-js`. Fixed a live bug on the way: the storefront's public
"Guardian on account" badge was reading `point_of_contact.has_active_guardian?`, and
`point_of_contact` is the *activating admin* — so it published whether a Fuime staff
member has a parent. Also fixed: the platform fee never consulted `event.plan`, so
Founders-plan ventures (0%) were charged 4%.

**Three things to do before trusting any of it.** (1) **Verify
`Stripe::AccountSession` exists in stripe 11.7.0** — the gem is pinned to a late-2024
version and could not be introspected (gems aren't installed), so the embedded flow
rests on an unverified assumption. If it's missing, upgrade the gem or fall back to
Account Links and accept a redirect. (2) Nothing here has been executed against
Stripe at all — no account created, no session minted, no webhook received; the
parameter shapes come from documentation, not from a successful call. (3) Five spec
files are unexecuted; run them in Docker.

**⚠️ Cards — resolved, and the answer is "not in this repo".** Researched properly
(addendum in LEGAL_RESEARCH.md). Age is *not* the blocker: Stripe documents the
Issuing cardholder floor as **13**. Three real blockers instead. (1) A Stripe
Issuing card is a **business-purpose commercial charge card** — "you may not use
your card for personal, family or household purposes", cannot be topped up from a
parent's personal funds, no consumer protections. It buys inventory; it cannot be
a teen's spending money. (2) Issuing needs `losses.payments=application`, which
drags `requirement_collection` (guardian SSNs into Fuime's systems) and
`fees.payer` (Fuime pays all Stripe processing — a pricing change) with it, and
**`controller` is create-only** so every existing family would have to re-onboard.
(3) The BaaS alternative is closed at this stage: Evolve is barred by its Fed order
from onboarding new fintech partners without regulator approval, CFSB and Choice
are both under orders, and Synctera screens at Series C+. Copper — same size, same
stage — lost its cards on 24 hours' notice in 2024. **Keep the Issuing UI hidden;
the funding incompatibility is documented in `Fuime::DisabledModules`.** Near-term
path is refer-out: payouts settle to the family, they spend on a card they already
have, Fuime keeps the ledger and the parent visibility.

**Next:** ledger semantics under direct charges (the gross payment is now a mirror
of the family's Stripe balance, not funds Fuime holds, and `record_platform_fee` is
redundant with `application_fee_amount`), then the plan lineup.

**2026-08-03 — the legal review landed, and the architecture has to change.**
Written on `fuime/p0-honest-posture` off `4fec272d8`. New file
`docs/fuime/LEGAL_RESEARCH.md` is the output of a seven-workstream
primary-source review; its 16 load-bearing citations were independently
re-verified. Two findings are structural and are now `CLAUDE.md` constraints
L1–L8. (1) **The pooled-account model can never go live.** Taking customers'
payments into Fuime's own Stripe balance and paying out on request is money
transmission (31 CFR 1010.100(ff)(5)); unlicensed operation is criminal under
18 U.S.C. § 1960, and it independently violates Stripe's restricted-business
rules. HCB escapes this only because donations become a 501(c)(3)'s own assets —
"Column + Stripe like Hack Club" does not transfer to a for-profit. Production
money-in becomes **Stripe Connect, guardian-owned connected account per
venture**, which is a new spike, not a change to the existing pipeline; keep the
pooled pipeline as the test-mode simulator it already is. (2) **SSN-free
onboarding is impossible once money moves** — Stripe requires the guardian's SSN
last-4 before an under-18 account can charge or pay out. This session shipped
only the P0 copy work: the guardian invite no longer claims an identity check
Fuime does not perform, "business account" is gone in favour of "venture", the
FAQ no longer says a minor cannot sign a contract (they can — it is voidable at
*their* option, which is the whole reason guardians exist), and a standing
"financial technology company, not a bank" disclosure now renders in the footer
**and** separately in the storefront, which takes the no-nav layout branch and
never renders `application/_footer`. **Verification gap worth naming:** rspec
did not run — `bundle exec rspec` reports the executable missing *and* the
Docker daemon was down, so the container path below was unavailable too. Changes
are copy-only and `ruby -c` passes on every `.rb`, but two specs
(`spec/requests/fuime/status_disclosure_spec.rb`, new; `spec/requests/marketing_spec.rb`,
amended) have never been executed. **Run those two first.** One gap was opened
knowingly: the site now publishes the Starter/Standard-7%/Pro-$15+4%/Founders
lineup while the app still ships Standard at 4% and has no Starter or Pro class,
because that fee constant feeds Stripe metadata, the ledger fee line **and** the
proportional refund reversal — three money paths I could not test. It is
survivable only because nothing is billed in test mode and the site says so;
closing it is the top P1 item and is written up in UPSTREAM_DIVERGENCE.md with
the exact files. Also shipped in this session, and the first real feature work
rather than copy: **guardian oversight**. Agreement §3 promises the signing adult
visibility that "cannot be turned off by the minor", and nothing implemented it —
`EventPolicy#reader?` resolved only through `OrganizerPosition` and accepting a
guardianship creates none, so the predicate was false for every guardian who ever
signed. Milestone 4's open design question is now decided and recorded: access
derives from the **Guardianship record, not an OrganizerPosition**, because the
minor is a manager of their own venture and could delete a membership row —
which would make the one guarantee their parent relies on revocable by exactly
the person it exists to be independent of. New `GET /guardian` overview, a
`Guardianship.overseeing_event` scope, `EventPolicy#guardian_reader?`, and a nav
entry. Read-only by construction: `member?`/`manager?` do not consult it, and all
27 `reader?` call sites were audited. Two new spec files are **unexecuted** —
`spec/policies/event_policy_guardian_spec.rb` and
`spec/controllers/guardianships_controller_index_spec.rb`. Next session: run all
four unexecuted spec files, then the plan lineup, then the Connect spike
(LEGAL_RESEARCH.md "Recommended path" P1).

**2026-08-02 — Phase 1: the app now tells the truth about itself.** Written
against `97ddfe3e0`, in a working tree a second session was editing at the same
time — name the commit, not the branch, because the branch moved underneath this
work mid-session (`fuime/enable-card-issuing` → `fuime/front-on-approval`).
Two live misrepresentations closed. (1) `/privacy`
was redirecting to `hackclub.com/privacy-and-terms/` and `/faq` to
`help.hcb.hackclub.com` — Fuime serving another organisation's documents as its
own, which blocks the first real signup. There are now real `/privacy`,
`/terms`, `/guardian-agreement` and `/faq` pages, linked from the footer and
from onboarding. The guardian agreement page renders **the same versioned
partial the signing flow renders**, so the published text cannot drift from the
binding one; it passes a `Struct` stand-in for the minor rather than editing the
versioned file, whose own header forbids that. (2) Stripe runs in test mode in
production, and nothing said so — a storefront asked strangers for card numbers
and the Cards page issued real-looking cards. There is now an app-wide banner
plus specific copy on both surfaces, all reading `StripeService.live?`, so going
live removes every one of them at once. Also repointed
`security_reporting_email` and `github_url` off Hack Club.
**Measurement:** baseline taken in a clean worktree at `HEAD` with assets copied
in — 450 examples / 22 failures, versus 474 / 22 with this work. Failure lists
diffed with `comm` and **identical**; the +24 are the 24 new specs. See the new
table at the end of `known-failures.md` and use it as the next reference point.
**Gotcha:** `docker run --rm ... | tail -N` buffers everything until the
container exits, so a long run looks like a hung one with a 0-byte log. Also
note `docker run` names containers randomly — to wait on a run, poll
`docker ps --format '{{.Image}}' | grep '^fuime-web$'`, not the container name.
**Still operator-only, and each still open:** object-storage credentials
(receipts are *still* dying on every deploy — `render.yaml` says `amazon` with
nothing behind it), `APPSIGNAL_PUSH_API_KEY` (newly added to `render.yaml` for
both services), and a real `support@fuime.com` inbox, which every legal page now
routes COPPA deletion and export requests to.
**Storage does not have to be AWS.** `config/storage.yml` now takes an optional
`S3__ENDPOINT`, so Cloudflare R2 (recommended — no egress fees) or Backblaze B2
work unchanged. A **Render persistent disk cannot** be used: a disk is reachable
by one service instance only and not from another service, and `fuime-worker`
really does read uploaded bytes (receipt OCR, `check_deposit.front.open`,
Active Storage's `AnalyzeJob`). Don't relitigate this — it is written up at the
end of `UPSTREAM_DIVERGENCE.md`.

**2026-08-02 — Transfer approval was gating nothing.** Branch
`fuime/front-on-approval`. No production admin had a
`Governance::Admin::Transfer::Limit` (bd10e06c1 only fixed new rake-made
admins), so nobody could approve a disbursement; set rushilchopra@gmail.com to
$10,000/24h via a Render one-off job. Then found the gate was decorative:
`DisbursementService::Create` fronted the incoming side **at creation**, so
`HCB-500-2` ($1,230,004, still `reviewing`) had already made $1,229,914
spendable. Now fronts only on approval. Two new specs; 35 examples green in
`spec/services/disbursement_service/`. **Run rake on the deployed app with
`render jobs create srv-d9n2tm6417fc73ci8hl0 --start-command "..."`** — SSH keys
aren't registered, and the Postgres `ipAllowList` is empty so psql can't reach
it either.

**2026-08-02 — Playground org with money.** Playground Mode was already here:
it is upstream's `Event#demo_mode`, per-org, and it blocks money movement while
leaving the ledger fully readable. Added
`bundle exec rails runner script/seed_playground_org.rb` — creates
`/fuime-playground` (demo_mode on, same demo teen + guardian as
`seed_demo_business.rb`) and funds it with 8 fabricated ledger lines through the
seeds' own import path. $417.88 on the ledger, $373.46 available. Idempotent.
No app code changed, so rspec was not re-run. Note `RawCsvTransactionService`'s
`amount:` is **dollars, not cents** — `db/seeds.rb` gets this wrong.

**2026-08-02 — Security keys, third attempt.** Two bugs, both hidden from the
suite. (1) `webauthn-ruby` only infers the RP ID when *exactly one* origin is
allowed; we listed two, so the RP ID was `nil` and every registration and
sign-in raised `WebAuthn::RpIdVerificationError` in production. `config.rp_id` is
now explicit. (2) The `use_two_factor_authentication` toggle lived inside the SMS
card, which is hidden without Twilio — so the "admins must enable 2FA" banner
pointed at a page with no way to enable it. It's now its own card, gated on
`User#second_factor_available?`. 157 auth-related examples green (this includes
fixing three stale `logins_controller_spec` assertions that still said "HCB").
**Any key registered on the deployed app before this must be re-registered** —
the RP ID is baked into a credential. Untested against physical hardware.

**2026-08-02 — Milestone 3 close-out.** Branch `fuime/m3-finish-brand-sweep`.
Finished the brand sweep and wrote the missing `docs/fuime/BRAND_STRINGS.md`
(read that before touching any `HCB`/`Hack Club` string — it classifies which
are branding, which are ledger data, and which are legally required to stay).
Disabled four surfaces that made claims Fuime cannot make — the fiscal
sponsorship and verification letters (PDFs on Hack Club letterhead with a real
employee's signature and EIN, one attesting an FDIC banking relationship), the
termination agreement, and the Perks page — and closed three "trap pages"
(Cards, Donations, Google Workspace) that showed a nav item, rendered fully,
then bounced the only action on them. Also killed a credentialed cross-origin
`fetch` to `blog.hcb.hackclub.com` that ran on every authenticated page load,
and fixed the admin header logo rendering full-size over the page.
**Verified against a `cafd73bba` baseline with assets built on both sides:
zero new failures in all three scopes.** Two measurement traps are documented
at the end of that UPSTREAM_DIVERGENCE entry — read them before trusting a
spec run; one of them makes an early-terminated run look green.

**2026-08-02 — Approval crash fixed; money-in wired up.** Branch
`fuime/m3-finish-brand-sweep`. Approving a teen-led application 500'd on a nil
contract (no DocuSeal template configured) — guarded, with a regression spec
proven to catch it. The storefront Pay button was hardcoded `disabled` and
nothing called `PaymentLinkService`; added `Fuime::CheckoutsController` +
`POST /b/:slug/pay`. The 4% fee now posts as a visible ledger line and rebates
proportionally on refunds/chargebacks (it previously lived only in Stripe
metadata, so a refund would have left a teen net negative by the fee).
**Gotcha that cost time:** several rspec containers can pile up against the one
`bank_test` database and deadlock each other — `docker ps`, stop the strays, then
`SELECT pg_terminate_backend(...)` before `rails db:schema:load`. Also note
`db:test:prepare` can exit 0 having left the schema unloaded; `db:schema:load`
is the reliable call.
Also fixed the other half of that outage: approved applications never became
businesses. `activate_event!` raised on a nil contract *inside* `with_lock`, so
`Event.create!` rolled back with it; `tags:` blew up on `params[:tags]` being nil
(a Ruby default does not apply to an explicit nil — this failed on ANY activation
with no tags selected, contract or not); and the only Activate button in the app
lived on the contract-party page, which does not exist without a contract.
**Next:** click the payment through against live test-mode Stripe
(`STRIPE__TEST__*` + `stripe listen`) — that is the one part not yet executed.
**Also note:** the dashboard card bug reported this session was reproduced on the
deployed Render app, which lags this branch. Check what is deployed before
debugging a symptom you cannot reproduce locally.

**2026-08-01 — Production hardening pass.** Branch `fuime/production-hardening`.
Closed every *engineering* blocker from `PRODUCTION_READINESS.md`: guardianship is
now an enforced control rather than a redirect, the webhook no longer double-posts
or fronts unsettled money, tax math uses net earnings, receipts go to S3, and
money-out modules are blocked at the request level. Added 68 specs (there were
zero). Remaining blockers are legal — identity verification, money transmission
structure, CPA review — and gate launch regardless of code.
**Before this branch helps anyone:** set the `S3__*` vars in Render and re-sync
the Blueprint, or the app will refuse to boot (by design). Then `rails db:migrate`.

---

## Running the app locally

The host toolchain on this machine does **not** work directly: Homebrew ships
Ruby 4.0.6 while the app pins 3.4.9, and no version manager (rbenv/mise/asdf) is
installed. `bundle install` exits 0 but installs nothing, so `bundle exec rspec`
fails with "command not found: rspec". Use Docker.

```bash
# One-time
cp .env.development.example .env.development   # then fill in the blanks
docker build -f Dockerfile -t fuime-dev .      # ~10 min first time

# Services
docker compose up -d db redis

# Database (first run, or after pulling new migrations)
docker compose run --rm -e RAILS_ENV=test -e DATABASE_URL=postgres://postgres:postgres@db:5432 \
  web bundle exec rails db:test:prepare
docker compose run --rm -e RAILS_ENV=test -e DATABASE_URL=postgres://postgres:postgres@db:5432 \
  web bundle exec rails db:migrate
```

### Running specs

```bash
docker compose run --rm -e RAILS_ENV=test -e DATABASE_URL=postgres://postgres:postgres@db:5432 \
  web bundle exec rspec spec/models/guardianship_spec.rb
```

The full suite takes a long time. Run the Fuime-specific specs first:

```bash
... web bundle exec rspec \
  spec/models/guardianship_spec.rb \
  spec/models/user_guardianship_spec.rb \
  spec/services/fuime/ \
  spec/controllers/fuime/
```

## Gotchas hit

- **Build BOTH the JS bundle and the CSS before running controller or request
  specs.** They render real views, and `app/views/layouts/_head.html.erb` calls
  both `javascript_include_tag "bundle"` and `stylesheet_link_tag
  "application"`. In a fresh container these produce two different errors and
  ~115 failures that look exactly like a mass regression:

  - no JS → `ActionView::Template::Error: The asset "bundle.js" is not present
    in the asset pipeline`
  - no CSS → `LoadError: cannot load such file -- sassc`

  The `sassc` error is misleading. `sassc` is not in the Gemfile and is not
  meant to be: CSS is built by postcss (`yarn build:css`). Sprockets only
  reaches for its sassc processor because the prebuilt `application.css` is
  missing, so the fix is to build the CSS, not to add the gem.

  ```bash
  docker compose run --rm -e RAILS_ENV=test \
    -e DATABASE_URL=postgres://postgres:postgres@db:5432 \
    web bash -c 'yarn install && yarn build && yarn build:css'   # ~5 min
  ```

  Both write to `app/assets/builds/` (`bundle.js`, `application.css`,
  `admin.css`, `mailer.css`), not `public/`. CI runs these as part of setup,
  so neither failure shows up there.

- **`DATABASE_URL` must be passed explicitly** to `docker compose run`. The
  compose file only sets `REDIS_URL`; without the override, Rails looks for a
  local socket and fails.
- **`db:test:prepare` does not run pending migrations.** It loads the schema,
  so newly added migrations still report `PendingMigrationError`. Run
  `db:migrate` after it.
- **`strong_migrations` blocks `add_reference ... foreign_key:`** in one step.
  Split into three migrations: add the column with
  `index: {algorithm: :concurrently}` and `disable_ddl_transaction!`, then
  `add_foreign_key ... validate: false`, then `validate_foreign_key`.
  See `20260801170000`–`170002`.
- **The user factory now sets a birthday** (adults by default). Fuime treats
  unknown age as a minor requiring a guardian, so a birthday-less factory user
  is barred from operating a business — correct in production, but it silently
  turns unrelated specs into tests of the guardianship gate. Use the `:minor`,
  `:minor_with_guardian`, and `:unknown_age` traits to test that gate on purpose.
- **Request specs don't have `create_session`.** `SessionSupport` uses
  `cookies.encrypted`, which needs `type: :controller` plus an explicit
  `include SessionSupport`. `spec/controllers/fuime/` follows this pattern.
- **The boot-time safety check raises in production/staging** on ephemeral
  Active Storage, a half-configured live Stripe key, or a hackclub.com host.
  That is intentional. `FUIME_SKIP_SAFETY_CHECK=true` bypasses it for one-off
  recovery work only — never for serving traffic.

## Seeded / real accounts

Production currently has three real user accounts plus `bank@hackclub.com`
(`User::SYSTEM_USER_ID` — required by the app, not a seed account) and 12 HCB
system orgs referenced by hardcoded id in `EventMappingEngine::EventIds`.
Do not delete either; see the "Production Data Reset" section of
`UPSTREAM_DIVERGENCE.md` for why and for the FK ordering that reset required.
