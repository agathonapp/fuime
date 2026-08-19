# Fuime — Setup Notes

## Handoff (most recent first)

**2026-08-19 (later) — CI green: the 16 pre-existing RSpec failures.**
The hardening PR re-sharded the suite so every shard carried a failure
that already existed on `main`. Specs were stale against current Fuime
rules (Free + School plans, livemode from StripeService, guardian name
not email). WebAuthn needed the same `TEST_URL_HOST` fallback as
`config/environments/test.rb` so FakeClient works without secrets.
Do not re-inject GitHub secrets. Affected examples: 135, 0 failures locally.

**2026-08-19 — Defensive hardening (production logs, Twilio webhook, CI).**
Three fixes on `cursor/defensive-hardening-796c`. Production log default is `info`
(`RAILS_LOG_LEVEL` still overrides). Twilio webhooks 403 without a valid
`X-Twilio-Signature` / `TWILIO__AUTH_TOKEN`; media download allowlists Twilio
hosts and will not follow a redirect off that list. CI RSpec no longer injects
`${{ secrets }}` and no longer `eval`s a constructed command. Focused specs:
`spec/requests/twilio_webhook_spec.rb`, `spec/jobs/twilio/process_webhook_job_spec.rb`.
**2026-08-18 — The branch is on GitHub as PR #70. Nothing of Friday's work was deployed.**

The state that mattered most and was not visible from any doc: **five unpushed commits and 28
uncommitted files** sat on this laptop while `fuime-web` auto-deploys from `main`. Among them was
the one-line `Event#accepts_payments?` fix — so **app.fuime.com could not let a single
merchant-of-record venture sell**, and no amount of live-mode configuration would have changed
that. Now committed (`b435ba4e2`, `c25351286`), pushed, and open as **PR #70**. Not merged: a
merge auto-deploys, and that is a decision to take deliberately.

**First full-repository suite run in this repo's history: 3357 examples, 8 failures, 17 pending.**
All 8 are the documented baseline in `known-failures.md` (Apple-Silicon `wkhtmltopdf` ×4, the
`School` plan-lineup contradiction ×2, `stripe_connected_account` livemode, guardianships index).
The branch adds ~460 examples and introduces **zero** new failures. Previous sessions reported
1267/1327 green across *subsets*; this is the whole thing.

**`business_category` was a dead end, not the trap the last handoff called it.** The last entry
noted a blank category blocks selling. Checking how anyone recovers found the real defect: nobody
can. The column was required by nothing (`allow_blank: true` both sides, absent from
`required_submission_fields`, derived only from `service_type`) **and writable nowhere** — outside
`activate_event!` it appears in no form, no strong-params list, no admin screen. A founder who did
everything right reached "Choose what this venture sells" with nowhere to choose it. Both halves
fixed; see UPSTREAM_DIVERGENCE 2026-08-18.

**Scope decided by the founder today:** payouts ship the week of Aug 24, not Friday — the 7-day
hold plus 10% reserve means nobody is payable before ~Aug 28 anyway, and `mark_paid!` is already a
human assertion, so the open originator decision (§4.3) is **not** on the launch critical path.
Identity/KYC moves to payout-request time, which is also when the W-9/1099-NEC obligation attaches.

**Operator age floor for Friday is 13** (`FUIME_MINIMUM_OPERATOR_AGE=13`, set in
`.env.development`; **still to set on Render**). A 7–12 tier was asked for and is not a config
change: under MoR Stripe's 13-floor no longer binds (the operator holds no Stripe account — that
obstacle is genuinely gone), but COPPA and child-labor both remain, and both point at the same
structure — **parent as the operator and vendor, child as a named participant holding no account
and signing nothing**. That is LEGAL_RESEARCH's "parent is the merchant", P3 item 7. An
auto-linked parent email is **not** verifiable parental consent (16 CFR 312.5(b)), and a public
storefront naming a child is exactly the disclosure case email-plus cannot cover.

**Three things stand between this branch and real money, and none of them are code:**
(1) Stripe live account approved, in Fuime LLC's name, with the MoR structure described
accurately — under-describing it to get approved is worse than a rejection, because it gets
revoked mid-event. (2) `FUIME_MOR_COUNSEL_MEMO`, unchanged and still the top item.
(3) **Register the live webhook endpoint** and put *its* signing secret in
`FUIME_STRIPE_WEBHOOK_SECRET` — live endpoints have their own, nothing in code checks it, and
without it every sale succeeds on the card and is invisible in the ledger.

