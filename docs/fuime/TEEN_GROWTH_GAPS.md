# Teen growth gaps — what to build to get more teens on Fuime

**2026-09-10.** Read-only audit of `main` @ `149185483` (`agathonapp/fuime`).
No product code was changed. This is a punch list for Rushmore, grounded in
the repo — not a launch-legal memo and not generic growth advice.

**Trust this for:** "what still blocks a teenager from signing up, activating,
selling, and coming back with a friend."

**Do not trust this for:** money-transmission counsel, Stripe underwriting, or
"first real dollar." Those remain `LAUNCH_SPEC.md` §0–§2 and
`LEGAL_RESEARCH.md`. Several of those items still block *live money*; they do
not, by themselves, explain why the next fifty teens never finish the funnel.

**Related docs, and where they lie:**

| Doc | Still true? | Drift |
|---|---|---|
| `LAUNCH_SPEC.md` §4.1 ("Pay button disabled, 4% never collected") | **Stale** | Checkouts exist; fee is plan-driven 7%/5% |
| `LAUNCH_SPEC.md` §1.4 / §6 (DOB mandatory, parked at guardian) | **Stale** | Onboarding is a 13+ checkbox; guardian is deferred |
| `LAUNCH_SPEC.md` §1.3 (`/privacy` → hackclub.com) | **Fixed** | `config/routes.rb` now serves `static_pages#privacy` |
| `ADMIN_OPS_QUEUES.md` ("deliberately unbuilt") | **Half stale** | §4 subscriptions **is** built; §1–§3 are not |
| `EMBEDDED_CONNECT.md` / `CLAUDE.md` (production = Connect) | **Contradicted by deploy config** | `render.yaml` sets `FEATURE_MERCHANT_OF_RECORD=true` |
| `PLATFORM_REVIEW.md` (2026-08-16) | **Mostly current** on MoR product shape | Still the clearest "is this a business platform?" write-up |
| `site/index.html` + `site/pricing.html` + `site/docs/BRIEF.md` | **Wrong on price** | Site: Pro $15/mo + **4%**. App: Pro **$19.99/mo + 7%** (same rate as Free) |

---

## 0. One-screen answer

The signup → guardian → application path **exists and is request-specced**.
A teen can get an account, tick "I'm 13 or older," apply, and (under
production MoR) operate a venture **without a parent**. That is not the
bottleneck.

What actually strands teens:

1. **Interest never becomes an account.** The marketing waitlist writes to
   Redis. There is no "you're in" email, magic link, or cohort code.
2. **A human still has to click twice after they apply.** Approve, then
   activate, then (unless a cohort auto-vets) operator vetting. Until those
   fire, `Event#accepts_payments?` is false and the storefront is dark.
3. **The parent loop is one email with a 7-day token and no reminder.**
   Under MoR that does not block selling; it **does** block getting paid.
   Under Connect (the default in tests and in most docs) it blocks operating
   at all.
4. **The site sells a plan the app does not have.** Parents who read
   fuime.com will expect 4% + $15. The app charges 7% + $19.99 and unlocks
   a second venture + API keys — not a rate cut.
5. **There is no teen-facing growth loop.** Referrals are an admin
   attribution tool. Discover is a shop window, not a marketplace. School
   is a plan an admin assigns, not a channel a teacher can open.

Engineering is no longer "build payments from zero." It is "close the
holes in a funnel that already has most of the pipes."

---

## 1. How a teen actually gets on (as of this commit)

Production posture from `render.yaml`: `FEATURE_MERCHANT_OF_RECORD=true`,
`FUIME_MINIMUM_OPERATOR_AGE=13`. Tests and local default: MoR **off**,
age floor **16** if the env var is unset.

```
visitor ──► marketing waitlist (Redis)     ✗ no bridge into the app
     or
visitor ──► POST /logins (email code)
              │
              ▼
         onboarding: name + phone + "I'm 13 or older"
              │  (no DOB; cannot self-assert 18+)
              ▼
         home / apply  ── guardian invite is deferred ──► /guardian/new
              │
              ▼
         Event::Application wizard
              │  submit may auto-invite parent (cosigner_email)
              │  cohort code may auto approve + activate + vet
              ▼
         admin: approve ──► admin: activate ──► admin: operator vetting
              │
              ▼
         publish offer ──► guest checkout ──► ledger (code; Stripe E2E unproven)
              │
              ▼
         payout: guardian (MoR: Plaid destination + weekly batch;
                           Connect: guardian-owned Stripe + PayoutRequest)
```

Canonical specs:

- `spec/requests/family_signup_flow_spec.rb` — login → attestation → invite
  → parent accept → activation seam. Does **not** assert mail delivery.
- `spec/requests/fuime_full_business_flow_spec.rb` — apply → sell → pay
  under MoR with `PaymentLinkService` stubbed at the Stripe boundary.

### 1.1 What is done

| Step | State | Where |
|---|---|---|
| Email login codes | Works; `deliver_now`; failure is user-visible | `LoginCodeService::Request` |
| Age gate at signup | 13+ checkbox, write-once; settings cannot mint `adult_18_plus` | `UsersController#update`, `User#attest_minor_13_plus!` |
| Under-13 with a real DOB | Refused | `User#minimum_age_requirement` |
| Deferred guardian | After profile save, teen is **in the product** with a flash; hard gate waits | `UsersController#update`; Connect: `User#permitted_to_operate_business?`; MoR: that predicate is `true` |
| Manual + auto guardian invite | Pending row, 7-day token, `GuardianshipMailer#invite` | `GuardianshipsController`, `Fuime::GuardianInviteService`, `Event::Application` `mark_submitted` |
| Parent accept | Checkbox = 18+ attestation + versioned agreement + IP/UA | `GuardianshipsController#accept` — the **only** user-facing path to `adult_18_plus` |
| Activation refuses guardianless minor | **Connect only** | `Event::Application#activation_blockers` |
| Selling eligibility | Vetting + category allowlist (`services`, `digital`) + age floor | `Fuime::OperatorEligibility`, `Event#selling_blockers` |
| Cohort fast-path | Auto approve / activate / vet; still cannot waive eligibility | `Fuime::CohortAdmission` |
| Family plan Checkout | Guardian-only; Stripe Billing on the **platform** account | `Fuime::BillingController`, `Fuime::SubscriptionService` |
| Admin comp / revoke / cancel-at-Stripe | Built | `/admin/subscriptions`, user admin Family plan panel |
| Storefront + Discover + `/pay/…` | Built; Discover is listed published offers only | `DiscoverController`, `Fuime::Offer` |
| Guardian overview page | Exists (`/guardianships`); not a money dashboard | `guardianships/index.html.erb` |

### 1.2 What is broken, incomplete, or a dead end

See §7. The load-bearing ones for *getting teens on*:

- Waitlist has no admit path.
- After submit, copy says "Waiting on Fuime to finish setting up your account"
  (`Event::Application#next_step`) until an admin activates — unless a
  cohort admitted them.
- Operator vetting defaults to `unvetted`; unvetted ventures cannot take
  payment.
- Guardian invite expires in 7 days (`Guardianship::INVITE_VALID_FOR`);
  `find_by_token` returns nil; there is no reminder mailer and no stale
  queue (`ADMIN_OPS_QUEUES.md` §3).
- Accepting a guardianship proves **email control + a checkbox**, not
  identity (`Guardianship#accept!` says so in the model).
- No parent notified when the venture is live and Stripe/Plaid setup is
  the next click.
- Cohorts are the best existing growth lever and **are not in `Admin::Nav`**
  — `/admin/cohorts` exists; you have to know the URL.

---

## 2. Plans / pricing / subscriptions