**Still true and still worth saying: nobody has driven this in a browser end to end.** Everything
is asserted at the request and model layer. A click-through on app.fuime.com from signup to a
completed payment has not happened.


**2026-08-16 (late) — Cohorts: one person vouches for a group, and the roster board.**

Founders Weekend needed ~50 teens through signup → first sale in one sitting, past three human
gates (approve, activate, vet). **150 clicks during a live event is not a control** — it is a
queue somebody clears without reading, which produces a signed record of a judgement nobody made.

`Fuime::Cohort` moves that decision rather than removing it: one person decides once, in advance,
and `rationale` is NOT NULL because they must write down why they can. That sentence is copied
verbatim into every vetting note, next to their name. The note states what happened and nothing
else — a spec asserts it never says "looks legitimate" or "low risk".

**A code cannot exempt anybody from anything.** An admitted 14-year-old is vetting-approved and
still cannot sell; an admitted crafts venture likewise; an admitted founder with no parent is
still refused at payout. All three asserted, because that is where this feature would go wrong.
`expires_at` and `max_members` are required (a code with neither is a permanent bypass for whoever
pastes it into a Discord), and the cap is enforced **under a row lock** — fifty people submitting
at once is the ordinary case here.

**Founders type the code on the review page**, not via URL: the sign-in round trip loses a query
param, which would drop somebody into the ordinary queue with nothing explaining why their friend
got in. A bad code never blocks submitting.

**`/admin/cohorts/:id` is the roster board — the screen to watch on the day.** It answers "who is
stuck and on what?" for everybody at once, which neither existing queue does.
`Fuime::FounderProgress` names ONE next action rather than a state, and reports rather than
decides — every answer reads from `accepts_payments?` / `selling_blockers` / `has_active_guardian?`
so it can never tell a teenager they can sell when the real gate disagrees. Parents are counted
apart from the funnel on purpose: under MoR a missing guardian blocks being paid, not selling.

**Set up Friday's cohort at `/admin/cohorts`.** Exercised end to end in the dev app: an application
carrying `FW2026` came out as an activated, vetted venture, `accepts_payments? == true`, roster
reading "Publish something to sell".

⚠️ **An application that skipped the business-type step produces a venture with a blank
`business_category`, which fails eligibility closed and blocks selling before any other check.** A
cohort admits them happily and they still cannot sell. The roster's next-action column is what
surfaces it.

**Verification:** 1327 examples green. Full repo suite still not run.


**2026-08-16 (evening) — Merchant-of-record could not sell at all. It can now, and a
teenager's own software can sell for them.**

Driven by Founders Weekend: ~50 teens onboarding Friday 2026-08-21, signup → application →
first sale in one sitting, with real revenue (~$1k each over three days).

**The bug worth knowing about even if you read nothing else.** `Event#accepts_payments?` opened
with `return false unless payment_account&.ready_for_payments?`. Under MoR there IS no per-venture
merchant account — that is the whole model — and PR #68 correctly hid the screen to open one. So
every MoR venture was permanently unable to publish an offer, take a checkout, or appear in the
directory, while `PaymentLinkService#create_mor_checkout_session` underneath would have worked
fine. **Verified against Stripe test mode**: zero selling blockers, a real Checkout Session from
the service, `false` from the method. One line, total effect, invisible from either side alone.

**The guardian moved rather than went away.** A minor can now sell with no parent attached —
under MoR they hold no account and sign nothing, so there is no obligation for an adult to stand
behind yet. Removed from `OperatorEligibility`, `activate_event!` and
`User#permitted_to_operate_business?`; added to `PayableAssessment#compute_structural_skip_reason`
(batch path) and `EventPolicy#request_payout?` (request path). **All MoR-only — Connect is
untouched.**

`#request_payout?` is the one that is not obvious and is not redundant. Without it a parentless
teen files a request, `#decide_payout?` needs a guardian so nobody but an admin can action it, and
`one_pending_request_per_venture` then blocks them forever. One click, permanently wedged.
`spec/models/fuime/selling_without_a_guardian_spec.rb` asserts the whole property end to end —
it exists because the change spans five objects and no single object's spec can see it.

**The cost, on the record:** no adult obligor behind a chargeback during the selling window
(MOR_MIGRATION_PLAN §7 Q3, still open). Bounded by hold + reserve and by money being unable to
leave before a guardian arrives.

**`FUIME_MINIMUM_OPERATOR_AGE`** — the 16 floor is now a dial, default 16, **hard-clamped at 13**
(COPPA/L6; a lower value clamps up rather than being honoured, an unparseable one falls back to
16). Set it to `13` or `14` for a cohort with younger founders. It only binds under MoR.

**New: `/api/fuime/v1`** — `Fuime::ApiKey` (`fuime_sk_…`, Lockbox + blind index, plaintext shown
exactly once), `GET /me`, and `payment_links` index/create/destroy. Operators mint keys at
`/:event_slug/developer`. A pay link is an **unlisted published `Fuime::Offer`** — `published`
now means payable, `listed` means in the shop window. **No route carries an event id**, so a
leaked key cannot express a request against another business. **Exercised end to end**: POST →
hosted payment page at the right price → real `cs_test_…` Checkout Session.

**A Stripe webhook has now run, and it needed no `stripe login`.** A real test-mode PaymentIntent
was confirmed with `pm_card_visa`, the `payment_intent.succeeded` event was pulled from **Stripe's
own Events API**, and that payload — correctly signed — reached the ledger through the real HTTP
endpoint: **+$45.00, −$2.25 fee, one row after replay.** It is now a fixture
(`spec/fixtures/fuime/payment_intent_succeeded.json`) driven by
`spec/requests/fuime_stripe_webhook_endpoint_spec.rb`, which also proves a forged signature, a
tampered body, a wrong secret and a stale timestamp are all refused — and that a missing secret
returns 503 rather than accepting anything.

⚠️ **`FUIME_STRIPE_WEBHOOK_SECRET` is empty in `.env.development`**, so locally this endpoint takes
the deliberate unsigned path for `stripe listen`. Any local "the webhook works" result proves
nothing about production until you set it. This briefly looked like a signature bypass; it is not.

**Before Friday, three things that are not code.** (1) `FUIME_MOR_COUNSEL_MEMO` must be set or the
app refuses to boot with MoR on — deliberate, untouched, and yours to answer. (2) `STRIPE_MODE`
is `test` on both Render services and there are no live credentials anywhere; live is a
credentials + env change, not a deploy of this branch. (3) **Register the webhook endpoint in
Stripe** — `payment_intent.succeeded`, `charge.refunded`, `charge.dispute.created` pointed at
`https://app.fuime.com/fuime/webhooks/stripe`. Nothing in code checks that this is done, and
without it every sale is invisible in the ledger.

**Still unexercised: the Connect webhook endpoint** and `Fuime::ConnectPaymentRecorder` behind it.
Not the MoR money-in path, so not on Friday's critical path — but "no webhook has ever run" is now
false only for the platform endpoint.

**Verification:** 1267 examples green across `spec/models/fuime`, `spec/services/fuime`,
`spec/controllers/fuime`, `spec/requests`, `spec/policies`, `spec/views/fuime`, `spec/helpers` and
the guardianship/vetting/school specs. **The full repository suite has not been run.**


**2026-08-16 (later) — Plaid Link works, and it is the first integration this repo has
actually run against its provider.**

`Fuime::PayoutMethod` shipped this morning as a model with no way to create a row. It now has
one: `Fuime::PlaidLinkService`, an operator page at **`/:event_slug/payout-method`**, and a
"Payout account" nav item that appears under merchant-of-record exactly where "Payments"
disappears. Sandbox Plaid keys are in `.env.development`.

**🔑 It was exercised end to end against Plaid's real sandbox** — link token, public token
exchange, `/accounts/get`, `/identity/get`, persistence, encryption-at-rest, and the
replace-the-old-destination path, through the service itself rather than raw HTTP. Every prior
handoff has had to say "nothing has run against the provider". This one does not. Two guards
fired on real data rather than a stub: an account id from a **different Plaid Item** was refused
(sandbox mints fresh ids per Item, so that case happened by accident), and an Item with both
checking and savings and no account named was **refused rather than guessed at**.

**⚠️ The trap that cost the most time, and it invalidates spec runs silently.**
`docker-compose.yml` gives the `web` service `env_file: .env.development`, and specs run through
that service — so **everything in `.env.development` is in the test container whatever
`RAILS_ENV` says.** Adding `FEATURE_MERCHANT_OF_RECORD=true` there (the obvious way to see the
new page in a browser) ran the entire suite in the umbrella model, as a *green* run that tested a
different application, with the `:merchant_of_record` tag silently reduced to a no-op.