### What exists

| Plan | Rate | Monthly | How a family gets it | What it actually unlocks |
|---|---|---|---|---|
| **Free** | **7%** | $0 | Default on new ventures | One non-school venture. No `api_keys`. |
| **Pro (family)** | **7%** (same as Free) | **$19.99** (`FUIME_PRO_MONTHLY_CENTS`) | Guardian pays at `/billing`, or admin comps | Unlimited ventures + developer API. **Not a rate cut.** |
| **Standard** | **5%** | **$15** theoretically | Admin assigns the STI row | Lower take-rate. Monthly fee has **no checkout UI**. |
| **Founders** | 0% | $0 | Admin assigns | Hand-onboarded waiver. |
| **School** | 0% | Invoiced offline | Admin assigns | Institution is the adult; students skip per-teen guardian via `institutionally_vouched_for?`. |

`Event#billing_plan` resolves Pro at read time from the guardian's
`Fuime::Subscription` (`active` / `trialing`). It does **not** rewrite
`event_plans` rows. Lapse loses the second-venture slot and API keys;
it must **never** freeze payouts or the ledger (`Fuime::Subscription`
header comment). That floor is correct. Do not "improve" it by locking
a teenager out of their own money.

Admin surfaces that work: venture plan picker, `/admin/subscriptions`
(the old §4 queue), grant/revoke comp, cancel-in-Stripe for paid rows.
`grant_family_plan!` refuses anyone who is not `known_adult?` or `staff?`.

### What is stubbed or missing

| Gap | Current state |
|---|---|
| Per-venture Standard $15/mo | `SubscriptionService` can bill `event:`; **no controller calls it** |
| Family-plan purchase E2E | SETUP_NOTES (2026-08-21): **no family has ever completed Stripe Checkout** |
| Success-banner copy | `/billing` still says every venture "drops to 7%" — implies a discount that does not exist (`app/views/fuime/billing/show.html.erb`) |
| `Event::Plan::Free` comment | Still narrates "drop to 4% with the family plan" (`app/models/event/plan/free.rb`) |
| `Event::Plan::Pro` comment | Header still says "the lower 4% rate" even though `REVENUE_FEE` now equals Free |
| Marketing site | `site/index.html`, `site/pricing.html`, `site/docs/BRIEF.md`: Pro **$15 + 4%** |
| Dunning | Stripe-side retries only; admin can see `past_due` / `incomplete` |

**Why this blocks teens:** the first venture does not need Pro. The
**second** venture does. A founder who outgrows lawn-mowing-plus-tutoring
hits `activation_blockers` ("the free plan includes one venture") and
the only self-serve unlock is a parent Checkout that has never been
proven live, advertised at the wrong price on the public site.

---

## 3. Payment systems (maturity vs teen-facing gaps)

Two architectures, one flag.

| | Connect (`FEATURE_MERCHANT_OF_RECORD` off) | MoR (on — `render.yaml`) |
|---|---|---|
| Customer pays | Direct charge on guardian's connected account | Checkout on **Fuime's** platform account |
| Fuime's cut | `application_fee_amount` | Ledger payable + 50¢ floor (`FUIME_MINIMUM_FEE_CENTS`) |
| Teen can sell without parent? | **No** — `permitted_to_operate_business?` is `!needs_guardian?` | **Yes** — predicate short-circuits `true` |
| Teen can get paid without parent? | No — guardian owns the Stripe account | No — `Fuime::PayableAssessment` + payout destination |
| Payout rail | `PayoutRequest` → Stripe payout, guardian approves | Weekly `Fuime::PayoutBatch`, admin generate/approve/mark-paid, operator Plaid |
| Cards | Flipper `fuime_cards_2026_08_04`, test-mode or sponsor-banking only | Same; live Stripe keys refuse issuing (`card_issuing_permitted?`) |