`spec/support/structural_flags.rb` now clears every structural flag per example unless the
owning tag is present. **It has to be `before(:each)`, not `before(:suite)`** — dotenv 3.1.7
loads `dotenv/autorestore`, which snapshots ENV once and restores it after *every example*, so a
suite-level deletion holds for exactly one example and is then undone. That presents as one
inexplicable failure in a file that passes under `-e`. Anything wanting ENV to hold across this
suite must re-assert it per example.

**Two design points worth carrying.** (1) **Plaid verifies; it never moves money** — unchanged
from §4.3. This buys a verified destination, not a payment, and `mark_paid!` is still a human
assertion until an originator is chosen. (2) **`/auth/get` is never called and must not be.**
The `auth` product is requested at Link time only so the Item is *capable* of being handed to an
originator later; a spec stubs `auth_get` to raise so a future refactor that reaches for the
digits fails the suite. `provider_reference` holds the Plaid `item_id`; the access token lives in
a Lockbox `_ciphertext` column and a spec reads the raw column to prove the plaintext is not there.

**Also worth knowing: the plaid gem keeps nested request attributes as bare Hashes.**
`LinkTokenCreateRequest.new(user: {…})` serializes fine but `request.user.client_user_id` raises,
so a misspelled filter key would sail through to Plaid ignored — and the first sign would be an
operator connecting a credit card the UI meant to hide. Use the typed classes. And
`/item/create_public_token` is discontinued (API 2020-09-14), so to drive the flow headlessly use
a sandbox **custom user** (`override_username: "user_custom"`, config JSON as `override_password`).

**Two specs were already red on this branch and nobody knew.** `fuime_full_business_flow_spec`
and `fuime_payout_batches_admin_spec` both generate a payout run for a venture with no payout
destination, which `20fee1cd5` had just taught `PayableAssessment` to skip. That commit verified
"505 examples across the touched suites" — and these two exercise the same gate from further
away. **A change to a gate has a blast radius wider than the files it edits; run the full suite
for those even when the targeted specs are green.** Both now set up a verified destination, which
is what a real MoR venture has; the gate was not weakened.

**A schema.rb false alarm, so nobody re-debugs it.** Regenerating `db/schema.rb` on this
machine's Postgres rewrites seven existing check constraints from
`ARRAY['a'::character varying]::text[]` to `ARRAY['a'::character varying::text]` — semantically
identical, purely how `pg_get_constraintdef` renders across server versions. It is not a missing
migration. It was reverted out of this diff so the schema change stays exactly the two new
columns; expect it to reappear and revert it again rather than committing it.

**⚠️ A second session was editing this checkout at the same time** — API keys
(`Fuime::ApiKey`, `/:event_slug/developer`), offer listings, and the guardian gate moving from
`Fuime::OperatorEligibility` into `Fuime::PayableAssessment`, with migrations `20260817000000`
and `20260817000100` landing after this one. That is the house failure mode CLAUDE.md warns
about, and it has two consequences here: the full-suite number below measured the **combined**
working tree rather than the Plaid work alone, and `db/schema.rb` was regenerated at
`20260816230000`, so it does not yet describe those two later migrations. Re-run `db:migrate`
and check the schema version before committing either half.

**Still not done and still the biggest gap: no Stripe webhook has ever run.** Plaid does not
change that. `stripe login` against the Fuime account first — the CLI is on `acct_1Tmdhs…` while
the app key is `acct_1Tzna…`.

**Next:** an originator for §4.3 (Slash / Mercury / Stripe) is what turns a verified destination
into a payment, and it is still an open decision. Engineering is still not the critical path —
`FUIME_MOR_COUNSEL_MEMO` is.


**2026-08-16 — PR #68 merged and deployed; payout methods started; MoR has one gate left.**

**Read `docs/fuime/PLATFORM_REVIEW.md` first** — it is the honest audit of what Fuime is and
is not, written today, and it names the one gap that can lose money (disputes and clawback,
§8.5 phase 7 — still unbuilt).