Ledger write path is shared: `Fuime::VentureLedger` → existing HCB
`CanonicalTransaction` pipeline. `Fuime::PayablesLedger` is a **presenter**
for the operator UI under MoR, not a second book.

### Exercised vs documentation-derived

- **Exercised (2026-08-14, test mode):** Connect Checkout *shape* —
  Stripe accepted the direct charge and stored `application_fee_amount`.
  Record: `EMBEDDED_CONNECT.md` §7.
- **Not exercised:** webhooks → ledger line, embedded onboarding,
  payouts, disputes, family-plan Billing, MoR Checkout against a real
  session, Plaid collect. The Stripe CLI blocker in §7 (CLI logged into
  a Hack Club test account, not Fuime's) is still the stated reason.

`LAUNCH_SPEC.md` §4.1 is the most dangerous stale page in the repo for
this topic. Payments are not "called from nowhere." They are called
from `Fuime::CheckoutsController`. The remaining hole is **proof**, not
absence.

### Teen-facing payment gaps (not architecture homework)

1. After activation, nothing walks the teen to "publish one offer and
   text the `/pay/slug/offer` link." Discover's empty state already
   says that; the signed-in home page does not own the same sentence.
2. Signed-in **minor buyers** are refused at checkout
   (`Fuime::CheckoutsController`, 2026-08-21). Guests can pay. A
   classmate logged into their own Fuime account cannot buy from a
   friend. That is a growth own-goal at school events.
3. Under MoR, first sale can happen before a parent exists; first
   **payout** cannot. `Fuime::FounderProgress#guardian_pending?` is
   correctly split out of the sell funnel so Friday organisers chase
   sales, not parents — but nobody emails the parent that the kid
   now has money waiting.
4. Cards will not put spend in a teen's pocket on live Stripe. Do not
   sell cards in onboarding until that is a real rail.

---

## 4. Onboarding friction

### Email / deliverability

Login **is** the product: no code, no session. Codes send `deliver_now`
via SMTP (Resend in `render.yaml`). Guardian invites are `deliver_later`
on the `critical` queue — a down worker silently parks every new family.

LAUNCH_SPEC §3.4: this has already broken production once. DKIM / SPF /
DMARC on the sending domain is still a go/no-go checkbox, not a code
task. There is no spec that opens a mailbox; `family_signup_flow_spec`
reads the code from the database.

Missing mail that loses teens:

| Mail | Status |
|---|---|
| Login code | Built |
| Guardian invite / accepted | Built |
| Invite expiring (day 3 / day 6) | **Not built** |
| Waitlist "you're in" | **Not built** (site promises "one email when it's your turn") |
| Application approved / activated | Application mailer exists; vetting-approved does not ping the teen |
| "Your kid made a sale — set up payouts" | **Not built** |

### KYC / identity

Guardianship accept = email + "I am 18 and I am this child's guardian."
`GuardianVerification` is a **consent record** for the cards-enabled
Connect profile (forward to Stripe, persist method / timestamp / IP,
never the image — L4). Default payments-only Connect profile lets
Stripe collect KYC inside embedded onboarding; that path is unexercised
and **retired in the UI under MoR**.

This is a legal/trust gap more than a "first account" gap. It becomes a
teen-growth gap the first time a self-signed pair (`#self_signed_signals`)
is the only adult on a payout.

### Age gates

| Gate | Mechanism | Failure mode |
|---|---|---|
| Platform floor | 13+ checkbox; DOB if present | Honor system without DOB. Anyone can tick 13+. |
| Operator floor | `FUIME_MINIMUM_OPERATOR_AGE`, default **16**, clamped at 13 | Production sets 13. A deploy that forgets the env var makes every attestation-only teen **unable to sell** ("we'd need their date of birth"). |
| Adult | Guardian-accept checkbox only | Settings form cannot promote a user to 18+. |
| Unknown age | Fail-closed as minor | Correct. |

### UI dead ends

- Approved application, no event: "Waiting on Fuime…" — accurate, and a
  graveyard if Applications / vetting queues are not staffed.
- Expired guardian link: generic invalid; resend lives on
  `/guardianships` and `/users/:id/admin`. The teen has to know that.
- `/billing` as a teen: "ask your parent" — correct (L2), but only
  useful if a guardian exists and is `known_adult?`.
- Multi-guardian Connect provision job refuses unless exactly one
  overseeing guardian (`ProvisionConnectAccountJob`).
- Cohorts: blank `business_category` can auto-admit a founder who then
  fails `OperatorEligibility`. Roster `FounderProgress#next_action` is
  the only surfacing.
- No Flipper / flag that "opens signup." The app is already open.
  The waitlist is a parallel list, not a gate.

---

## 5. Growth / retention loops

| Loop | State | Verdict |
|---|---|---|
| **Waitlist** | Capture + `/admin/waitlist` (CSV, charts). Read-only. | Acquisition without conversion. |
| **Cohorts** | `Fuime::Cohort` + admission + `/admin/cohorts/:id` roster | **Best existing lever** for a room of teens. Not in admin nav. |
| **Referrals** | `Referral::Program` / `Link` / `Attribution`; admin builder; New Teenagers leaderboard | Ops attribution. Zero teen UI, zero reward. |
| **Directory** | Public ventures, newest / A–Z | Discovery of *businesses*, not a way to join. |
| **Discover** | Listed published offers → `/b/:slug` | Helps buyers, not founders. Empty state tells the founder to share a pay link — that *is* the n=1 loop. |
| **Learn** | Templates + lessons | Pre-signup education; does not create an account. |
| **School** | Plan + awards + funding service | Channel is real; onboarding is manual; Stripe top-up unverified. |
| **Drips / reactivation** | None that are Fuime-specific | Homepage task list is pull, not push. |
| **Family / sibling** | Pro covers every ward | Works only after a guardian exists and pays or is comped. |

There is no "invite a classmate" control. Every incremental teen is
currently paid acquisition, a Friday cohort, or a founder who already
knew the URL.

---

## 6. Admin tools that unblock a specific teen today

**What you can already do (no new code):**

1. `/users/:id/admin` — resend / revoke guardianship; comp or revoke
   family plan.
2. Venture settings admin — assign **Founders** (0%) or **School**
   (institutional adult, no per-student guardian).
3. Applications queue — activate; blockers are now shown instead of a 500.
4. Operator vetting queue — the badge is work owed; unvetted = cannot sell.
5. `/admin/cohorts` — **bookmark this.** Create the cohort *before* the
   event; the roster's `next_action` column is the run-of-show.
6. `/admin/subscriptions` — `past_due` / stalled `incomplete`.
7. `/admin/waitlist` — export CSV and mail people **by hand**.

**What you cannot do without a console or a hunt:**

| Need | Status |
|---|---|
| All pending guardianships older than 7 days | Unbuilt (`ADMIN_OPS_QUEUES.md` §3) |
| Connected accounts that cannot charge | Unbuilt (§2) |
| Failed `PayoutRequest`s | Unbuilt (§1). Payout **batches** have a nav badge. |
| Admit a waitlist email into the app | Unbuilt |
| One-click guardian exemption (non-school) | Does not exist; school plan and staff are the exemptions |
| Age waiver | No admin toggle (attestation is the surface) |
| Find cohorts from the console chrome | Route exists; **no nav item** |

---

## 7. Ranked punch list

Ordered by **teens stranded × how often it happens × whether code can
fix it**. Size is engineering shape (S/M/L), not calendar time.
Legal/counsel items are marked so they are not mistaken for a weekend
PR.

### P0 — Teens who already showed up never become operators

#### G1. Waitlist → account bridge
- **Current:** `site/api/waitlist.js` → Redis; `Admin::WaitlistController`
  is read-only. Site copy promises one email when it's their turn.
- **Why it blocks teens:** every warm lead dies in a list ops can export
  but cannot admit.
- **Size:** M
- **Next:** Admin "invite next N" that sends a login-ready email (same
  code flow as `LoginsController`) and optionally stamps a cohort.
  Do not build a second auth system.

#### G2. Staff the three human gates — or default Friday to cohorts
- **Current:** submit → `under_review` → `admin_approve` → `admin_activate`
  → `operator_vetting`. Cohort admission collapses the three when a code
  is on the application. Cohorts are missing from `Admin::Nav`.
- **Why it blocks teens:** after a complete application the product
  tells them to wait on Fuime. That wait is unbounded and silent if
  queues are not worked.
- **Size:** S (nav + runbook) / M (self-serve activate for low-risk
  services + 13+ with a guardian or school)
- **Next:** Put Cohorts in the Organizations nav with a live count.
  Write a one-page ops runbook: "solo applicant = Applications +
  Vetting; event = cohort code on the review step." Do not remove
  vetting until offer-level moderation exists (`PLATFORM_REVIEW.md`).

#### G3. Marketing price ≠ app price (L8)
- **Current:** site and BRIEF sell Standard 7% / Pro $15 + **4%**.
  App: Free 7%, Pro **$19.99 + 7%**, Standard 5% + theoretical $15.
- **Why it blocks teens:** the conversion conversation is with the
  **parent**. A $15/4% pitch that becomes $20/7% at `/billing` is how
  you lose the household, not the kid.
- **Size:** S (copy) — or a founder pricing decision, then copy
- **Next:** Pick one sentence and ship it in `site/index.html`,
  `site/pricing.html`, `site/docs/BRIEF.md`, `Event::Plan::{Free,Pro}`
  comments, and the `/billing` success banner. Until then, fuime.com
  is lying about the product that exists.

#### G4. Login email is a single point of failure
- **Current:** Resend SMTP; codes `deliver_now`; no mailbox assertion
  in the family spec. Domain auth still an open `LAUNCH_SPEC` §3.4 box.
- **Why it blocks teens:** broken email means **nobody can sign in**,
  including the parent who holds the invite.
- **Size:** S (ops) / M (staging canary that requests a code and
  watches Resend)
- **Next:** Confirm DKIM/SPF/DMARC on the live domain; alert on
  `LoginCodeService` send failures (already reported to
  `Rails.error`). This outranks new features every time it is red.

### P1 — Teens who have an account never finish activation

#### G5. Guardian invite is fire-and-forget
- **Current:** one `GuardianshipMailer#invite`; token 7 days; resend
  only from `/guardianships` or user admin. No stale queue.
- **Why it blocks teens:** under **Connect**, they cannot operate.
  under **MoR**, they can sell and then **cannot get paid** — a worse
  story at dinner. `FounderProgress#guardian_pending?` is the Friday
  tell; nothing equivalent emails the parent.
- **Size:** M
- **Next:** Build `ADMIN_OPS_QUEUES.md` §3 (pending >7d badge + resend)
  and Day-3 / Day-6 reminder mailers. Same `resend_invite!` — do not
  invent a second token.

#### G6. Parent is not walked to the money-setup click
- **Current:** Connect: teen sees payment-setup status; only the
  guardian can finish embedded onboarding. MoR: Plaid payout method
  is a separate page. No "venture is live, do this next" mail.
- **Why it blocks teens:** the founder thinks they are done; the
  storefront stays dark (Connect) or payouts stay skipped (MoR).
- **Size:** M
- **Next:** On `activate_event!` and on first payable sale, email the
  overseeing guardian a single deep link (`PaymentSetupsController` or
  `PayoutMethodsController`). Teen dashboard banner with the same URL
  to text dad.

#### G7. Operator age floor vs 13+ checkbox
- **Current:** production `FUIME_MINIMUM_OPERATOR_AGE=13`. Code default
  if unset is **16**. Attestation-only users have no DOB;
  `OperatorEligibility#age_blocker` then asks for one when the floor
  is above 13.
- **Why it blocks teens:** a forgotten env var turns every checkbox
  teen into "cannot sell" after a "successful" activation.
- **Size:** S
- **Next:** Keep `13` in `render.yaml` (already there). Fail boot or
  show a huge admin banner when the effective floor ≠ the documented
  production value. Collect DOB later if counsel wants a real COPPA
  proof; do not silently raise the floor.

#### G8. Family-plan Checkout never proven
- **Current:** controller, portal, webhook handler, admin queue — all
  real. SETUP_NOTES: zero completed purchases. Banner implies a rate
  drop.
- **Why it blocks teens:** second venture is the first time a
  successful founder hits a paywall. If the webhook never marks
  `active`, they stay stuck even after the parent paid.
- **Size:** M
- **Next:** One test-mode guardian Checkout + `customer.subscription.*`
  against **Fuime's** Stripe CLI account (same §7 account-mismatch
  fix). Then fix the banner: Pro sells unlimited ventures + API, not 4%.

#### G9. Signed-in teens cannot buy from each other
- **Current:** `Fuime::CheckoutsController` refuses `minor_or_unknown_age?`
  buyers; guests pass.
- **Why it blocks teens:** school-event demand is other logged-in
  teens. They hit a wall their guest friends do not.
- **Size:** S (product decision + copy) or M (allow with a guest-like
  path that does not attach the minor as a cardholder)
- **Next:** Decide: sign them out of checkout, or allow guest-equivalent
  payment while signed in. Do not invent teen-to-teen credit.

### P2 — Money path that makes the first sale believable

#### G10. Webhooks → ledger not proven on Fuime's Stripe account
- **Current:** `ConnectPaymentRecorder` / MoR checkout / subscription
  handler written; `EMBEDDED_CONNECT.md` §7 still blocked on CLI login.
- **Why it blocks teens:** a founder who takes a payment and sees
  nothing on the venture page churns and tells the group chat.
- **Size:** M (ops + fix-what-breaks) — not a greenfield build
- **Next:** Fuime Stripe CLI → dual `stripe listen` → one Connect
  charge **and** one MoR charge → assert the CanonicalTransaction.
  This is still the highest-leverage *engineering* hour in the repo.
  It does not by itself put more teens on; it keeps the ones who sell.

#### G11. Failed payout / disabled-account queues
- **Current:** models record failure; nobody is shown it
  (`ADMIN_OPS_QUEUES.md` §1–§2). Batch nav exists for MoR weekly runs.