**What landed on main (`5d763097c`, PR #68):** MoR phase 6 payout runs · the business-type
onboarding step · `Fuime::Offer` and the storefront that stops being a tip jar ·
`/pay/business/thing` payment links · the substrate decision (stay on Stripe, `WHOP_EVALUATION.md`
§11) · a ledger memo-injection fix. **`fuime-web` autoDeploys from main**, so this is live at
app.fuime.com. Both Stripe webhook secrets are set.

**Uncommitted-to-main work sits on `fuime/vetting-from-application`** — four commits: vetting
reads the application, LLC recorded, `Fuime::PayoutMethod`, and the batch/nav wiring. Not yet a
PR.

**🔑 The single most important state change: Fuime LLC exists.** That clears one of the two
merchant-of-record gates. The other is unchanged and is now the ONLY thing between here and
flipping `FEATURE_MERCHANT_OF_RECORD`: `FUIME_MOR_COUNSEL_MEMO` must cite a memo answering
§7 Q1, Q2 and Q4. Adding code does not move it. That counsel conversation is the highest-leverage
item on the list.

**Next task, already shaped:** the Plaid Link flow and the operator page for
`Fuime::PayoutMethod`. The model, its no-credentials-stored guarantees, the batch gate and the
nav swap are done and tested; what is missing is `Fuime::PlaidLinkService` (create link token →
exchange public token → write `provider_reference` → `mark_verified!`) plus the page. **It needs
`PLAID_CLIENT_ID` and `PLAID_SECRET` in the environment** — sandbox is fine, and without them the
integration cannot be run even once, which this session twice showed is not good enough.

**Two traps this session paid for, both worth carrying:**

1. **`bin/lint` is not safe without a full suite after it.** `rubocop -a` took the suite from 8
   failures to 26: `Rails/HttpPositionalArguments` saw a spec's local `post(...)` ledger helper,
   assumed it was an HTTP request, and rewrote every call into a request spec that tested
   nothing — while satisfying the linter. Rename such helpers (`post_line`) rather than trusting
   the autocorrect.
2. **AASM is not whiny by default.** A transition whose save fails validation reverts the state
   and returns `false` rather than raising. Check the return value or you will tell a user
   something happened that did not.

**Verification at handoff: 3189 examples, 8 failures** on main — the standing eight in
`known-failures.md`. CI's RSpec shards are red on main for the same reason and were before this
work; all twelve non-RSpec checks pass.

**Still never done, and now the biggest gap: no webhook has ever run against Stripe.** The
secrets are set, so a test-mode payment landing on a ledger is finally testable and is the one
thing that proves the money path. `stripe login` against the Fuime account first — the CLI is on
`acct_1Tmdhs…` ("Hack Club Shop testing") while the app key is `acct_1Tzna…`.


**2026-08-15 — Phase 7a: the business-type step, and the venture-born-blocked bug it fixes.**

New `business_type` step between the intro screen and `project_info`, plus
`Fuime::ServiceCatalog` — ten services, each with a checklist, and Whop's three-card fork with
its third card changed from "clone a proven business" to "start from a template".

**The bug is older than the UI and worth knowing about: nothing ever set
`Event#business_category` from an application.** `activate_event!` did not carry it, so every
venture the funnel produced started blank — and `OperatorEligibility::ELIGIBLE_CATEGORIES` is
`%w[services]`, which a blank does not satisfy. Ventures were created already unable to sell
and the vetting queue was where anybody found out.

**Two constraints in the catalog are asserted, not commented, because both are under constant
pressure to "just be helpful".** No template may suggest a price (§8.3 D2 — a suggested rate is
a set rate with a softer verb) and the checklists must positively say the rate is the
operator's. And babysitting, childcare and coaching children are deliberately absent: under MoR
Fuime is the legal seller, and for childcare the foreseeable failure is injury to a child. That
is a launch-scope judgement for the §7 Q1 counsel conversation, not a permanent rule.

**Two bugs found on the way.** `Event::ApplicationsController#update` raised
`DoubleRenderError` on any non-autosave update with no `return_to` — `redirect_back_or_to` does
not end the action and it fell through to `head :no_content`. And validating `service_type`
inclusion on every save would have bricked every existing application the day a catalog key was
retired; it is now `if: :service_type_changed?`.

**Whop as the whole substrate is open, not chosen** — see MOR_MIGRATION_PLAN §9. Better rails,
same L5 vocabulary. Blocking unknown is Q9 (guardian as verified principal), which should be
asked in the same conversation already owed to Stripe.


**2026-08-15 — Phase 6: the weekly payout run exists, and it deliberately cannot send money.**

`Fuime::PayoutBatchService` generates a run every Wednesday for a Friday payout, an admin reads
every line at **/admin/payout_batches**, and `mark_paid!` is the only thing that debits an
operator's ledger. Approving posts nothing — the page's copy says so and a spec asserts it.

**The thing to hold onto: a run's terminal step is a human assertion, not a transfer.** The
originator is still an open decision (MOR_MIGRATION_PLAN §4.3 — Mercury's ToS on programmatic
ACH to hundreds of third parties, Slash as the API-native alternative, Plaid behind either).
When it lands it becomes a `LegalEntity::PayoutMethod::BankAccount` behind the same transition
and nothing in phase 6 changes.

**Four new env dials, all defaulted and all frozen onto each batch row at generation:**
`FUIME_PAYOUT_HOLD_DAYS` 7 · `FUIME_PAYOUT_RESERVE_BASIS_POINTS` 1000 ·
`FUIME_PAYOUT_RESERVE_WINDOW_DAYS` 90 · `FUIME_PAYOUT_MAXIMUM_CENTS` 250000 ·
`FUIME_PAYOUT_MINIMUM_CENTS` 1000. Frozen rather than read live because a run that floats with
the configuration is a run nobody can explain to an operator afterwards. **The numbers are the
founder's call** — they answer §8.4 item 1 defensibly, not finally. A steady $100/week operator
ends up with a standing $130 reserve (~1.3 weeks of earnings) and is then paid in full weekly.

**Two traps worth carrying forward.** `Fuime::VentureLedger#post!` writes a PENDING line that
something must later promote, and `ConnectSettlementSweep` only promotes payment- and
refund-shaped keys — so any new Fuime money path that has no Stripe settlement event must use
`post_settled!` or its debit sits in `committed_cents` forever. And `PayoutRequest#reject`
cannot leave `approved` by design (on the Connect paths approval IS the money moving), so
cancelling a batch line needed a separate `cancel_from_run` event guarded on `scheduled?`.

**Verification: 3091 examples, 8 failures — the eight pre-existing ones and nothing else.** One
seed; see `known-failures.md` for why that is recorded as weaker evidence than the phase-3 run.


**2026-08-14 — Phase 3: vetting is live in every model, and the launch scope is a gate.**
Read `docs/fuime/MOR_MIGRATION_PLAN.md` **§8** first — it is new, it supersedes §5's
sequencing, and it records what the revised brief settles versus what it only assumes.

**The single most important thing in this handoff: `Event#accepts_payments?` now returns
false for any venture nobody has approved.** The column defaults to `unvetted`, so *every
existing venture is blocked from selling until an admin approves it* at **/admin/operator_vetting**.
That is intended — manual approval is the control the whole model rests on — but it means a
production deploy needs someone to work that queue before anyone can sell. The nav item shows
the outstanding count. There is no bulk-approve and deliberately so; if you want one for
existing ventures, write it as a one-off task with a recorded reason, not as a migration.

The spec factory defaults ventures to **approved** (`:unvetted` / `:rejected` / `:suspended`
traits exist), for the same reason users default to adults — otherwise every storefront,
checkout and payout spec silently becomes a test of this gate.

**Two flags now, and they are near-opposites.** `FEATURE_SPONSOR_BANKING` = "Fuime holds YOUR
money" (needs a named partner bank to boot). `FEATURE_MERCHANT_OF_RECORD` = "the money is
Fuime's own and we owe you a payable" (needs `FUIME_MOR_COUNSEL_MEMO` to boot). Neither implies
the other. Both default off, and with MoR off the app still runs the **guardian-owned Stripe
Connect model exactly as before** — the pivot is additive, not a replacement.

**What binds when.** Vetting binds always. Services-only, the 16+ operator floor and
per-operator guardianship bind *only* under MoR, because they bound liability Fuime carries as
seller of record — under Connect that risk sits with the family, and enforcing them anyway
would block school ventures that `Event#institutionally_sponsored?` already covers. Tag a spec
`:merchant_of_record` to exercise that half (sibling of `:sponsor_banking`).

**Never render `Event#selling_blockers` on a public page.** Those strings name operators and
state their ages. `app/views/fuime/_selling_blockers.html.erb` is the authenticated-only
partial; `spec/controllers/fuime/storefront_blocker_privacy_spec.rb` asserts none of them
appear verbatim on the storefront, so the guarantee survives rewording.

**Two bugs the new specs caught, both invisible to a status-code test:** the admin queue's
`group(...).count` raised `PG::GroupingError` because `Event`'s `default_scope` orders by id
(`unscope(:order)`), and the three decision buttons were `form.submit`, whose label *is* its
value — they posted `status=Approve`. Use `form.button` when several buttons share a param.

**The Stripe pass is half done, and the second half has a specific blocker.** Test keys *are*
present — they resolve through `Credentials.fetch(:STRIPE, mode, :SECRET_KEY)`, i.e.
`STRIPE__TEST__SECRET_KEY`, **not** the flat `STRIPE_SECRET_KEY` you might grep for. Money-in
is verified against real Stripe: the direct-charge shape is accepted and
`application_fee_amount` stores correctly. Webhooks, onboarding, embedded components and
ledger posting are all still untested — see `EMBEDDED_CONNECT.md` §7 for exactly what was and
was not run.

**Before continuing: `stripe login` against the Fuime account.** The CLI is authenticated to
`acct_1TmdhsGRzfgn1FN5` ("Hack Club Shop testing") while the app key is
`acct_1TznaN2Uz4P3wrXO`. `stripe listen` would forward events from an account this app knows
nothing about, and every handler would no-op while looking like it ran. Also
`FUIME_STRIPE_WEBHOOK_SECRET` is empty, and `StripeService.construct_webhook_event` skips
signature verification entirely when it is blank.

**Verification: 2969 examples, 8 failures — the 8 pre-existing ones and nothing else.** Three
full-suite runs at different seeds, because adding ~75 examples reshuffles RSpec's random order
and a single run cannot tell a regression from an order-dependent spec. Run A surfaced
`spec/initializers/flipper_groups_spec.rb:25`, which passes in isolation and passed at another
seed — order-dependent Flipper state, not the diff. Run B surfaced two real failures in a spec
written after A, both fixed. All three runs and the attribution are in `known-failures.md`.

---

**2026-08-13 — The merchant-of-record pivot starts; custody is now a flag.** Read
`docs/fuime/MOR_MIGRATION_PLAN.md` first — it is the plan of record for this work and its §0
explains why the brief that started it was aimed at a codebase that no longer exists. Phases 1
and 2 are done on `fuime/mor-pivot-phase1`; phases 3–7 are blocked on the four questions in
its §7, two of which are for counsel and one for Stripe.

**⏪ There is a restore point.** The complete working tree from immediately before the pivot,
including the 20 uncommitted Connect files, is in the tag **`pre-mor-pivot`** (`859fc5018`).
`git checkout -b rescue pre-mor-pivot` recovers all of it. Do not delete that tag until the
pivot merges — MOR_MIGRATION_PLAN §0.2 explains why the Connect work may need to come back.

What landed: `Fuime::Features` (`app/lib/fuime/features.rb`) with `FEATURE_SPONSOR_BANKING`,
default off, ENV-only and deliberately **not** Flipper — a Flipper flag is a checkbox any
admin can tick, and the failure mode here is unlicensed money transmission rather than a bad
rollout. `Fuime::DisabledModules` went from one hardcoded list to three, so the custody
modules (ACH, checks, wires, disbursements, Emburse) come back by configuration rather than
by editing a concern. Plus `Fuime::PayablesLedger`, which reframes `Event#balance_*` as "what
Fuime owes you, paid Friday" without touching the ledger engine.

**Two gotchas that will bite the next session.**

- **Fronting is off, and it breaks any spec that funds an event with `fronted: true`.**
  `Event#can_front_balance?` returns false while custody is off, *and* the column now defaults
  to false — so a spec needs BOTH the `:sponsor_banking` tag and an explicit
  `can_front_balance: true` to spend fronted money. Three upstream spec files already needed
  this (see `known-failures.md`). If you see `inadequate_balance` where you expected something
  specific, this is why.
- **Cards are now blocked in LIVE mode, not test.** `Fuime::Features.card_issuing_permitted?`
  keeps test-mode Issuing demonstrable and refuses it against live keys — finally implementing
  a promise the 2026-08-02 card note made in a comment and nothing enforced. Blocked at the
  controller *and* at `StripeCard#balance_available`, because blocking controllers alone would
  leave an already-issued card authorising swipes.

**Verification: the first full-suite baseline exists.** 2896 examples, 8 failures, all
pre-existing and attributed in `known-failures.md`. ~14 minutes; local `bundle exec rspec`
still does not work (Ruby 4.0.6 vs the Gemfile's 3.4.9) so it must run in Docker — the exact
command is further down this file.

**Phase 2 is now finished.** Operator-facing pages read `Fuime::PayablesLedger`
("Owed to you", never "Account balance"), and `spec/views/fuime/payables_copy_spec.rb` keeps
them there by reading template source for forbidden nouns and forbidden method calls.

**A live money bug fell out of it, and it is the most important thing in this handoff.**
`FeeEngine::Create` was charging Fuime's `revenue_fee` a SECOND time. Upstream that engine is
how HCB takes its cut, but under Connect the fee is already deducted by Stripe
(`application_fee_amount`) and posted as its own ledger line — so a $100 sale arrived as +$100
/ −$4 / −$3.20 and the hourly job accrued another $4. That is **8% charged for a 4% product**,
and it is exactly why the dashboard and the payouts page disagreed. Fixed by waiving the
accrual on any line carrying a Fuime ledger key. **If a real database ever accrues `Fee` rows,
audit `fee_balance` before launch** — nothing has run against production money, so there is
probably nothing to correct, but nobody has checked.

**Next task:** Phase 3+ are blocked on MOR_MIGRATION_PLAN §7. The one engineering decision now
open is the payout rail — see its **§4.3**, added after the Slash/Mercury/Plaid question. Short
version: MoR decouples money-in from money-out, so Connect is no longer needed for collection,
and a business-banking rail is legitimate *because* the balance is Fuime's own revenue rather
than customer funds. The cost of leaving Connect is 1099-NEC filing, which Connect does and
Slash/Mercury do not.

**2026-08-07 — The waitlist runs on Render only; Upstash is gone.** Storage moved
from Upstash REST to a Render Key Value instance, so the site now speaks the
Redis protocol (`ioredis`, `npm ci --omit=dev` at build) and Rails reads through
the `redis` gem. Key layout unchanged, so nothing had to be migrated. Set
`WAITLIST_REDIS_URL` explicitly on both services — **there is no fallback to
`REDIS_URL` on purpose**: falling back would let a forgotten variable look like
an empty waitlist rather than a missing one. Locally, put it on its own database
(`redis://localhost:6379/2`); the specs use DB 15 and flush it.

**Requires a Render dashboard action:** `fuime-redis` must go **free → starter
with journal-snapshot** (`render.yaml` says so, but a blueprint sync has to
apply it). Free Key Value has no persistence — it was also silently dropping
Sidekiq jobs on every restart. Watch the tripwire: `noeviction` means a Rails
cache big enough to fill the instance starts *rejecting* waitlist writes; split
the roster onto its own instance when cache memory becomes non-trivial.

`fuime-web` was already failing before any of this (deploy ~20:06 UTC Aug 6,
before both merges) — **still undiagnosed, needs the Render deploy log.** The
production Docker build reproduces locally through bundle and yarn install, so
it is more likely boot or the `/up` health check than the build. 27 Rails
examples + 35 site tests green; rubocop and erb_lint clean.

**2026-08-06 — The waitlist is readable, and the lost signups are recoverable.**
`/admin/waitlist`, reachable from both the Misc nav dropdown and the admin_tools
card desk: count against the 1,000 goal, 30-day daily bars, source breakdown,
roster, CSV. `Fuime::WaitlistRoster` reads the Upstash keys the marketing site
writes, read-only, and renders a notice rather than raising when unset. It lives
in Rails, not on the site, so access is the console's existing `signed_in_admin`
instead of a shared token to hand out.

`fuime-site` was in fact deployed Resend-only, so the first ~10–15 signups exist
only as mail in `rushil@fuime.com` and Upstash cannot backfill them. Recovery:
put one address per line (optionally `email,source,iso8601`) in a file, then
`rake fuime:waitlist:import[file]` — dry-run with `[file,dry]` first. It needs
`UPSTASH_REDIS_REST_WRITE_TOKEN` (everything else Fuime does with this list is
read-only); set it for the run and remove it after. Idempotent, so re-running is
safe and it never overwrites a real capture. **Still to do by hand:** set
`UPSTASH_REDIS_REST_URL`/`_TOKEN` on `fuime-site` or new signups keep vanishing,
and the same two (read-only) on `fuime-web`. 27 examples green, rubocop and
erb_lint clean; full suite not re-run.

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