- **Why it blocks teens:** "I made money and Fuime ghosted me" is
  how you lose a cohort, not a ticket.
- **Size:** M
- **Next:** Build those two queues after G10, not before — they
  display webhook-fed state.

#### G12. Cards in live mode
- **Current:** category allowlist + issuing service; Flipper off;
  live keys refuse issue.
- **Why it blocks teens:** it does **not**, today. Do not put cards
  on the homepage. Spend is not the reason they cannot sign up.
- **Size:** L, and gated on Stripe Issuing answers
  (`LEGAL_RESEARCH.md` open questions)
- **Next:** Leave the flag off. Revisit after G10 and written Stripe
  answers.

### P3 — Loops that create the *next* teen

#### G13. Teen referral / "bring a founder"
- **Current:** admin referral programs only.
- **Why it blocks teens:** viral coefficient is ~0. Every seat is
  hustled.
- **Size:** M
- **Next:** One personal link that attributes a *new* teenager
  (reuse `Referral::Attribution`). Reward in something you already
  have — Founders 0% for a month, or a waitlist bump — **after**
  counsel looks at "paying a minor to recruit." Do not ship cash
  referral bonuses to 15-year-olds on a hunch.

#### G14. School as a self-serve channel
- **Current:** School plan + awards work; funding top-up unverified;
  no "start a school program" flow.
- **Why it blocks teens:** one teacher is fifty founders. Today that
  teacher needs an admin to assign a plan.
- **Size:** L (product + Stripe) / S (manual playbook)
- **Next:** A written school playbook + Founders-Weekend-style
  cohort beats building a teacher portal. Verify
  `SchoolFundingService` when you next have the Stripe CLI.

#### G15. Discover / directory as acquisition
- **Current:** working, deliberately unranked (legal).
- **Why it blocks teens:** it won't get you the *first* sale. It
  might get the fifth buyer.
- **Size:** S to leave alone
- **Next:** On the venture home, a single "Copy pay link" for the
  primary offer. Do not add recommendations.

### P4 — Will halt growth the moment money is real (not "more teens" this week)

These are true and they are **not** why the waitlist is not converting.
Do not let them steal the week if the goal is seats.

| # | Gap | Size | Why it is not P0 for *seats* |
|---|---|---|---|
| G16 | Counsel memo §1.1 + Stripe written answers | — (letters) | Blocks live money and cards; app already signs teens up in test/MoR |
| G17 | Guardian identity **verification** (vendor, not checkbox) | L | Blocks the "Parent-signed ✓" claim and payout trust, not account creation |
| G18 | COPPA parent export / delete | L | Blocks a honest public launch; not the waitlist bridge |
| G19 | Counsel-drafted ToS / Privacy / Guardian agreement | M once words exist | Plumbing records version + IP today; words are still Fuime's |
| G20 | Error tracking / on-call | M | You will not hear about a red login path until a parent emails |
| G21 | Offer moderation under MoR | M | Fuime is the seller of record for whatever a vetted teen types later |
| G22 | Disputes / clawback | L | Loses Fuime money (`PLATFORM_REVIEW.md`); does not block signup |

---

## 8. Suggested build order if the goal is "more teens on"

Do these, in this order, and refuse work that is not on the list until
the first four are shipped or explicitly killed.

1. **G3** — tell the truth on fuime.com and `/billing` (S, copy).
2. **G1** — waitlist invite email + optional cohort stamp (M).
3. **G2** — Cohorts in admin nav + a one-page "how we admit" runbook (S).
4. **G5** — guardian reminder + stale queue (M).
5. **G10** — Fuime Stripe CLI webhook pass (M, but unlocks G8 and G11).

Everything else in §7 is real. None of it puts a teenager on the
product faster than "the people who already gave you their email can
log in" and "the people who already applied are not waiting on a URL
only you know."

### Explicitly do *not* start

- Rewriting Connect vs MoR. Production is MoR in `render.yaml`. Update
  `CLAUDE.md` CURRENT POSITION when someone is touching that file;
  do not rebuild the money model to feel like the docs.
- Cards, Whop, or a new ledger.
- A ranked marketplace on `/discover`.
- Renaming `Event` → Venture in the schema (Rule 6).
- Deleting HCB modules (Rule 2).

---

## 9. How to unstick one teen tomorrow morning

No deploy required.

1. Find them on `/users/:id/admin`.
2. If guardianship is pending — **Resend invite**. If the parent email
   is wrong, revoke and have the teen re-invite.
3. If the application is approved and there is no venture — **Activate**
   (read the blocker list; usual cause is no guardian under Connect, or
   the one-venture wall).
4. If the venture exists and cannot sell — **Operator vetting → approve**,
   then check `selling_blockers` (category `crafts`/`food`/`other` will
   never pass; `services`/`digital` will).
5. If they need a second venture — **Comp family plan** on that same
   admin page (adult/staff only).
6. If this is an event, not a solo — open `/admin/cohorts` and work
   the roster `next_action` column left to right.

If you do that for the people already in Redis and in Applications,
you will have more teens on the product than any new screen will create
this month.
